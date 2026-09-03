#!/usr/bin/env python3
import copy
import sys

from common import load_json, same_json, write_json

live_path, seed_path, apply_path, base_path = sys.argv[1:]

REDUNDANT_DEFAULTS = {
    "enableSkillCommands": True,
    "skills": ["~/.agents/skills"],
    "editorPaddingX": 0,
    "outputPad": 1,
    "transport": "auto",
}
RUNTIME_KEYS = {"lastChangelogVersion"}
missing = object()


def normalize(config, keep_runtime=False):
    runtime = {}
    for key, value in REDUNDANT_DEFAULTS.items():
        if same_json(config.get(key), value):
            del config[key]
    for key in RUNTIME_KEYS:
        if keep_runtime and key in config:
            runtime[key] = config[key]
        config.pop(key, None)
    return runtime


def merge_missing(target, source):
    for key, value in source.items():
        if key not in target:
            target[key] = copy.deepcopy(value)
        elif isinstance(value, dict) and isinstance(target[key], dict):
            merge_missing(target[key], value)


def resolve(live, seed, base):
    if same_json(seed, base):
        return live
    if same_json(live, base):
        return seed
    if isinstance(live, dict) and isinstance(seed, dict) and isinstance(base, dict):
        merged = {}
        for key in sorted(live.keys() | seed.keys() | base.keys()):
            value = resolve(live.get(key, missing), seed.get(key, missing), base.get(key, missing))
            if value is not missing:
                merged[key] = value
        return merged
    return seed


live = load_json(live_path)
seed = load_json(apply_path or seed_path)
live_original = copy.deepcopy(live)
seed_original = copy.deepcopy(seed)
runtime = normalize(live, keep_runtime=True)
normalize(seed)
try:
    base = load_json(base_path)
    base_original = copy.deepcopy(base)
    normalize(base)
    base_exists = True
except FileNotFoundError:
    base = {}
    base_original = None
    base_exists = False

if base_exists:
    resolved = resolve(live, seed, base)
else:
    resolved = copy.deepcopy(seed)
    merge_missing(resolved, live)
    if "defaultModel" in live:
        resolved["defaultModel"] = copy.deepcopy(live["defaultModel"])

live_resolved = copy.deepcopy(resolved)
live_resolved.update(runtime)

baseline = resolved if apply_path else seed
if not same_json(live_resolved, live_original):
    write_json(live_path, live_resolved, prefix=".json-live-", preserve_mode=True, expected=live_original)
if apply_path and not same_json(resolved, seed_original):
    write_json(apply_path, resolved, prefix=".json-seed-", preserve_mode=True, expected=seed_original)
if not same_json(baseline, base_original):
    write_json(base_path, baseline, prefix=".json-base-", preserve_mode=True, expected=base_original)

if apply_path:
    print(f"Applied Pi config changes to tracked seed: {apply_path}")
else:
    print("Applied Pi config changes to live config; tracked seed was not writable")
