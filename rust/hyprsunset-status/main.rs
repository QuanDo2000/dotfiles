use std::{
    env,
    fs::OpenOptions,
    io::{self, Read},
    os::{unix::fs::OpenOptionsExt, unix::process::CommandExt},
    path::PathBuf,
    process::{Command, Output, Stdio},
    sync::mpsc,
    thread,
    time::Duration,
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const MAX_CONFIG_BYTES: u64 = 1024 * 1024;
const LINUX_O_NONBLOCK: i32 = 0o4000;
const MAX_COMMAND_OUTPUT: u64 = 128;
unsafe extern "C" {
    fn kill(pid: i32, signal: i32) -> i32;
}

fn kill_child_group(pid: i32) {
    // process_group(0) gives each helper a distinct process group.
    let _ = unsafe { kill(-pid, 9) };
}

fn bounded_command(program: &str, args: &[&str]) -> io::Result<Output> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .process_group(0);
    let mut child = command.spawn()?;
    let group = match i32::try_from(child.id()) {
        Ok(pid) => pid,
        Err(_) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::other("invalid child pid"));
        }
    };
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut child = child;
        let result = (|| -> io::Result<Output> {
            let mut stdout = Vec::new();
            child
                .stdout
                .take()
                .ok_or_else(|| io::Error::other("missing stdout"))?
                .take(MAX_COMMAND_OUTPUT + 1)
                .read_to_end(&mut stdout)?;
            if stdout.len() as u64 > MAX_COMMAND_OUTPUT {
                return Err(io::Error::other("helper output exceeds 128 bytes"));
            }
            Ok(Output {
                status: child.wait()?,
                stdout,
                stderr: Vec::new(),
            })
        })();
        if result.is_err() {
            kill_child_group(group);
            let _ = child.wait();
        }
        let _ = sender.send(result);
    });
    match receiver.recv_timeout(Duration::from_secs(2)) {
        Ok(result) => result,
        Err(mpsc::RecvTimeoutError::Timeout) => {
            kill_child_group(group);
            let _ = receiver.recv_timeout(Duration::from_secs(1));
            Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("{program} timed out"),
            ))
        }
        Err(mpsc::RecvTimeoutError::Disconnected) => Err(io::Error::other("helper worker failed")),
    }
}

fn config_path() -> Result<PathBuf> {
    let root = match env::var_os("XDG_CONFIG_HOME") {
        Some(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from(env::var_os("HOME").ok_or("HOME is unset")?).join(".config"),
    };
    Ok(root.join("hypr/hyprsunset.conf"))
}

fn settings() -> Result<(String, String, String)> {
    let mut day = String::new();
    let mut night = String::new();
    let mut temperature = String::new();
    let mut file = match OpenOptions::new()
        .read(true)
        .custom_flags(LINUX_O_NONBLOCK)
        .open(config_path()?)
    {
        Ok(file) => file,
        Err(err) if err.kind() == io::ErrorKind::NotFound => {
            return Ok(("07:00".into(), "20:00".into(), "4500".into()));
        }
        Err(err) => return Err(err.into()),
    };
    // A symlink to a regular Home Manager config is allowed; FIFO/device reads are not.
    if !file.metadata()?.is_file() {
        return Ok(("07:00".into(), "20:00".into(), "4500".into()));
    }
    let mut content = String::new();
    file.by_ref()
        .take(MAX_CONFIG_BYTES + 1)
        .read_to_string(&mut content)?;
    if content.len() as u64 > MAX_CONFIG_BYTES {
        return Err("hyprsunset config exceeds 1 MiB".into());
    }
    for line in content.lines() {
        let mut fields = line.split_whitespace();
        let (Some(key), Some(eq)) = (fields.next(), fields.next()) else {
            continue;
        };
        if eq != "=" {
            continue;
        }
        let value = fields.next().unwrap_or("");
        match key {
            "time" if day.is_empty() => day = value.to_owned(),
            "time" if night.is_empty() => night = value.to_owned(),
            "temperature" => temperature = value.to_owned(),
            _ => (),
        }
    }
    if day.is_empty() {
        day = "07:00".into();
    }
    if night.is_empty() {
        night = "20:00".into();
    }
    if temperature.is_empty() {
        temperature = "4500".into();
    }
    Ok((day, night, temperature))
}

fn now_arg() -> Result<String> {
    if let Some(arg) = env::args_os().nth(1)
        && !arg.is_empty()
    {
        return Ok(arg
            .into_string()
            .map_err(|_| "time argument is not UTF-8")?);
    }
    let output = bounded_command("date", &["+%H:%M"])?;
    if !output.status.success() {
        return Err("date failed".into());
    }
    Ok(String::from_utf8(output.stdout)?
        .trim_end_matches('\n')
        .to_owned())
}

fn service_running() -> bool {
    match env::var_os("HYPRSUNSET_RUNNING") {
        Some(value) if !value.is_empty() => value == "true",
        _ => bounded_command(
            "systemctl",
            &["--user", "is-active", "--quiet", "hyprsunset.service"],
        )
        .is_ok_and(|output| output.status.success()),
    }
}

fn json_string(value: &str) -> String {
    let mut output = String::with_capacity(value.len() + 2);
    output.push('"');
    for ch in value.chars() {
        match ch {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            c if c <= '\u{001f}' => output.push_str(&format!("\\u{:04x}", c as u32)),
            c => output.push(c),
        }
    }
    output.push('"');
    output
}

fn run() -> Result<()> {
    let (day, night, temperature) = settings()?;
    let now = now_arg()?;
    let (text, tooltip, class) = if !service_running() {
        (
            "󰅙",
            "Night light service is inactive".to_owned(),
            "disabled",
        )
    } else if now < day || now >= night {
        (
            "󰖔",
            format!("Night light: {temperature}K\nNormal colors at {day}"),
            "active",
        )
    } else {
        (
            "󰖙",
            format!("Night light: inactive\nWarm colors at {night}"),
            "inactive",
        )
    };
    println!(
        "{{\"text\":{},\"tooltip\":{},\"class\":{}}}",
        json_string(text),
        json_string(&tooltip),
        json_string(class)
    );
    Ok(())
}

fn main() {
    if let Err(err) = run() {
        eprintln!("hyprsunset-status: {err}");
        std::process::exit(1);
    }
}
