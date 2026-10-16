"""Control and observe production panels in the isolated live verifier fixture."""
import json


QML_CONTROL = '''
    property var control: ({})
    FileView {
        id: controlFile
        path: Quickshell.env('HYPRSHELL_TEST_CONTROL')
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { shell.control = JSON.parse(text()); performControl.restart(); }
    }
    Timer {
        id: performControl; interval: 200
        onTriggered: {
            if (!shell.control.id) return;
            for (let window of docks.instances.concat(taskbars.instances)) {
                if (shell.control.action === 'open' && window.component === shell.control.component)
                    window.toggleLauncher();
                else window.closeMenu();
            }
            reportControl.restart();
        }
    }
    Timer {
        id: reportControl; interval: 900
        onTriggered: {
            let states = {};
            for (let window of docks.instances.concat(taskbars.instances)) {
                let state = window.children.find(child => child.reserve !== undefined && child.revealed !== undefined);
                if (!state) throw new Error('Cannot find production DockVisibility');
                states[window.component] = {eligible:window.shown, shown:state.shown,
                    reserve:state.reserve, suppressed:state.suppressed,
                    fullscreen:window.fullscreen, overlapped:window.overlapped,
                    workspace:window.workspace, rect:window.dockRect,
                    mode:window.panel.hideMode, policy:window.panel.fullscreenPolicy};
            }
            console.log('PANEL_LIVE_STATE ' + JSON.stringify({id:shell.control.id, states:states}));
        }
    }
'''


def write_json(target, value):
    pending = target.with_suffix('.tmp')
    pending.write_text(json.dumps(value))
    pending.replace(target)


def read_report(log, token):
    log.seek(0)
    for line in log.read().splitlines():
        if 'PANEL_LIVE_STATE ' in line:
            report = json.loads(line.split('PANEL_LIVE_STATE ', 1)[1])
            if report['id'] == token:
                return report['states']
    return None


def check_state(state, *, shown, reserve, suppressed=False, eligible=True):
    expected = dict(shown=shown, reserve=reserve, suppressed=suppressed, eligible=eligible)
    for key, value in expected.items():
        assert state[key] == value, (key, value, state)


def run_behavior(config, target, control, log, process, output, hypr, monitors, wait_for):
    """Test all app-panel edges without launching or manipulating real windows."""
    token = 0

    def command(component, action='', windows=None):
        nonlocal token
        token += 1
        write_json(target, config)
        # The report includes the production state after its 500ms hide delay.
        write_json(control, dict(id=token, component=component, action=action, windows=windows or []))
        def report():
            if process.poll() is not None:
                log.seek(0)
                raise RuntimeError(log.read())
            return read_report(log, token)
        return wait_for(report, 'behavior report ' + str(token))

    for name in config['panels']:
        config['panels'][name]['enabled'] = False
    command('hyprdock')
    baseline = next(m for m in monitors() if m['name'] == output['name'])['reserved']
    count = 0
    for component in ('hyprdock', 'hyprbar'):
        panel = config['panels'][component]
        panel['enabled'] = True
        for edge in ('top', 'bottom', 'left', 'right'):
            panel.update(position=edge, hideMode='always', fullscreenPolicy='hide', workspaceOverrides={})
            state = command(component)[component]
            check_state(state, shown=True, reserve=True)
            workspace = state['workspace']
            assert isinstance(workspace, int) and workspace > 0, state

            def verify_reservation(reserved):
                expected = baseline.copy()
                if reserved:
                    expected[{'left':0, 'top':1, 'right':2, 'bottom':3}[edge]] += (
                        panel['thickness'] + panel['windowGap'] + panel['marginEdge'])
                return next(m for m in monitors() if m['name'] == output['name'])['reserved'] == expected

            wait_for(lambda: verify_reservation(True), component + ' always-visible reservation')
            rect = state['rect']
            monitor = next(m for m in monitors() if m['name'] == output['name'])
            client = dict(address='abc', title='Fixture', workspace=dict(id=workspace, name=str(workspace)),
                          monitor=dict(name=output['name']), lastIpcObject=dict(
                              **{'class':'panel-live-fixture'},
                              at=[monitor['x']+rect['x'], monitor['y']+rect['y']],
                              size=[rect['width'], rect['height']]))
            scenarios = [
                ('auto-hidden', 'auto-hide', '', [], False, False, False, True),
                ('auto-menu-held', 'auto-hide', 'open', [], True, False, False, True),
                ('auto-dismissed', 'auto-hide', '', [], False, False, False, True),
                ('dodge-clear', 'dodge', '', [], True, False, False, True),
                ('dodge-overlap', 'dodge', '', [client], False, False, False, True),
                ('dodge-menu-held', 'dodge', 'open', [client], True, False, False, True),
                ('dodge-dismissed', 'dodge', '', [client], False, False, False, True),
            ]
            fullscreen = json.loads(json.dumps(client))
            fullscreen['lastIpcObject']['fullscreen'] = 2
            scenarios += [
                ('fullscreen-hide', 'always', '', [fullscreen], False, False, True, True),
                ('fullscreen-show', 'always', '', [fullscreen], True, True, False, True),
                ('workspace-hidden', 'always', '', [], False, False, True, False),
                ('workspace-restored', 'always', '', [], True, True, False, True),
            ]
            for label, mode, action, windows, shown, reserve, suppressed, eligible in scenarios:
                panel['hideMode'] = mode
                panel['fullscreenPolicy'] = 'show' if label == 'fullscreen-show' else 'hide'
                panel['workspaceOverrides'] = {str(workspace):False} if label == 'workspace-hidden' else {}
                state = command(component, action, windows)[component]
                assert state['mode'] == mode, state
                check_state(state, shown=shown, reserve=reserve, suppressed=suppressed, eligible=eligible)
                if 'overlap' in label or label.startswith('dodge-') and windows:
                    assert state['overlapped'], state
                if label.startswith('fullscreen-'):
                    assert state['fullscreen'], state
                wait_for(lambda: verify_reservation(reserve), component + ' reservation ' + label)
                raw = json.loads(hypr('-j', 'layers'))[output['name']]['levels']
                reveal = [row for level in raw.values() for row in level
                          if row.get('pid') == process.pid and row['namespace'] ==
                          ('hyprshell-dock-reveal' if component == 'hyprdock' else 'hyprshell-taskbar-reveal')]
                assert len(reveal) == int(eligible and not suppressed and mode != 'always'), (label, reveal)
                if reveal:
                    row = reveal[0]
                    assert (row['h'] if edge in ('top', 'bottom') else row['w']) == 3, row
                count += 1
            print(f'PASS behavior {component} {edge}: always + 11 transitions', flush=True)
        panel['enabled'] = False
        command(component)
    print(f'PASS {count} visibility/menu/reservation transitions plus 8 always-visible baselines', flush=True)
