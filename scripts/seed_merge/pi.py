#!/usr/bin/env python3
import json
import sys

from common import load_json, write_json

live_path, seed_path, apply_path = sys.argv[1:]


def missing_from_seed(live, seed):
    missing = {}
    for key, value in live.items():
        if key not in seed or (key == "defaultModel" and seed[key] != value):
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


try:
    compare_path = apply_path or seed_path
    live_config = load_json(live_path)
    seed_config = load_json(compare_path)
    missing = missing_from_seed(live_config, seed_config)
except Exception as exc:
    print(f"Warning: failed to compare Pi config with tracked seed: {exc}", file=sys.stderr)
    sys.exit(0)

if missing:
    if apply_path:
        write_json(apply_path, merge_missing(seed_config, missing), prefix=".json-seed-")
        print(f"Applied Pi config changes to tracked seed: {apply_path}")
    else:
        print("Pi live config has changes missing from the tracked seed.")
        print("Review these additions:")
        print(json.dumps(missing, indent=2))
