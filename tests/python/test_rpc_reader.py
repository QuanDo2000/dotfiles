import json
import os
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'fixtures'))
from rpc_reader import RpcReader


@unittest.skipIf(os.name == 'nt', 'Unix pipe select semantics')
class RpcReaderTests(unittest.TestCase):
    def setUp(self):
        read_fd, self.write_fd = os.pipe()
        self.stream = os.fdopen(read_fd, 'r')
        self.addCleanup(self.stream.close)
        self.addCleanup(os.close, self.write_fd)
        self.reader = RpcReader(self.stream)

    def test_coalesced_events_are_consumed_without_another_write(self):
        os.write(self.write_fd, b'{"skip":true}\n{"match":true}\n{"next":true}\n')
        try:
            self.assertEqual(self.reader.read_until(lambda event: event.get('match'), timeout=0.1), {'match': True})
            self.assertEqual(self.reader.read_until(lambda event: event.get('next'), timeout=0.1), {'next': True})
        except RuntimeError as error:
            self.fail(f'already-written events must not time out: {error}')

    def test_partial_record_still_times_out(self):
        os.write(self.write_fd, b'{"partial":')
        with self.assertRaisesRegex(RuntimeError, 'expected RPC event'):
            self.reader.read_until(lambda event: True, timeout=0.05)
        os.write(self.write_fd, b'true}\n')
        self.assertEqual(self.reader.read_until(lambda event: True, timeout=0.1), {'partial': True})

    def test_unicode_line_separator_is_not_a_record_boundary(self):
        event = {'text': 'before\u2028after'}
        os.write(self.write_fd, (json.dumps(event, ensure_ascii=False) + '\r\n').encode())
        self.assertEqual(self.reader.read_until(lambda event: True, timeout=0.1), event)


if __name__ == '__main__':
    unittest.main()
