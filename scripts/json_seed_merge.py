#!/usr/bin/env python3
import json
import os
import sys
import tempfile

live_path, seed_path, apply_path, label, override_keys = sys.argv[1:]
live_overrides = set(filter(None, override_keys.split(",")))


def load(path):
    with open(path, encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def missing_from_seed(live, seed):
    missing = {}
    for key, value in live.items():
        if key not in seed or (key in live_overrides and seed[key] != value):
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


def write_json(path, value):
    directory = os.path.dirname(path) or "."
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".json-seed-", text=True)
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


try:
    compare_path = apply_path or seed_path
    live_config = load(live_path)
    seed_config = load(compare_path)
    missing = missing_from_seed(live_config, seed_config)
except Exception as exc:
    print(f"Warning: failed to compare {label} config with tracked seed: {exc}", file=sys.stderr)
    sys.exit(0)

if missing:
    if apply_path:
        write_json(apply_path, merge_missing(seed_config, missing))
        print(f"Applied {label} live config additions to tracked seed: {apply_path}")
    else:
        print(f"{label} live config has settings missing from the tracked seed.")
        print("Review these additions:")
        print(json.dumps(missing, indent=2))
