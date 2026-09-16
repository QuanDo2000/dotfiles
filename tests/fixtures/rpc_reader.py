"""Bounded JSONL reads for the Unix Pi RPC integration tests."""

import json
import os
import select
import time


class RpcReader:
    def __init__(self, stream):
        self.stream = stream
        self.buffer = b''

    def read_until(self, predicate, timeout=15):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b'\n' in self.buffer:
                line, self.buffer = self.buffer.split(b'\n', 1)
                event = json.loads(line)
                if predicate(event):
                    return event
                continue
            # TextIOWrapper.readline() can hide subsequent records from select().
            ready, _, _ = select.select([self.stream], [], [], max(0, deadline - time.monotonic()))
            if not ready:
                break
            chunk = os.read(self.stream.fileno(), 65536)
            if not chunk:
                break
            self.buffer += chunk
        raise RuntimeError('expected RPC event not observed')
