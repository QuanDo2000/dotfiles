#!/usr/bin/env python3
import math
import os
import re
import sys
import tempfile
import tomllib

live_path, seed_path, apply_path = sys.argv[1:]


def load(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def missing_from_seed(live, seed):
    missing = {}
    for key, value in live.items():
        if key == "hooks":
            continue
        if key not in seed:
            missing[key] = value
        elif isinstance(value, dict) and isinstance(seed[key], dict):
            nested = missing_from_seed(value, seed[key])
            if nested:
                missing[key] = nested
    return missing


def merge_missing(seed, missing):
    for key, value in missing.items():
        if isinstance(value, dict) and isinstance(seed.get(key), dict):
            merge_missing(seed[key], value)
        else:
            seed[key] = value
    return seed


def quote(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return str(value) if math.isfinite(value) else quote(str(value))
    if isinstance(value, str):
        return quote(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{toml_key(key)} = {toml_value(item)}" for key, item in value.items()) + " }"
    return quote(str(value))


def toml_key(key):
    return key if re.fullmatch(r"[A-Za-z0-9_-]+", key) else quote(key)


def table_name(path):
    return ".".join(toml_key(part) for part in path)


def write_toml(path, value):
    directory = os.path.dirname(path) or "."
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".codex-seed-", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(render(value))
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def render(table):
    lines = []

    def write(line=""):
        lines.append(line)

    def render_table(current, path=()):
        scalar_lines = []
        child_tables = []
        for key, value in current.items():
            if isinstance(value, dict):
                child_tables.append((key, value))
            else:
                scalar_lines.append(f"{toml_key(key)} = {toml_value(value)}")

        if scalar_lines:
            if path:
                write(f"[{table_name(path)}]")
            lines.extend(scalar_lines)
            write()

        for key, value in child_tables:
            render_table(value, (*path, key))

    render_table(table)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines) + "\n"


try:
    seed_compare_path = apply_path or seed_path
    live_config = load(live_path)
    seed_config = load(seed_compare_path)
    missing = missing_from_seed(live_config, seed_config)
except Exception as exc:
    print(f"Warning: failed to compare Codex config with tracked seed: {exc}", file=sys.stderr)
    sys.exit(0)

if missing:
    if apply_path:
        write_toml(apply_path, merge_missing(seed_config, missing))
        print(f"Applied Codex live config additions to tracked seed: {apply_path}")
    else:
        print("Codex live config has settings missing from the tracked seed.")
        print("Review these additions for config/shared/ai/codex/config.toml:")
        print()
        print(render(missing), end="")
