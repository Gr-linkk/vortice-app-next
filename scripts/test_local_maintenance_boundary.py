"""Executable separation gates for the experimental maintenance package."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'experiments/maintenance_local'


class LocalMaintenanceBoundary(unittest.TestCase):
    def test_guard_checks_dedicated_identity_and_service_free_startup(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/local-maintenance.sh'), 'check'],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotRegex((APP / 'pubspec.lock').read_text(), r'(?i)supabase|firebase')

    def test_no_signer_generation_or_release_path(self):
        helper = (ROOT / 'scripts/local-maintenance.sh').read_text()
        self.assertNotIn('genkeypair', helper)
        self.assertIn('VORTICE_MAINTENANCE_KEYSTORE', helper)
        gradle = (APP / 'android/app/build.gradle.kts').read_text()
        self.assertIn('signingConfig = null', gradle)
        self.assertIn('endsWith("Release")', gradle)

    def test_local_entrypoint_uses_separate_storage(self):
        entrypoint = (APP / 'lib/main.dart').read_text()
        self.assertIn('VORTICE_MAINTENANCE_DATA', entrypoint)
        self.assertIn('maintenance-local-v1', entrypoint)
        self.assertNotIn('VORTICE_LAB_DATA', entrypoint)
        self.assertNotRegex(entrypoint, r'(?i)supabase|firebase')

    def test_progress_domain_has_no_runtime_dependencies(self):
        projection = (APP / 'lib/job_progress.dart').read_text()
        self.assertNotRegex(
            projection,
            r"(?:import|export)\s+['\"](?:dart:(?:io|ffi|ui)|"
            r"package:(?:flutter|sqlite3|flutter_rust_bridge)|"
            r"(?:[^'\"]*/)?(?:lab_store|local_sync|office_backup|"
            r"work_progress_reader)\.dart|src/rust/)",
        )
        reader = (APP / 'lib/work_progress_reader.dart').read_text()
        self.assertNotRegex(reader, r'\.evidence\.status\(')
        self.assertNotRegex(
            reader,
            r'\.(?:execute|update|attachPhoto|submit|approve|returnSubmission|'
            r'selectJob|setSetting|importBundle)\(',
        )


if __name__ == '__main__':
    unittest.main()
