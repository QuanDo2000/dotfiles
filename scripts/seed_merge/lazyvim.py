#!/usr/bin/env python3
import copy
import sys

from common import load_json, write_json

live_path, seed_path, apply_path, base_path = sys.argv[1:]
managed_keys = {"extras", "news", "version"}
missing = object()


def merge_missing(target, source):
    for key, value in source.items():
        if key not in target:
            target[key] = copy.deepcopy(value)
        elif isinstance(value, dict) and isinstance(target[key], dict):
            merge_missing(target[key], value)


def resolve(live, seed, base):
    if seed == base:
        return live
    if live == base:
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
try:
    base = load_json(base_path)
    base_exists = True
except (OSError, ValueError):
    base = {}
    base_exists = False

resolved = copy.deepcopy(seed)
merge_missing(resolved, live)

for key in managed_keys:
    live_value = live.get(key, missing)
    if base_exists:
        value = resolve(live_value, seed.get(key, missing), base.get(key, missing))
    else:
        value = seed.get(key, missing)
    if value is missing:
        resolved.pop(key, None)
    else:
        resolved[key] = copy.deepcopy(value)

if apply_path:
    write_json(apply_path, resolved, prefix=".lazyvim-seed-", preserve_mode=True)
write_json(live_path, resolved, prefix=".lazyvim-seed-", preserve_mode=True)
write_json(base_path, resolved, prefix=".lazyvim-seed-", preserve_mode=True)
if apply_path:
    print("Applied LazyVim config changes to live config and tracked seed")
else:
    print("Applied LazyVim config changes to live config; tracked seed was not writable")
