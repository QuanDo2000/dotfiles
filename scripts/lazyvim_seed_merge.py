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
base_exists = os.path.isfile(base_path)
base = load(base_path) if base_exists else copy.deepcopy(seed)
resolved = copy.deepcopy(seed)
merge_missing(resolved, live)

for key in managed_keys if base_exists else ():
    live_value = live.get(key, missing)
    seed_value = seed.get(key, missing)
    base_value = base.get(key, missing)
    value = seed_value if seed_value != base_value else live_value
    if value is missing:
        resolved.pop(key, None)
    else:
        resolved[key] = copy.deepcopy(value)

if apply_path:
    write_json(apply_path, resolved)
write_json(live_path, resolved)
write_json(base_path, resolved)
print("Applied LazyVim config changes to live config and tracked seed")
