"""Ensure password preflight rejects common Windows failures without leaking inputs."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'util/check-lab-password.py'
spec = importlib.util.spec_from_file_location('password_check', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PasswordTests(unittest.TestCase):
    def test_preflight(self):
        for password in ('', 'short1!', 'onlylowercase', 'TwoCategories', 'Administrator42!', 'Valid123!\n'):
            with self.subTest(password=password):
                self.assertFalse(module.valid(password))
        self.assertTrue(module.valid('Example-test-42'))
        self.assertTrue(module.valid('ExampleTest42'))
        self.assertFalse(module.valid('MyOperator42!', 'Operator'))

    def test_failure_does_not_print_secret(self):
        password = 'privatebutinvalid'
        result = subprocess.run([sys.executable, str(SCRIPT)], input=password,
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(password, result.stdout + result.stderr)
