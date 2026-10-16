#!/usr/bin/env python3
"""Opt-in real-window acceptance on a virtual output or isolated existing-output workspace."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

from check_panel_live import PAYLOAD, fixture_source, hypr, monitors, wait_for
from panel_live_behavior import write_json, read_report

spec = importlib.util.spec_from_file_location('show_desktop', PAYLOAD/'settings/show_desktop.py')
desktop_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(desktop_module)


WINDOWS = '''
    Window {
        title:'Hyprshell acceptance A'; visible:true; width:360; height:240
        flags:Qt.Window | Qt.WindowDoesNotAcceptFocus
        color:'#20334a'
        Text { anchors.centerIn:parent; text:'Panel acceptance A'; color:'white' }
    }
    Window {
        title:'Hyprshell acceptance B'; visible:true; width:320; height:200
        flags:Qt.Window | Qt.WindowDoesNotAcceptFocus
        color:'#334a20'
        Text { anchors.centerIn:parent; text:'Panel acceptance B'; color:'white' }
    }
'''


def switch_workspace(output, number):
    # Change only the test monitor's workspace in one event,
    # then return focus without cursor warps to the user's output.
    code = ('local previous=hl.get_active_monitor().name; '
            'local warp=hl.get_config("cursor.no_warps"); '
            'hl.config({cursor={no_warps=true}}); '
            'local ok,err=pcall(function() '
            'hl.dispatch(hl.dsp.focus({monitor='+json.dumps(output['name'])+'})); '
            'hl.dispatch(hl.dsp.focus({workspace='+str(number)+'})); end); '
            'hl.dispatch(hl.dsp.focus({monitor=previous})); '
            'hl.config({cursor={no_warps=warp}}); if not ok then error(err) end')
    hypr('eval', code)
    wait_for(lambda:next(m for m in monitors() if m['name']==output['name'])['activeWorkspace']['id']==number,
             'actual workspace switch')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--output', help='test an existing output on a temporary workspace; never remove it')
    parser.add_argument('--wtype', help='optional wtype binary for real Escape-key delivery')
    parser.add_argument('--screenshots', type=Path, help='save test-output input review images here')
    args = parser.parse_args()
    if not args.run or not __debug__:
        parser.error('--run and Python assertions are required')
    before = monitors()
    output = None
    process = None
    controller = None
    original_workspace = None
    cursor = json.loads(hypr('-j', 'cursorpos'))
    original_monitor = next(m['name'] for m in before if m['focused'])
    temporary = tempfile.TemporaryDirectory(prefix='hyprshell-session-')
    try:
        if args.output:
            output = next((m for m in before if m['name'] == args.output), None)
            if output is None:
                raise RuntimeError('Requested output is unavailable')
            if output.get('specialWorkspace', {}).get('id', 0):
                raise RuntimeError('Close the output special workspace before testing')
            original_workspace = output['activeWorkspace']['id']
            used = {w['id'] for w in json.loads(hypr('-j', 'workspaces'))}
            isolated = next(n for n in range(99, 0, -1) if n not in used)
            switch_workspace(output, isolated)
            output = next(m for m in monitors() if m['name'] == args.output)
        else:
            hypr('output', 'create', 'headless')
            added = wait_for(lambda:[m for m in monitors() if m['name'] not in {b['name'] for b in before}], 'virtual output')
            if len(added) != 1:
                raise RuntimeError('Cannot uniquely identify the temporary output')
            output = added[0]
        root = Path(temporary.name)
        config = json.loads((PAYLOAD/'settings/defaults.json').read_text())
        for name, panel in config['panels'].items():
            panel.update(enabled=name == 'hyprdock', monitors=[output['name']])
        config['panels']['hyprdock'].update(position='bottom', animations=False)
        target = root/'config/hyprshell/settings.json'
        target.parent.mkdir(parents=True)
        write_json(target, config)
        control = root/'control.json'
        write_json(control, {})
        fixture = root/'Session.qml'
        source = fixture_source().replace('    id: shell\n', '    id: shell\n'+WINDOWS)
        # Actual toplevel integration; no synthetic window rows in this run.
        source = source.replace('windows: shell.control.windows || []; ', '')
        fixture.write_text(source)
        env = dict(os.environ, XDG_CONFIG_HOME=str(root/'config'), XDG_STATE_HOME=str(root/'state'),
                   QT_QPA_PLATFORM='wayland', QT_QPA_PLATFORMTHEME='',
                   HYPRSHELL_TEST_OUTPUT=output['name'], HYPRSHELL_TEST_CONTROL=str(control))
        with (root/'quickshell.log').open('w+') as log:
            process = subprocess.Popen(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                       env=env, stdout=log, stderr=subprocess.STDOUT)
            compositor = desktop_module.Hyprland()
            controller = desktop_module.Desktop(root/'desktop.json')
            def clients():
                return [c for c in compositor.query('clients') if c['pid'] == process.pid]
            def ensure_owned():
                if any(c['pid'] != process.pid and c.get('mapped') and c['monitor'] == output['id'] and (c['workspace']['id'] == workspace or c.get('pinned'))
                       for c in compositor.query('clients')):
                    raise RuntimeError('Another app appeared on the test output; stopping window actions.')
            windows = wait_for(lambda: clients() if len(clients()) == 2 else None, 'two disposable windows')
            workspace = output['activeWorkspace']['id']
            for client in windows:
                compositor.dispatch('window.move', window='address:'+client['address'], workspace=workspace, follow=False)
            wait_for(lambda:all(c['monitor'] == output['id'] for c in clients()), 'window output routing')
            a, b = [c['address'] for c in clients()]
            compositor.dispatch('window.float', window='address:'+a, action='set')
            compositor.dispatch('window.resize', window='address:'+a, x=360, y=240, relative=False)
            compositor.dispatch('window.move', window='address:'+a, x=output['x']+60, y=output['y']+70, relative=False)
            compositor.dispatch('window.pin', window='address:'+a, action='set')
            compositor.dispatch('window.fullscreen', window='address:'+b, mode='fullscreen', action='set')
            wait_for(lambda: any(c['fullscreen'] == 2 for c in clients()), 'real fullscreen')

            token = 0
            def observe(action=''):
                nonlocal token
                token += 1
                write_json(control, dict(id=token, component='hyprdock', action=action))
                try:
                    return wait_for(lambda:read_report(log, token), 'panel state')['hyprdock']
                except RuntimeError:
                    log.seek(0)
                    print(log.read()[-6000:])
                    raise
            state = observe()
            assert state['fullscreen'] and state['suppressed'] and not state['reserve'], state
            print('PASS actual fullscreen Hide policy', flush=True)
            config['panels']['hyprdock']['fullscreenPolicy'] = 'show'
            write_json(target, config)
            state = observe()
            assert state['fullscreen'] and state['shown'] and state['reserve'], state
            print('PASS actual fullscreen Show policy', flush=True)

            used = {w['id'] for w in compositor.query('workspaces')}
            alternate = next(n for n in range(99, 0, -1) if n not in used)
            config['panels']['hyprdock'].update(workspaceScope='selected', workspaceList=[workspace])
            write_json(target, config)
            switch_workspace(output, alternate)
            state = observe()
            assert not state['eligible'] and not state['reserve'] and not state['fullscreen'], state
            switch_workspace(output, workspace)
            state = observe()
            assert state['eligible'] and state['fullscreen'] and state['reserve'], state
            print('PASS actual workspace transitions and panel visibility restoration', flush=True)

            for component in ('hyprdock', 'hyprbar'):
                for name, panel in config['panels'].items():
                    panel['enabled'] = name == component
                for edge in ('top', 'bottom', 'left', 'right'):
                    panel = config['panels'][component]
                    panel.update(position=edge, hideMode='auto-hide', fullscreenPolicy='show')
                    write_json(target, config)
                    compositor.dispatch('cursor.move', x=output['x']+400, y=output['y']+250)
                    token += 1
                    write_json(control, dict(id=token, component=component))
                    state = wait_for(lambda:read_report(log, token), 'hidden input state')[component]
                    assert not state['shown'], state
                    rect = state['rect']
                    width = output['width']/output['scale']
                    height = output['height']/output['scale']
                    x = 1 if edge == 'left' else width-1 if edge == 'right' else rect['x']+rect['width']/2
                    y = 1 if edge == 'top' else height-1 if edge == 'bottom' else rect['y']+rect['height']/2
                    compositor.dispatch('cursor.move', x=output['x']+x, y=output['y']+y)
                    token += 1
                    write_json(control, dict(id=token, component=component, action='inspect'))
                    state = wait_for(lambda:read_report(log, token), 'reveal hover')[component]
                    if not state['shown']:
                        print('Reveal diagnostics:', json.dumps(dict(cursor=compositor.query('cursorpos'),
                              layers=[row for level in compositor.query('layers')[output['name']]['levels'].values()
                                      for row in level if row.get('pid') == process.pid])), flush=True)
                    assert state['shown'] and not state['reserve'], state
                    if args.screenshots:
                        args.screenshots.mkdir(parents=True, exist_ok=True)
                        subprocess.run(['grim', '-o', output['name'], str(args.screenshots/(component+'-'+edge+'.png'))],
                                       check=True, timeout=5)
                    compositor.dispatch('cursor.move', x=output['x']+400, y=output['y']+250)
                    token += 1
                    write_json(control, dict(id=token, component=component, action='open'))
                    state = wait_for(lambda:read_report(log, token), 'launcher keyboard state')[component]
                    assert state['menuOpen'] and state['shown'], state
                    if args.wtype:
                        # Escape only, while this fixture owns an exclusive
                        # launcher menu; never type text or launch an app.
                        assert state['menuExclusive'], 'Fixture launcher did not request exclusive keyboard focus'
                        subprocess.run([args.wtype, '-k', 'Escape'], check=True, timeout=5)
                        token += 1
                        write_json(control, dict(id=token, component=component, action='inspect'))
                        state = wait_for(lambda:read_report(log, token), 'Escape dismissal')[component]
                        assert not state['menuOpen'] and not state['shown'], state
                    label = 'reveal/menu input' if args.wtype else 'reveal/menu opening (Escape unverified)'
                    print(f'PASS native {label} {component} {edge}', flush=True)
            compositor.dispatch('cursor.move', x=cursor['x'], y=cursor['y'])
            compositor.dispatch('focus', monitor=original_monitor)

            config['panels']['hyprdock'].update(enabled=True, hideMode='always', showDesktop=True)
            config['panels']['hyprbar']['enabled'] = False
            write_json(target, config)
            ensure_owned()
            state = observe('desktop')
            assert state['desktopHidden'] and not state['desktopBusy'] and not state['desktopError'], state
            assert all(c['workspace']['name'] == desktop_module.PARK for c in clients()), clients()
            state = observe('desktop')
            assert not state['desktopHidden'] and not state['desktopError'], state
            assert all(c['workspace']['name'] != desktop_module.PARK for c in clients()), clients()
            print('PASS production Show Desktop button and shared controller round trip', flush=True)

            ensure_owned()
            controller.action('toggle', output['name'])
            assert all(c['workspace']['name'] == desktop_module.PARK for c in clients()), clients()
            assert not any(c['pinned'] for c in clients()), clients()
            # A new controller instance simulates shell/helper restart.
            desktop_module.Desktop(root/'desktop.json').action('restore')
            restored = clients()
            assert all(c['workspace']['id'] == workspace for c in restored if not c['pinned']), restored
            assert next(c for c in restored if c['address'] == a)['pinned'], restored
            assert next(c for c in restored if c['address'] == a)['monitor'] == output['id'], restored
            assert next(c for c in restored if c['address'] == b)['fullscreen'] == 2, restored
            print('PASS Show Desktop actual pinned/fullscreen windows and restart recovery', flush=True)

            # Closing a hidden disposable window must not prevent recovery.
            ensure_owned()
            controller.action('toggle', output['name'])
            compositor.dispatch('window.close', window='address:'+b)
            wait_for(lambda:len(clients()) == 1, 'hidden-window closure')
            controller.action('restore')
            assert clients()[0]['monitor'] == output['id'] and clients()[0]['pinned'], clients()
            print('PASS recovery after a hidden window closes', flush=True)

            if not args.output:
                # Verify recovery when the source output disappears.
                ensure_owned()
                controller.action('toggle', output['name'])
                hypr('output', 'remove', output['name'])
                wait_for(lambda:output['name'] not in {m['name'] for m in monitors()}, 'output unplug')
                output = None
                controller.action('restore')
                assert clients()[0]['workspace']['name'] != desktop_module.PARK and clients()[0]['pinned'], clients()
                print('PASS recovery after virtual output removal', flush=True)
            process.terminate()
            process.wait(timeout=5)
            log.seek(0)
            contents = log.read()
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                assert error not in contents, contents
    finally:
        # Never leave disposable windows parked when a check fails.
        try:
            if controller:
                controller.action('restore')
        finally:
            if process and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            if output:
                if args.output and original_workspace is not None:
                    switch_workspace(output, original_workspace)
                elif not args.output:
                    hypr('output', 'remove', output['name'])
            hypr('dispatch', 'hl.dsp.cursor.move({x='+str(cursor['x'])+',y='+str(cursor['y'])+'})')
            hypr('dispatch', 'hl.dsp.focus({monitor='+json.dumps(original_monitor)+'})')
            temporary.cleanup()
    suffix = 'original output/workspace restored' if args.output else 'temporary output removed'
    print('Real-window checks passed; temporary windows removed; '+suffix+'.')


if __name__ == '__main__':
    main()
