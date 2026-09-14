"""Exercise Packer's shutdown gate without contacting Proxmox."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "packer/common/scripts/wait-for-shutdown.sh"


class ShutdownGateTests(unittest.TestCase):
    def run_gate(self, scenario):
        with tempfile.TemporaryDirectory() as directory:
            curl = Path(directory) / "curl"
            curl.write_text("""#!/usr/bin/env bash
set -eu
url=${!#}
if [ "$SCENARIO" = http_error ]; then exit 22; fi
case "$url" in
  */qemu)
    case "$SCENARIO" in
      missing) echo '{"data":[]}' ;;
      duplicate) echo '{"data":[{"vmid":114,"name":"tpl-ws2025"},{"vmid":116,"name":"tpl-ws2025"}]}' ;;
      *) echo '{"data":[{"vmid":109,"name":"tpl-ws2025","template":1},{"vmid":114,"name":"tpl-ws2025"}]}' ;;
    esac ;;
  */114/status/current)
    case "$SCENARIO" in
      timeout) echo '{"data":{"status":"running"}}' ;;
      transition)
        if [ -f "$POLL_MARKER" ]; then
          echo '{"data":{"status":"stopped"}}'
        else
          touch "$POLL_MARKER"
          echo '{"data":{"status":"running"}}'
        fi ;;
      invalid) echo '{"data":null}' ;;
      *) echo '{"data":{"status":"stopped"}}' ;;
    esac ;;
  *) exit 99 ;;
esac
""")
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                       SCENARIO=scenario, PKR_VAR_proxmox_username="test@pve!test",
                       PKR_VAR_proxmox_token="test-token", POLL_MARKER=f"{directory}/polled")
            return subprocess.run(
                ["bash", str(SCRIPT), "https://example.invalid/api2/json", "proxmox", "tpl-ws2025",
                 "5" if scenario == "transition" else "1"],
                env=env, text=True, capture_output=True, timeout=10,
            )

    def test_stopped_build_excludes_existing_template(self):
        result = self.run_gate("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Build VM 114 is stopped", result.stdout)

    def test_waits_for_running_build_to_stop(self):
        result = self.run_gate("transition")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Build VM 114 is stopped", result.stdout)

    def test_failures_never_report_success(self):
        for scenario in ("missing", "duplicate", "http_error", "invalid", "timeout"):
            with self.subTest(scenario=scenario):
                result = self.run_gate(scenario)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("is stopped", result.stdout)


if __name__ == "__main__":
    unittest.main()
