"""Exercise the launcher without contacting the running desktop."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


LAUNCHER = Path(__file__).resolve().parents[1] / "bin/start-quickshell-bar"


class PanelStartupTests(unittest.TestCase):
    def run_launcher(self, scenario):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake = root / "quickshell"
            fake.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
root = pathlib.Path(os.environ["FAKE_SESSION"])
args = sys.argv[1:]
scenario = os.environ["SCENARIO"]
if args[0] == "--no-duplicate":
    count = root / "launches"
    n = int(count.read_text()) + 1 if count.exists() else 1
    count.write_text(str(n))
    if scenario != "restart" or n > 1:
        (root / "running").touch()
elif args[0] == "ipc":
    print("true" if (root / "running").exists() else "false")
elif args[0] == "list":
    print('{"pid": 123}')
elif args[0] == "kill":
    (root / "killed").touch()
''')
            bus = root / "busctl"
            bus.write_text('''#!/usr/bin/env python3
import os, pathlib
root = pathlib.Path(os.environ["FAKE_SESSION"])
count = root / "owner_checks"
n = int(count.read_text()) + 1 if count.exists() else 1
count.write_text(str(n))
scenario = os.environ["SCENARIO"]
print("u 999" if scenario == "wrong-owner" or (scenario == "delayed-owner" and n == 1) else "u 123")
''')
            fake.chmod(0o755)
            bus.chmod(0o755)
            launcher = root / "start"
            # Bound the failure test without waiting the production 30 seconds.
            launcher.write_text(LAUNCHER.read_text().replace("SECONDS + 30", "SECONDS + 5"))
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       XDG_STATE_HOME=str(root / "state"), XDG_CONFIG_HOME=str(root / "config"),
                       FAKE_SESSION=str(root), SCENARIO=scenario)
            result = subprocess.run(["bash", str(launcher)], env=env,
                                    capture_output=True, text=True, timeout=15)
            return result, int((root / "launches").read_text()), (root / "killed").exists()

    def test_retries_when_old_instance_unregisters_after_first_launch(self):
        result, launches, killed = self.run_launcher("restart")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertGreaterEqual(launches, 2)
        self.assertFalse(killed)

    def test_waits_for_notification_ownership(self):
        result, _, killed = self.run_launcher("delayed-owner")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(killed)

    def test_rejects_wrong_notification_owner(self):
        result, _, killed = self.run_launcher("wrong-owner")
        self.assertEqual(result.returncode, 1)
        self.assertTrue(killed)


if __name__ == "__main__":
    unittest.main()
