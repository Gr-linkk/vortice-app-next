"""Offline checks: invalid cleanup scope must stop before Git/backend access."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class CleanupOptionsTest(unittest.TestCase):
    def run_cleanup(self, directory, *args, output=None):
        env = dict(os.environ)
        env.pop('VORTICE_E2E_OUTPUT', None)
        if output is not None:
            env['VORTICE_E2E_OUTPUT'] = str(output)
        return subprocess.run(
            [sys.executable, str(Path(__file__).with_name('cleanup_fixtures.py').resolve()), *args],
            cwd=directory, env=env, capture_output=True, text=True,
        )

    def test_no_scope_does_not_default_to_historical_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_cleanup(directory)
            self.assertEqual(result.returncode, 2)
            self.assertIn('Specify --manifest-dir', result.stderr)

    def test_missing_environment_scope_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_cleanup(directory, output=Path(directory) / 'missing')
            self.assertEqual(result.returncode, 2)
            self.assertIn('Manifest directory must already exist', result.stderr)

    def test_existing_receipt_is_preserved_before_any_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / 'receipt.json'
            receipt.write_text('previous evidence', encoding='utf-8')
            result = self.run_cleanup(
                directory, '--manifest-dir', directory, '--receipt', str(receipt),
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn('Receipt already exists', result.stderr)
            self.assertEqual(receipt.read_text(encoding='utf-8'), 'previous evidence')


if __name__ == '__main__':
    unittest.main()
