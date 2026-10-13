"""Exercise media setup with isolated commands; never install real packages."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MediaSetupTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name); self.bin = self.root / 'bin'; self.bin.mkdir()
        self.log = self.root / 'calls'
        release = self.root / 'os-release'; release.write_text('ID=fedora\nVERSION_ID=44\n')
        self.helper = self.root / 'media.sh'
        self.helper.write_text((ROOT / 'tools/install_media_fedora.sh').read_text()
                               .replace('/etc/os-release', str(release))
                               .replace('/run/ostree-booted', str(self.root / 'ostree')))
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        INSTALLED='libavcodec-free,libva-intel-media-driver', DECODER='hevc')
        self.program('sudo', "raise SystemExit(1 if os.environ.get('FAIL_SWAP') and 'swap' in sys.argv else 0)")
        self.program('rpm', "raise SystemExit(0 if sys.argv[-1] in os.environ['INSTALLED'].split(',') else 1)")
        self.program('ffmpeg', "print(' VFS..D ' + os.environ['DECODER'] + ' decoder')")

    def program(self, name, body):
        p = self.bin / name
        p.write_text('#!' + sys.executable + '\nimport os,sys,json\n'
                     f'with open({str(self.log)!r}, "a") as f: f.write(json.dumps([{name!r}, *sys.argv[1:]]) + "\\n")\n' + body)
        p.chmod(0o755)

    def run_helper(self, mode='--install'):
        return subprocess.run(['bash', str(self.helper), mode], env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_repositories_and_targeted_replacements(self):
        result = self.run_helper(); self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn(['sudo', 'dnf', 'swap', '-y', 'libavcodec-free', 'libavcodec-freeworld'], calls)
        self.assertIn(['sudo', 'dnf', 'swap', '-y', 'libva-intel-media-driver', 'intel-media-driver'], calls)
        self.assertTrue(any('https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm' in c for c in calls))
        self.assertFalse(any('--allowerasing' in c for c in calls))

    def test_existing_repositories_are_preserved(self):
        self.env['INSTALLED'] = 'rpmfusion-free-release,rpmfusion-nonfree-release'
        self.assertEqual(self.run_helper('--repositories-only').returncode, 0)
        self.assertFalse(any(c[:3] == ['sudo', 'dnf', 'install'] for c in self.calls()))

    def test_failed_swap_stops_before_driver_install(self):
        self.env['FAIL_SWAP'] = '1'
        self.assertNotEqual(self.run_helper().returncode, 0)
        self.assertFalse(any('intel-media-driver' in c and 'install' in c for c in self.calls()))

    def test_missing_hevc_is_a_failure(self):
        self.env['DECODER'] = 'vp9'
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('HEVC software decoder verification failed', result.stderr)

    def test_invalid_mode_changes_nothing(self):
        self.assertEqual(self.run_helper('--unknown').returncode, 2)
        self.assertFalse(self.log.exists())
