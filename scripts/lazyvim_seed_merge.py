#!/usr/bin/env python3
import copy
import json
import os
import sys
import tempfile

live_path, seed_path, apply_path, base_path = sys.argv[1:]
managed_keys = {"extras", "news", "version"}
missing = object()


def load(path):
    with open(path, encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


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
        for key in live.keys() | seed.keys() | base.keys():
            value = resolve(live.get(key, missing), seed.get(key, missing), base.get(key, missing))
            if value is not missing:
                merged[key] = value
        return merged
    return seed


def write_json(path, value):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".lazyvim-seed-", text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            json.dump(value, file, indent=2)
            file.write("\n")
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


live = load(live_path)
seed = load(apply_path or seed_path)
try:
    base = load(base_path)
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
        value = live_value
    if value is missing:
        resolved.pop(key, None)
    else:
        resolved[key] = copy.deepcopy(value)

if apply_path:
    write_json(apply_path, resolved)
write_json(live_path, resolved)
write_json(base_path, resolved)
if apply_path:
    print("Applied LazyVim config changes to live config and tracked seed")
else:
    print("Applied LazyVim config changes to live config; tracked seed was not writable")
