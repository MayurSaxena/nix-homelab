"""Check lifecycle ordering and guards against a scripted Proxmox API."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "util/lab-vm.sh"
VMS = "nodes/proxmox/qemu"
VM = {"name": "test01", "vmid": 301, "tags": "adhoc;lab"}


def step(method, path, data=None, **kwargs):
    return dict(method=method, path=path, data=data, **kwargs)


def task(method, path, label, fields=None, result="OK"):
    return [step(method, path, f"UPID:{label}", fields=fields or {}),
            step("GET", f"nodes/proxmox/tasks/UPID:{label}/status",
                 {"status": "running"}),
            step("GET", f"nodes/proxmox/tasks/UPID:{label}/status",
                 {"status": "stopped", "exitstatus": result})]


class LifecycleTests(unittest.TestCase):
    def run_cli(self, arguments, steps):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "steps.json"
            fixture.write_text(json.dumps(steps))
            curl = root / "curl"
            curl.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
from urllib.parse import unquote, urlsplit
p = Path(os.environ['API_FIXTURE'])
steps = json.loads(p.read_text())
if not steps: sys.exit('Unexpected API request: ' + sys.argv[-1])
s = steps.pop(0)
method = sys.argv[sys.argv.index('-X') + 1]
if method in ('GET', 'DELETE'): assert '--get' in sys.argv, 'Query parameters must not become a request body'
path = unquote(urlsplit(sys.argv[-1]).path).split('/api2/json/', 1)[1]
assert (method, path) == (s['method'], s['path']), (method, path, s)
fields = dict(sys.argv[i+1].split('=', 1) for i, a in enumerate(sys.argv) if a == '--data-urlencode')
for key, value in s.get('fields', {}).items(): assert fields.get(key) == value, (key, fields)
for key in s.get('absent', []): assert key not in fields, fields
p.write_text(json.dumps(steps))
if s.get('http_error'): sys.exit(22)
print(json.dumps({'data': s['data']}))
""")
            curl.chmod(0o755)
            sops = root / "sops"
            sops.write_text("#!/usr/bin/env bash\ncase \"$3\" in *public-key*) echo 'ssh-ed25519 AAAA test';; *) echo test-password;; esac\n")
            sops.chmod(0o755)
            env = dict(os.environ, PATH=f"{directory}:{os.environ['PATH']}",
                       API_FIXTURE=str(fixture), PROXMOX_VE_AUTH_TICKET="test",
                       PROXMOX_VE_CSRF_PREVENTION_TOKEN="test",
                       PROXMOX_VE_ENDPOINT="https://example.invalid/",
                       LAB_POLL_INTERVAL="0", LAB_TASK_TIMEOUT="5")
            result = subprocess.run(["bash", str(SCRIPT), *arguments], env=env,
                                    text=True, capture_output=True, timeout=15)
            self.assertEqual(json.loads(fixture.read_text()), [], result.stderr)
            return result

    def test_golden_replacement_waits_for_delete_and_create(self):
        steps = [step("GET", VMS, [VM]), step("GET", f"{VMS}/301/snapshot", [{"name": "golden"}])]
        steps += task("DELETE", f"{VMS}/301/snapshot/golden", "delete")
        steps += task("POST", f"{VMS}/301/snapshot", "create", {"snapname": "golden", "vmstate": "0"})
        result = self.run_cli(["snapshot", "test01"], steps)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_failed_snapshot_delete_prevents_creation(self):
        steps = [step("GET", VMS, [VM]), step("GET", f"{VMS}/301/snapshot", [{"name": "golden"}])]
        steps += task("DELETE", f"{VMS}/301/snapshot/golden", "delete", result="disk error")
        result = self.run_cli(["snapshot", "test01"], steps)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("completed", result.stdout)

    def test_revert_waits_for_stop_rollback_and_start(self):
        steps = [step("GET", VMS, [VM]), step("GET", f"{VMS}/301/snapshot", [{"name": "golden"}]),
                 step("GET", f"{VMS}/301/status/current", {"status": "running"})]
        for suffix in ("status/stop", "snapshot/golden/rollback", "status/start"):
            steps += task("POST", f"{VMS}/301/{suffix}", suffix.replace("/", "-"))
        result = self.run_cli(["revert", "test01"], steps)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_guards_refuse_non_disposable_guests(self):
        for tags in ("", "lab", "adhoc", "adhoc;lab;terraform", "adhoc;lab;template"):
            with self.subTest(tags=tags):
                result = self.run_cli(["despawn", "test01"], [step("GET", VMS, [dict(VM, tags=tags)])])
                self.assertNotEqual(result.returncode, 0)

    def test_despawn_waits_for_deletion(self):
        steps = [step("GET", VMS, [VM]), step("GET", f"{VMS}/301/status/current", {"status": "stopped"})]
        steps += task("DELETE", f"{VMS}/301", "destroy", {"purge": "1"})
        result = self.run_cli(["despawn", "test01"], steps)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_spawn_attaches_metadata_and_uses_linux_user(self):
        template = {"name": "tpl-debian", "vmid": 900, "template": 1}
        steps = [step("GET", VMS, [template]),
                 step("GET", f"{VMS}/900/config", {"ostype": "l26", "net0": "virtio=AA,bridge=vmbr0"}),
                 step("GET", "cluster/nextid", 301)]
        steps += task("POST", f"{VMS}/900/clone", "clone", {"newid": "301", "name": "test01", "full": "1", "pool": "lab"})
        steps += [step("POST", f"{VMS}/301/config", None, fields={"tags": "adhoc;lab"}),
                  step("GET", f"{VMS}/301/config", {"net0": "virtio=BB,bridge=production,tag=10"}),
                  step("POST", f"{VMS}/301/config", None, fields={
                      "ide2": "local-zfs:cloudinit", "ciuser": "debian", "ipconfig0": "ip=dhcp",
                      "sshkeys": "ssh-ed25519%20AAAA%20test",
                      "net0": "virtio=BB,bridge=vmbr0,tag=90"})]
        steps += task("POST", f"{VMS}/301/status/start", "start")
        result = self.run_cli(["spawn", "tpl-debian", "test01", "debian"], steps)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unknown_linux_user_fails_before_clone(self):
        steps = [step("GET", VMS, [{"name": "tpl-debian", "vmid": 900, "template": 1}]),
                 step("GET", f"{VMS}/900/config", {"ostype": "l26"})]
        result = self.run_cli(["spawn", "tpl-debian", "test01"], steps)
        self.assertNotEqual(result.returncode, 0)

    def test_invalid_windows_password_fails_before_clone(self):
        steps = [step("GET", VMS, [{"name": "tpl-windows", "vmid": 900, "template": 1}]),
                 step("GET", f"{VMS}/900/config", {"ostype": "win11"})]
        result = self.run_cli(["spawn", "tpl-windows", "test01"], steps)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("password preflight failed", result.stderr)

    def test_http_failure_is_not_an_empty_success(self):
        result = self.run_cli(["snapshot", "test01"], [step("GET", VMS, http_error=True)])
        self.assertNotEqual(result.returncode, 0)

    def test_named_snapshot_is_not_overwritten(self):
        steps = [step("GET", VMS, [VM]), step("GET", f"{VMS}/301/snapshot", [{"name": "exercise"}])]
        result = self.run_cli(["snapshot", "test01", "exercise"], steps)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
