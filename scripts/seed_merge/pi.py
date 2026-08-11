#!/usr/bin/env python3
import json
import sys

from common import load_json, write_json

live_path, seed_path, apply_path = sys.argv[1:]

REDUNDANT_DEFAULTS = {
    "enableSkillCommands": True,
    "skills": ["~/.agents/skills"],
    "editorPaddingX": 0,
    "outputPad": 1,
    "transport": "auto",
}
RUNTIME_KEYS = {"lastChangelogVersion"}


def remove_keys(config, keys):
    changed = False
    for key, value in keys.items():
        if config.get(key) == value:
            del config[key]
            changed = True
    return changed


def missing_from_seed(live, seed, root=True):
    missing = {}
    for key, value in live.items():
        if root and (key == "subagents" or key in RUNTIME_KEYS):
            continue
        if key not in seed or (key == "defaultModel" and seed[key] != value):
            missing[key] = value
        elif isinstance(value, dict) and isinstance(seed[key], dict):
            nested = missing_from_seed(value, seed[key], root=False)
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


try:
    compare_path = apply_path or seed_path
    live_config = load_json(live_path)
    seed_config = load_json(compare_path)
    live_changed = remove_keys(live_config, REDUNDANT_DEFAULTS)
    seed_changed = remove_keys(seed_config, REDUNDANT_DEFAULTS)
    for key in RUNTIME_KEYS:
        if key in seed_config:
            del seed_config[key]
            seed_changed = True
    missing = missing_from_seed(live_config, seed_config)
except Exception as exc:
    print(f"Warning: failed to compare Pi config with tracked seed: {exc}", file=sys.stderr)
    sys.exit(0)

if live_changed:
    write_json(live_path, live_config, prefix=".json-live-", preserve_mode=True)

if apply_path and (missing or seed_changed):
    write_json(
        apply_path,
        merge_missing(seed_config, missing),
        prefix=".json-seed-",
        preserve_mode=True,
    )
    print(f"Applied Pi config changes to tracked seed: {apply_path}")
elif missing:
    print("Pi live config has changes missing from the tracked seed.")
    print("Review these additions:")
    print(json.dumps(missing, indent=2))
