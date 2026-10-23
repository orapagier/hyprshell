"""Exercise the real Rust CLI and QML picker with isolated settings and HTTP fixtures."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / 'config/quickshell/helpers/hyprweather'
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import weather

LOCATION = {'name': 'Miagao, Iloilo, Western Visayas, Philippines', 'latitude': 10.64, 'longitude': 122.23}
FORECAST = {'current': {'temperature_2m': 29.5, 'apparent_temperature': 34, 'relative_humidity_2m': 81,
                       'precipitation': 0.4, 'weather_code': 80, 'wind_speed_10m': 12, 'wind_gusts_10m': 19,
                       'time': '2026-10-21T09:15'},
            'daily': {'temperature_2m_max': [31], 'temperature_2m_min': [24],
                      'precipitation_probability_max': [80], 'sunrise': ['2026-10-21T05:40'],
                      'sunset': ['2026-10-21T17:30']},
            'hourly': {'time': ['2026-10-21T09:00', '2026-10-21T10:00', '2026-10-21T11:00', '2026-10-21T12:00'],
                       'temperature_2m': [29.5, 30, 31, 30], 'precipitation_probability': [80, 60, 40, 20]},
            'timezone_abbreviation': 'GMT+8'}


class WeatherValidationTests(unittest.TestCase):
    def test_saved_location_validation(self):
        self.assertEqual(weather.validate({'version': 1, 'location': LOCATION})['location'], LOCATION)
        for value in (91, True, float('nan')):
            with self.assertRaises(ValueError):
                weather.validate({'version': 1, 'location': dict(LOCATION, latitude=value)})

    def test_location_sync_and_generated_file_exclusions(self):
        import deployment
        import github_sync
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, repo = root / 'config', root / 'repo'
            (config / 'hyprshell').mkdir(parents=True)
            (config / 'hyprshell/weather.json').write_text(json.dumps({'version': 1, 'location': LOCATION}))
            github_sync.snapshot_managed_files(repo, config, root / 'home')
            self.assertEqual(json.loads((repo / 'config/hyprshell/weather.json').read_text())['location'], LOCATION)
            self.assertTrue(deployment.protected('config/hyprshell/weather.json'))
            self.assertTrue(github_sync.excluded('hyprweather'))
            self.assertTrue(deployment.ignored(Path('config/quickshell/helpers/hyprweather')))


@unittest.skipUnless(BINARY.is_file(), 'Build the Rust weather helper first')
class WeatherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'bin').mkdir()
        self.calls = self.root / 'calls'
        self.fail = self.root / 'fail'
        curl = self.root / 'bin/curl'
        curl.write_text('#!' + sys.executable + '\n' + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['WEATHER_TEST_ROOT'])
with (root / 'calls').open('a') as f: f.write(sys.argv[-1] + '\\n')
if (root / 'fail').exists(): sys.exit(6)
if 'geocoding-api' in sys.argv[-1]:
    print(json.dumps({'results': [{'name': 'Miagao', 'admin2': 'Iloilo', 'admin1': 'Western Visayas',
        'country': 'Philippines', 'latitude': 10.64, 'longitude': 122.23}]}))
else:
    print((root / 'forecast.json').read_text())
''')
        curl.chmod(0o755)
        (self.root / 'forecast.json').write_text(json.dumps(FORECAST))
        runtime = self.root / 'runtime'; runtime.mkdir(mode=0o700)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'),
                        XDG_STATE_HOME=str(self.root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                        WEATHER_TEST_ROOT=str(self.root), PATH=str(self.root / 'bin') + ':' + os.environ['PATH'],
                        QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')

    def cli(self, *args, success=True):
        result = subprocess.run([str(BINARY), *args], env=self.env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr + result.stdout)
        return [json.loads(line) for line in result.stdout.splitlines()]

    def test_city_search_selection_cache_and_offline(self):
        self.assertTrue(self.cli()[0]['needsLocation'])
        self.assertFalse(self.calls.exists())
        found = self.cli('search', 'Miagao', 'PH')[0]['results'][0]
        self.assertEqual(found, LOCATION)
        self.assertIn('countryCode=PH', self.calls.read_text())
        self.cli('select', json.dumps(found))
        fresh = self.cli()[0]
        self.assertFalse(fresh['stale'])
        self.assertIn('hourly=temperature_2m,precipitation_probability', self.calls.read_text())
        self.assertIn('forecast_days=2', self.calls.read_text())
        calls = self.calls.read_text()
        self.fail.touch()
        self.assertEqual(self.cli()[0], fresh)
        self.assertEqual(self.calls.read_text(), calls, 'Fresh cache must avoid all network access')
        cache = next((self.root / 'state/hyprshell/weather').glob('*.json'))
        data = json.loads(cache.read_text()); data['fetchedAt'] = int(time.time()) - 901
        cache.write_text(json.dumps(data))
        rows = self.cli()
        self.assertEqual(len(rows), 2, 'Emit cached data before an attempted stale refresh')
        self.assertTrue(rows[0]['stale'])
        self.assertEqual(rows[1]['weather'], FORECAST)
        self.assertIn('error', rows[1])
        self.fail.unlink()
        rows = self.cli()
        self.assertTrue(rows[0]['stale']); self.assertFalse(rows[1]['stale'])
        config = self.root / 'config/hyprshell/weather.json'
        before = config.read_bytes()
        self.cli('select', json.dumps(dict(found, latitude=999)), success=False)
        self.assertEqual(config.read_bytes(), before)
        self.cli('select', json.dumps(dict(found, latitude=10.7)))
        self.fail.touch()
        changed = self.cli()[0]
        self.assertNotIn('weather', changed, 'Never show another location’s cached weather')
        self.assertEqual(changed['location']['latitude'], 10.7)

    def test_legacy_cache_refreshes_to_include_hourly_data(self):
        self.cli('select', json.dumps(LOCATION))
        self.cli()
        cache = next((self.root / 'state/hyprshell/weather').glob('*.json'))
        data = json.loads(cache.read_text())
        del data['weather']['hourly']
        cache.write_text(json.dumps(data))
        rows = self.cli()
        self.assertEqual(len(rows), 2)
        self.assertTrue(rows[0]['stale'])
        self.assertEqual(rows[1]['weather']['hourly'], FORECAST['hourly'])
        self.assertFalse(rows[1]['stale'])

    @unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
    def test_native_picker_and_snapshot_lifecycle(self):
        (self.root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
        entry = self.root / 'Check.qml'
        entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: root
    FloatingWindow {
        id: window; visible: true; implicitWidth: 286; implicitHeight: 650
        WeatherCard { id: weather; anchors { left: parent.left; right: parent.right; top: parent.top } height: implicitHeight; active: true }
    }
    TestCase { id: test; name: "Weather"; when: false }
    Timer {
        interval: 200; running: true
        onTriggered: {
            try {
                test.tryVerify(() => weather.snapshot.needsLocation === true, 2000);
                let search = test.findChild(weather, 'weatherCitySearch');
                search.text = 'Miagao'; weather.search();
                test.tryVerify(() => weather.results.length > 0, 2000);
                if (weather.results[0].name.indexOf('Iloilo') < 0) throw new Error('Province missing');
                test.wait(100);
                test.mouseClick(test.findChild(weather, 'weatherResult-0'));
                test.tryVerify(() => weather.snapshot.weather !== undefined, 3000);
                if (weather.snapshot.weather.current.temperature_2m !== 29.5) throw new Error('Temperature missing');
                if (!test.findChild(weather, 'weatherTemperature').visible) throw new Error('Weather hidden');
                const hourly = test.findChild(weather, 'weatherHourlyForecast');
                if (!hourly.visible || weather.upcomingHours.length !== 3) throw new Error('Hourly forecast missing');
                if (weather.upcomingHours[0].time !== '2026-10-21T10:00' || weather.upcomingHours[0].rain !== 60)
                    throw new Error('Past hour included or rain missing');
                weather.active = false;
                let snapshot = weather.snapshot;
                test.wait(1100);
                if (weather.snapshot !== snapshot || weather.busy) throw new Error('Work while closed');
                weather.active = true;
                test.tryVerify(() => weather.snapshot !== snapshot, 2000);
                test.tryVerify(() => !weather.busy, 2000);
                snapshot = weather.snapshot;
                test.wait(1100);
                if (weather.snapshot !== snapshot || weather.busy) throw new Error('Polling while open');
                weather.grabToImage(result => result.saveToFile('/tmp/hyprweather-build/weather-preview.png'));
                test.wait(200);
                weather.active = false;
                snapshot = weather.snapshot;
                weather.snapshot = {weather:{current:{time:'2026-10-21T23:45'},hourly:{
                    time:['2026-10-21T23:00','2026-10-22T00:00','2026-10-22T01:00','2026-10-22T02:00'],
                    temperature_2m:[28,27,26,25],precipitation_probability:[40,30,20,10]}}};
                test.wait(50);
                if (weather.upcomingHours.length !== 3 || weather.upcomingHours[0].time !== '2026-10-22T00:00')
                    throw new Error('Hourly forecast fails across midnight');
                weather.snapshot = {weather:{current:{time:'2026-10-21T09:15'}}};
                test.wait(50);
                if (hourly.visible) throw new Error('Missing hourly data must hide forecast');
                weather.snapshot = snapshot;
                weather.manual = true; weather.editing = true;
                test.wait(50);
                if (hourly.visible) throw new Error('Hourly forecast crowds city editor');
                test.findChild(weather, 'weatherLatitude').text = '10.7';
                test.findChild(weather, 'weatherLongitude').text = '122.3';
                if (!test.findChild(weather, 'weatherSearchButton').enabled) throw new Error('Manual selection unavailable');
                test.findChild(weather, 'weatherLatitude').text = '';
                if (test.findChild(weather, 'weatherSearchButton').enabled) throw new Error('Empty coordinates accepted');
                console.log('WEATHER_NATIVE_OK'); Qt.quit();
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
        result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=self.env,
                                capture_output=True, text=True, timeout=20)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('WEATHER_NATIVE_OK', output)
        for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop'):
            self.assertNotIn(error, output)
        self.assertEqual(len(self.calls.read_text().splitlines()), 2, 'Search and one forecast only')
