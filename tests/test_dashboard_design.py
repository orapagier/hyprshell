"""Render real dashboard layouts and check reading order, bounds and actions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREVIEWS = Path('/tmp/hypr-dashboard-design')


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class DashboardDesignTests(unittest.TestCase):
    def test_responsive_layout_and_city_editor(self):
        PREVIEWS.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import "shell"
import "shell/style" as Style
ShellRoot {
    id: root
    property real previewWidth: 724
    property bool saved: false
    property real testHeight: 200
    property bool interpolated: false
    property bool reducedPhase: false
    property bool reducedInterpolated: false
    property var data: ({location:{name:"Butuan City, Province of Agusan del Norte, Caraga, Philippines"},
        fetchedAt:1792533600, stale:false, weather:{current:{temperature_2m:27, apparent_temperature:32,
            relative_humidity_2m:79, precipitation:0, interval:900, weather_code:3, wind_speed_10m:4,
            wind_gusts_10m:7, time:"2026-10-21T06:00"}, daily:{temperature_2m_max:[34],
            temperature_2m_min:[27],precipitation_probability_max:[22],sunrise:["2026-10-21T05:25"],
            sunset:["2026-10-21T17:19"]},hourly:{time:["2026-10-21T07:00","2026-10-21T08:00","2026-10-21T09:00"],
            temperature_2m:[28,30,31],precipitation_probability:[20,35,60]},timezone_abbreviation:"GMT+8"}})
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 800; implicitHeight: 1500
        color: "#171923"
        Rectangle {
            id: surface
            width: root.previewWidth + 36; height: dashboard.implicitHeight + 36
            color: "#171923"; radius: 28
            DashboardContent {
                id: dashboard; x: 18; y: 18
                width: root.previewWidth; height: implicitHeight
                services: ({sink:{audio:{volume:0.42,muted:false}},adapter:{enabled:true},connectedWifi:{signalStrength:0.78},wifiEnabled:true,statusData:{network:{tooltip:"Home Wi-Fi · 78%"}},batteryInfo:{present:true,percentage:38,pluggedIn:false}})
                resourceData: ({system:{hostname:"fedora",os:"Fedora Linux 44 (Forty Four)",
                    cpuModel:"12th Gen Intel(R) Core(TM) i5-1235U",kernel:"7.2.9-201.fc44.x86_64",
                    memoryTotal:16428249907,uptimeSeconds:132840,osAgeDays:8},usage:{cpuPercent:18,
                    memoryUsed:5798205850,memoryTotal:16428249907,storageFree:191126044672,storageTotal:511101108224}})
            }
        }
    }
    TestCase { id: test; name: "DashboardDesign"; when: false }
    MenuPopover {
        id: resizer
        parent: window.contentItem; opacity: 0; enabled: false; width: 800; height: 1000
        connected: false; opened: true; showHeader: false; animateContentHeight: true
        page: Component { Item { implicitHeight: root.testHeight } }
    }
    function capture(name) {
        test.wait(120);
        root.saved = false;
        surface.grabToImage(result => { root.saved = result.saveToFile("/tmp/hypr-dashboard-design/" + name + ".png"); });
        test.tryVerify(() => root.saved, 2000);
        if (!root.saved) throw new Error("Preview failed: " + name);
    }
    function checkBounds(item) {
        if (!item.visible || item.width === 0 || item.height === 0) return;
        if (item.objectName && item.objectName.startsWith('dashboard') || item.objectName === 'weatherLocation' || item.objectName === 'weatherTemperature' || item.objectName === 'weatherHourlyForecast' || item.objectName.startsWith('weatherHour-')) {
            let position = item.mapToItem(dashboard, 0, 0);
            if (position.x < -1 || position.y < -1 || position.x + item.width > dashboard.width + 1 || position.y + item.height > dashboard.height + 1)
                throw new Error('Overflow: ' + item.objectName + ' at ' + position + ' size ' + item.width + ',' + item.height);
        }
        for (let child of item.children || []) checkBounds(child);
    }
    Timer {
        interval: 200; running: true
        onTriggered: {
            try {
                const weather = test.findChild(dashboard, 'dashboardWeather');
                weather.snapshot = root.data;
                root.capture('wide'); root.checkBounds(dashboard);
                if (!test.findChild(dashboard, 'dashboardResourceUsage').visible) throw new Error('Resource card missing');
                if (test.findChild(dashboard, 'dashboardCpuUsage').value !== '18%') throw new Error('CPU usage missing');
                if (test.findChild(dashboard, 'dashboardRamUsage').value !== '5.4 / 15.3 GiB') throw new Error('RAM usage missing');
                if (test.findChild(dashboard, 'dashboardStorageUsage').value !== '178.0 GiB free') throw new Error('Free storage missing');
                if (dashboard.implicitHeight > 620) throw new Error('Wide dashboard is not compact');
                if (weather.x !== 0 || weather.width <= 350) throw new Error('Weather does not lead wide layout');
                if (test.findChild(dashboard, 'dashboardSettings') || test.findChild(dashboard, 'dashboardLock')) throw new Error('Removed buttons still take space');
                if (test.findChild(dashboard, 'dashboardWifiSignal').text !== '78%' || test.findChild(dashboard, 'dashboardBatteryLevel').text !== '38%') throw new Error('Connection percentages missing');
                const audio = test.findChild(dashboard, 'dashboardAudioLevel');
                const bluetooth = test.findChild(dashboard, 'dashboardBluetoothState');
                if (audio.text !== '42%' || bluetooth.text !== 'On') throw new Error('Audio or Bluetooth status missing');
                const statusOrder = ['dashboardBluetoothState','dashboardAudioLevel','dashboardWifiSignal','dashboardBatteryLevel'];
                for (let i = 1; i < statusOrder.length; i++)
                    if (test.findChild(dashboard, statusOrder[i-1]).mapToItem(dashboard,0,0).y >= test.findChild(dashboard, statusOrder[i]).mapToItem(dashboard,0,0).y)
                        throw new Error('Status rows must end with Battery at the bottom');
                const services = dashboard.services;
                for (let state of [{volume:0.42,muted:true,enabled:false,text:'42% · Muted'}, {volume:0,muted:false,enabled:true,text:'0%'}, {volume:1.25,muted:false,enabled:true,text:'125%'}]) {
                    dashboard.services = Object.assign({}, services, {sink:{audio:{volume:state.volume,muted:state.muted}},adapter:{enabled:state.enabled}});
                    test.wait(20);
                    if (audio.text !== state.text || bluetooth.text !== (state.enabled ? 'On' : 'Off')) throw new Error('Audio/Bluetooth status did not update');
                }
                dashboard.services = Object.assign({}, services, {sink:null,adapter:null});
                test.wait(20);
                if (audio.text !== 'Unavailable' || bluetooth.text !== 'Unavailable') throw new Error('Unavailable device state incorrect');
                dashboard.services = services;
                const metrics = test.findChild(weather, 'weatherMetrics');
                const hourly = test.findChild(weather, 'weatherHourlyForecast');
                const current = test.findChild(weather, 'weatherCurrentConditions');
                const device = test.findChild(dashboard, 'dashboardDeviceDetails');
                const connection = test.findChild(dashboard, 'dashboardConnectionStatus');
                if (Math.abs(current.mapToItem(dashboard,0,0).y - device.mapToItem(dashboard,0,0).y) > 1)
                    throw new Error('Top inner cards must align');
                if (Math.abs(hourly.mapToItem(dashboard,0,hourly.height).y - connection.mapToItem(dashboard,0,connection.height).y) > 1)
                    throw new Error('Bottom inner cards must align');
                if (Math.abs(hourly.y - metrics.y - metrics.height - 14) > 1) throw new Error('Forecast gap is not compact');
                const pencil = test.findChild(weather, 'weatherChangeCity');
                const location = test.findChild(weather, 'weatherLocation');
                const province = test.findChild(weather, 'weatherProvince');
                if (location.text !== 'Butuan City' || province.text !== 'Agusan del Norte' || !province.visible || province.font.pixelSize >= location.font.pixelSize)
                    throw new Error('City title and smaller province line missing');
                weather.snapshot = Object.assign({}, root.data, {location:{name:'Buenavista, Province of Agusan del Norte, Caraga, Philippines'}});
                root.capture('municipality'); root.checkBounds(dashboard);
                if (location.text !== 'Buenavista' || province.text !== 'Agusan del Norte') throw new Error('Municipality province missing');
                weather.snapshot = root.data;
                if (Math.abs(pencil.mapToItem(weather, 0, pencil.height / 2).y - location.mapToItem(weather, 0, location.height / 2).y) > 1) throw new Error('Pencil is not aligned with city');
                test.mouseClick(test.findChild(weather, 'weatherChangeCity'));
                if (!weather.editing || !test.findChild(weather, 'weatherCitySearch').activeFocus) throw new Error('City editor focus missing');
                if (test.findChild(weather, 'weatherTemperature').visible) throw new Error('Editor crowds forecast');
                root.capture('city-editor'); root.checkBounds(dashboard);
                test.mouseClick(pencil);
                if (weather.editing) throw new Error('City editor cancel broken');
                dashboard.services = {connectedWifi:null,wifiEnabled:true,statusData:{network:{tooltip:'Offline'}},batteryInfo:{present:false}};
                test.wait(50);
                if (test.findChild(dashboard, 'dashboardWifiSignal').text !== 'Disconnected' || test.findChild(dashboard, 'dashboardBatteryLevel').text !== 'No battery') throw new Error('Unavailable connection state incorrect');
                dashboard.services = {connectedWifi:null,wifiEnabled:false,statusData:{network:{tooltip:'Wi-Fi turned off'}},batteryInfo:{present:true,percentage:0,pluggedIn:false}};
                test.wait(50);
                if (test.findChild(dashboard, 'dashboardWifiSignal').text !== 'Off' || test.findChild(dashboard, 'dashboardBatteryLevel').text !== '0%') throw new Error('Wi-Fi off or empty battery state incorrect');
                dashboard.services = {connectedWifi:{signalStrength:0.78},wifiEnabled:true,statusData:{network:{tooltip:'Home Wi-Fi · 78%'}},batteryInfo:{present:true,percentage:38,pluggedIn:false}};
                root.previewWidth = 320;
                root.capture('narrow'); root.checkBounds(dashboard);
                const resources = dashboard.resourceData;
                dashboard.resourceData = {system:resources.system};
                root.capture('resources-unavailable'); root.checkBounds(dashboard);
                for (let name of ['dashboardCpuUsage','dashboardRamUsage','dashboardStorageUsage'])
                    if (test.findChild(dashboard, name).value !== '—' || test.findChild(dashboard, name).fraction !== -1)
                        throw new Error('Unavailable resources must not show invented usage');
                dashboard.resourceData = resources;
                const system = test.findChild(dashboard, 'dashboardSystemInfo');
                if (system.mapToItem(dashboard,0,0).y < weather.height) throw new Error('Narrow layout must stack');
                weather.snapshot = Object.assign({}, root.data, {stale:true,error:"Could not reach weather service. Check your connection."});
                root.capture('offline'); root.checkBounds(dashboard);
                if (test.findChild(weather, 'weatherStatus').visible || test.findChild(weather, 'weatherStatus').text.length)
                    throw new Error('Connection error must stay out of the cached-weather footer');
                weather.snapshot = {location:root.data.location,error:"Could not reach weather service. Check your connection."};
                root.capture('unavailable'); root.checkBounds(dashboard);
                weather.snapshot = {needsLocation:true};
                root.capture('choose-city'); root.checkBounds(dashboard);
                weather.manual = true;
                root.capture('coordinates'); root.checkBounds(dashboard);
                weather.manual = false; weather.snapshot = root.data;
                root.previewWidth = 724;
                for (let code of [0,2,61,95]) {
                    weather.snapshot = Object.assign({}, root.data, {weather:Object.assign({}, root.data.weather, {current:Object.assign({}, root.data.weather.current,{weather_code:code})})});
                    root.capture('condition-' + code); root.checkBounds(dashboard);
                }
                weather.snapshot = root.data;
                Style.Theme.preferences = ({highContrast:true,reducedMotion:true});
                root.capture('accessible'); root.checkBounds(dashboard);
                Style.Theme.preferences = ({});
                test.wait(50);
                resizer.requestedBodyHeightChanged.connect(() => {
                    const height = resizer.requestedBodyHeight;
                    if (!root.reducedPhase && height > 237 && height < 395) root.interpolated = true;
                    if (root.reducedPhase && height > 277 && height < 395) root.reducedInterpolated = true;
                });
                root.testHeight = 360;
                test.tryCompare(resizer, 'bodyHeight', 396, 1200);
                if (!root.interpolated) throw new Error('Content height must interpolate');
                if (Math.abs(resizer.bodyHeight - 396) > 1) throw new Error('Resize did not settle');
                Style.Theme.preferences = ({reducedMotion:true});
                test.wait(50);
                root.reducedPhase = true;
                root.testHeight = 240;
                test.tryCompare(resizer, 'bodyHeight', 276, 1200);
                if (root.reducedInterpolated || Math.abs(resizer.bodyHeight - 276) > 1) throw new Error('Reduced motion must resize without animation');
                console.log('DASHBOARD_DESIGN_OK'); Qt.quit();
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DASHBOARD_DESIGN_OK', output)
            for error in ('ReferenceError', 'Unable to assign', 'TypeError', 'Binding loop', 'Error loading'):
                self.assertNotIn(error, output)
