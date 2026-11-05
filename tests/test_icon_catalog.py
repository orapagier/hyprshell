import importlib.util
import json
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'config/quickshell/helpers/icon-catalog.py'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


icons = load('icon_catalog', HELPER)
prototype = load('icon_catalog_prototype', ROOT / 'tools/icon_catalog_prototype.py')


def next_message(process, timeout=5):
    if not select.select([process.stdout], [], [], timeout)[0]:
        raise AssertionError('Timed out waiting for a catalog line')
    return json.loads(process.stdout.readline())


def wait_for(process, predicate, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        message = next_message(process, max(0.1, deadline - time.monotonic()))
        if predicate(message):
            return message
    raise AssertionError('Timed out waiting for the expected catalog state')


class ProductionCatalogTests(unittest.TestCase):
    def start(self, folders):
        process = subprocess.Popen(
            [sys.executable, '-B', str(HELPER), '--folders-json', json.dumps(folders)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

        def cleanup():
            if process.poll() is None:
                process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()

        self.addCleanup(cleanup)
        return process

    def test_initial_stream_and_live_update(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'theme/apps'
            folder.mkdir(parents=True)
            (folder / 'one.svg').write_text('one')
            process = self.start([str(folder)])
            first = next_message(process)
            self.assertEqual((first['version'], first['revision']), (1, 0))
            self.assertEqual(first['catalog']['one'], icons.file_url(folder / 'one.svg'))
            (folder / 'two.png').write_text('two')
            second = next_message(process)
            self.assertEqual(second['revision'], 1)
            self.assertEqual(second['catalog']['two'], icons.file_url(folder / 'two.png'))

    def test_missing_folder_is_created_and_watched(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'theme/apps'
            process = self.start([str(folder)])
            first = next_message(process)
            self.assertEqual(first['catalog'], {})
            folder.mkdir(parents=True)
            (folder / 'later.svg').write_text('later')
            second = next_message(process)
            self.assertIn('later', second['catalog'])

    def test_rewrite_and_removal_publish_new_catalogs(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'theme/apps'
            folder.mkdir(parents=True)
            icon = folder / 'icon.svg'
            icon.write_text('one')
            process = self.start([str(folder)])
            first = next_message(process)
            self.assertIn('icon', first['catalog'])
            icon.write_text('two')
            wait_for(process, lambda message: message['revision'] > first['revision']
                     and 'icon' in message['catalog'])
            icon.unlink()
            removed = wait_for(process, lambda message: 'icon' not in message['catalog'])
            self.assertNotIn('icon', removed['catalog'])

    def test_removed_folder_is_recreated_and_watched(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / 'theme/apps'
            folder.mkdir(parents=True)
            (folder / 'gone.svg').write_text('gone')
            process = self.start([str(folder)])
            self.assertIn('gone', next_message(process)['catalog'])
            shutil.rmtree(folder)
            wait_for(process, lambda message: 'gone' not in message['catalog'])
            folder.mkdir()
            (folder / 'back.svg').write_text('back')
            wait_for(process, lambda message: 'back' in message['catalog'])

    def test_prototype_and_production_scan_agree(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / 'first space', Path(directory) / 'second'
            first.mkdir()
            second.mkdir()
            for name in ('same.png', 'same.svg', 'same.xpm', 'A.svg', 'a.svg',
                         'plus+name.svg', 'space name.svg', 'hash#name.svg',
                         'percent%name.svg', 'unicode-é.svg', 'unicode-É.svg',
                         '.hidden.svg', 'UPPER.SVG', 'broken.svg'):
                if name == 'broken.svg':
                    (first / name).symlink_to(first / 'missing')
                else:
                    (first / name).write_text('fixture')
            (second / 'same.xpm').write_text('later folder')
            folders = [first, second]
            self.assertEqual(icons.scan(folders), prototype.scan(folders))


if __name__ == '__main__':
    unittest.main()
