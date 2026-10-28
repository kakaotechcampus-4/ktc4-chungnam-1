import unittest
from stt_server.progress import progress


class ProgressTest(unittest.TestCase):
    def test_success(self):
        with self.assertLogs('stt_server.progress', level='INFO') as logs:
            with progress('asr', 'synthetic-trace'):
                pass
        self.assertIn('status=started', logs.output[0])
        self.assertIn('status=completed elapsed_s=', logs.output[1])

    def test_failure_hides_exception_contents(self):
        with self.assertLogs('stt_server.progress', level='INFO') as logs:
            with self.assertRaises(RuntimeError):
                with progress('asr', 'synthetic-trace'):
                    raise RuntimeError('synthetic-secret')
        self.assertIn('status=failed', logs.output[-1])
        self.assertNotIn('synthetic-secret', ' '.join(logs.output))
        self.assertTrue(all(r.exc_info is None for r in logs.records))
