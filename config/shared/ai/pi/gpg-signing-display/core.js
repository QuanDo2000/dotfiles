const { spawnSync } = require("node:child_process");

const NON_SIGNING_TAG_OPTIONS = new Set([
  "-d",
  "-l",
  "-v",
  "--contains",
  "--delete",
  "--list",
  "--merged",
  "--no-contains",
  "--no-merged",
  "--points-at",
  "--verify",
]);

const GIT_OPTIONS_WITH_VALUES = new Set([
  "-C",
  "-c",
  "--config-env",
  "--git-dir",
  "--namespace",
  "--work-tree",
]);

function needsInteractiveGpg(command) {
  for (const segment of String(command || "").split(/&&|\|\||[;\n]/)) {
    const words = segment.trim().split(/\s+/);
    let index = 0;
    while (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[index] || "")) index += 1;
    if (words[index] !== "git") continue;

    index += 1;
    while (String(words[index] || "").startsWith("-")) {
      const option = words[index].split("=")[0];
      index += 1;
      if (GIT_OPTIONS_WITH_VALUES.has(option) && !words[index - 1].includes("=")) index += 1;
    }

    const subcommand = words[index];
    const args = words.slice(index + 1);
    if (args.includes("--no-gpg-sign") || args.includes("--no-sign")) continue;
    if (subcommand === "commit") return true;
    if (subcommand === "tag" && args.length > 0
      && !args.some((word) => NON_SIGNING_TAG_OPTIONS.has(word.split("=")[0]))) return true;
    if (["cherry-pick", "merge", "rebase", "revert"].includes(subcommand)
      && args.some((word) => /^-S.+/.test(word) || word === "-S" || word.startsWith("--gpg-sign"))) return true;
  }
  return false;
}

function gpgSigningDisplayExtension(pi, dependencies = {}) {
  const platform = dependencies.platform || process.platform;
  const run = dependencies.spawnSync || spawnSync;

  pi.on("session_start", (_event, sessionCtx) => {
    const bash = dependencies.createBashTool(sessionCtx.cwd);

    pi.registerTool({
      ...bash,
      async execute(toolCallId, params, signal, onUpdate, ctx) {
        if (platform === "win32" || ctx?.mode !== "tui" || !needsInteractiveGpg(params.command)) {
          return bash.execute(toolCallId, params, signal, onUpdate, ctx);
        }
        if (signal?.aborted) throw new Error("Command aborted");

        const exitCode = await ctx.ui.custom((tui, _theme, _keybindings, done) => {
          tui.stop();
          let result;
          try {
            process.stdout.write("\x1b[2J\x1b[H");
            result = run(process.env.SHELL || "/bin/sh", ["-c", params.command], {
              cwd: ctx.cwd,
              env: process.env,
              stdio: "inherit",
            });
          } finally {
            tui.start();
            tui.requestRender(true);
          }
          done(result?.status ?? 1);
          return { render: () => [], invalidate() {} };
        });

        if (exitCode !== 0) throw new Error(`Command exited with code ${exitCode}`);
        return {
          content: [{ type: "text", text: "Interactive signing command completed successfully." }],
          details: undefined,
        };
      },
    });
  });
}

module.exports = gpgSigningDisplayExtension;
module.exports.needsInteractiveGpg = needsInteractiveGpg;
