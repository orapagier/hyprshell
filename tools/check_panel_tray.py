#!/usr/bin/env python3
"""Live tray routing diagnostic using a harmless private SNI provider.

A programmatic popup request does not establish visible menus or native input."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from check_panel_live import PAYLOAD, fixture_source, hypr, monitors, wait_for
from panel_live_behavior import write_json


def serve():
    from gi.repository import Gio, GLib
    item_xml = '''<node><interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/><property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/><property name="Status" type="s" access="read"/>
    <property name="IconName" type="s" access="read"/><property name="IconThemePath" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/><property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/><property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <method name="Activate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="SecondaryActivate"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    <method name="ContextMenu"><arg type="i" direction="in"/><arg type="i" direction="in"/></method>
    </interface></node>'''
    menu_xml = '''<node><interface name="com.canonical.dbusmenu">
    <property name="Version" type="u" access="read"/><property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/><property name="IconThemePath" type="as" access="read"/>
    <method name="GetLayout"><arg type="i" direction="in"/><arg type="i" direction="in"/><arg type="as" direction="in"/>
    <arg type="u" direction="out"/><arg type="(ia{sv}av)" direction="out"/></method>
    <method name="GetGroupProperties"><arg type="ai" direction="in"/><arg type="as" direction="in"/><arg type="a(ia{sv})" direction="out"/></method>
    <method name="GetProperty"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="out"/></method>
    <method name="AboutToShow"><arg type="i" direction="in"/><arg type="b" direction="out"/></method>
    <method name="Event"><arg type="i" direction="in"/><arg type="s" direction="in"/><arg type="v" direction="in"/><arg type="u" direction="in"/></method>
    </interface></node>'''
    properties = {'label':GLib.Variant('s','Panel acceptance menu'), 'enabled':GLib.Variant('b',True),
                  'visible':GLib.Variant('b',True)}
    def method(connection, sender, path, interface, name, params, invocation):
        print('TRAY_METHOD '+name, flush=True)
        if name == 'GetLayout':
            leaf = GLib.Variant('(ia{sv}av)', (1,properties,[]))
            value = GLib.Variant('(u(ia{sv}av))',(1,(0,{'children-display':GLib.Variant('s','submenu')},[leaf])))
        elif name == 'GetGroupProperties':
            value = GLib.Variant('(a(ia{sv}))', ([(1,properties)],))
        elif name == 'GetProperty':
            value = GLib.Variant('(v)',(properties.get(params.unpack()[1], GLib.Variant('s','')),))
        elif name == 'AboutToShow':
            value = GLib.Variant('(b)',(False,))
        else:
            value = GLib.Variant('()',())
        invocation.return_value(value)
    def prop(connection, sender, path, interface, name):
        values = {'Category':('s','ApplicationStatus'), 'Id':('s','hyprshell-panel-acceptance'),
                  'Title':('s','Panel acceptance'), 'Status':('s','Active'),
                  'IconName':('s','preferences-system'), 'IconThemePath':('as',[]) if interface=='com.canonical.dbusmenu' else ('s',''),
                  'IconPixmap':('a(iiay)',[]), 'ItemIsMenu':('b',True), 'Menu':('o','/Menu'),
                  'ToolTip':('(sa(iiay)ss)',('preferences-system',[],'Panel acceptance','')),
                  'Version':('u',3), 'TextDirection':('s','ltr')}
        if interface == 'com.canonical.dbusmenu' and name == 'Status':
            return GLib.Variant('s','normal')
        return GLib.Variant(*values[name])
    bus_name = 'org.kde.StatusNotifierItem-'+str(os.getpid())+'-1'
    def acquired(connection, name):
        connection.register_object('/StatusNotifierItem', Gio.DBusNodeInfo.new_for_xml(item_xml).interfaces[0], method, prop, None)
        connection.register_object('/Menu', Gio.DBusNodeInfo.new_for_xml(menu_xml).interfaces[0], method, prop, None)
        connection.call_sync('org.kde.StatusNotifierWatcher','/StatusNotifierWatcher','org.kde.StatusNotifierWatcher',
                             'RegisterStatusNotifierItem',GLib.Variant('(s)',(bus_name,)),None,Gio.DBusCallFlags.NONE,3000,None)
        print('TRAY_READY',flush=True)
    Gio.bus_own_name(Gio.BusType.SESSION,bus_name,Gio.BusNameOwnerFlags.NONE,None,acquired,None)
    GLib.MainLoop().run()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serve', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--screenshots', type=Path)
    args = parser.parse_args()
    if args.serve:
        serve(); return
    if not args.run or not __debug__:
        parser.error('--run and Python assertions are required')
    before = {m['name'] for m in monitors()}
    output = None
    shell = provider = None
    try:
        hypr('output','create','headless')
        added = wait_for(lambda:[m for m in monitors() if m['name'] not in before], 'tray output')
        if len(added) != 1: raise RuntimeError('Cannot identify tray output')
        output = added[0]
        with tempfile.TemporaryDirectory(prefix='hyprshell-tray-') as directory:
            root = Path(directory)
            config = json.loads((PAYLOAD/'settings/defaults.json').read_text())
            config['bar']['position'] = 'bottom'
            for name,panel in config['panels'].items():panel.update(enabled=name=='hyprpane',monitors=[output['name']])
            target=root/'config/hyprshell/settings.json';target.parent.mkdir(parents=True);write_json(target,config)
            control=root/'control.json';write_json(control,{})
            source=fixture_source().replace('import Quickshell.Io','import Quickshell.Services.SystemTray\nimport Quickshell.Io')
            source=source.replace('property var items: []', "property var items: SystemTray.items.values.filter(i => i.id === 'hyprshell-panel-acceptance')")
            source=source.replace('    id: shell\n', '''    id: shell
    Timer { interval:1200; running:true; repeat:true; onTriggered: {
        if (tray.items.length !== 1 || !tray.items[0].hasMenu) return;
        let panel=panels.instances[0];
        let bar=panel.contentItem.children.find(c=>c.trayAction !== undefined);
        if (!bar) return;
        bar.trayAction(tray.items[0],bar,Qt.RightButton);
        console.log('TRAY_OPENED'); stop();
    }}
''')
            fixture=root/'Tray.qml';fixture.write_text(source)
            env=dict(os.environ,XDG_CONFIG_HOME=str(root/'config'),XDG_STATE_HOME=str(root/'state'),
                     QT_QPA_PLATFORM='wayland',QT_QPA_PLATFORMTHEME='',HYPRSHELL_TEST_OUTPUT=output['name'],HYPRSHELL_TEST_CONTROL=str(control))
            with (root/'shell.log').open('w+') as log, (root/'provider.log').open('w+') as provider_log:
                shell=subprocess.Popen(['quickshell','--log-rules','qml.debug=true','-p',str(fixture)],env=env,stdout=log,stderr=subprocess.STDOUT)
                provider=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'--serve'],stdout=provider_log,stderr=subprocess.STDOUT)
                def opened():
                    log.seek(0);return 'TRAY_OPENED' in log.read()
                try:wait_for(opened,'native tray menu')
                except RuntimeError:
                    log.seek(0);provider_log.seek(0);print(log.read(),provider_log.read());raise
                provider_log.seek(0);text=provider_log.read();assert 'TRAY_METHOD GetLayout' in text,text
                time.sleep(1)
                if args.screenshots:
                    args.screenshots.mkdir(parents=True,exist_ok=True)
                    subprocess.run(['grim','-o',output['name'],str(args.screenshots/'tray-native-open.png')],check=True,timeout=5)
                print('PASS production Hyprpane tray routing and D-Bus layout retrieval; visible popup/input remain unverified',flush=True)
    finally:
        for process in (shell,provider):
            if process and process.poll() is None:
                process.terminate()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
        if output:hypr('output','remove',output['name'])


if __name__=='__main__':main()
