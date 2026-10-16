#!/usr/bin/env python3
"""Recoverable Show Desktop, scoped to one output's active ordinary workspace."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import re
import subprocess
import tempfile

PARK = 'special:hyprshell-desktop'


class Hyprland:
    def query(self, name):
        return json.loads(subprocess.check_output(['hyprctl', '-j', name], text=True, timeout=5))

    def dispatch(self, name, **fields):
        def literal(value):
            if isinstance(value, bool):
                return 'true' if value else 'false'
            return json.dumps(value, ensure_ascii=False)
        code = 'hl.dsp.' + name + '({' + ','.join(k+'='+literal(v) for k,v in fields.items()) + '})'
        output = subprocess.check_output(['hyprctl', 'dispatch', code], text=True, timeout=5)
        if output.strip() != 'ok':
            raise RuntimeError('The compositor could not complete the window action.')


class Desktop:
    def __init__(self, path, compositor=None, instance=None):
        self.path = Path(path)
        self.hypr = compositor or Hyprland()
        self.instance = instance if instance is not None else os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')

    def load(self):
        try:
            data = json.loads(self.path.read_text())
        except FileNotFoundError:
            return dict(version=1, instance=self.instance, windows=[])
        if not isinstance(data, dict) or data.get('version') != 1 or not isinstance(data.get('windows'), list):
            raise ValueError('The desktop recovery journal is invalid; keep it for recovery.')
        if data.get('instance') != self.instance:
            return dict(version=1, instance=self.instance, windows=[])
        for record in data['windows']:
            if (not isinstance(record, dict) or not re.fullmatch(r'0x[0-9a-fA-F]+', str(record.get('address', '')))
                    or type(record.get('pid')) is not int or type(record.get('workspace')) is not int
                    or record['workspace'] <= 0 or not isinstance(record.get('output'), str)
                    or type(record.get('pinned')) is not bool
                    or record.get('fullscreen') not in (0, 1, 2, 3)
                    or record.get('fullscreenClient') not in (0, 1, 2, 3)):
                raise ValueError('The desktop recovery journal is invalid; keep it for recovery.')
            geometry = record.get('geometry')
            if geometry is not None and (not isinstance(geometry, dict) or any(
                    not isinstance(geometry.get(key), list) or len(geometry[key]) != 2 or any(
                        type(v) not in (int, float) or not math.isfinite(v) for v in geometry[key])
                    for key in ('size', 'offset')) or any(v <= 0 for v in geometry['size'])):
                raise ValueError('The desktop recovery geometry is invalid; keep it for recovery.')
        return data

    def save(self, data):
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, name = tempfile.mkstemp(dir=self.path.parent, prefix='.show-desktop-')
        try:
            with os.fdopen(fd, 'w') as stream:
                json.dump(data, stream)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.path)
            directory = os.open(self.path.parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    def clients(self):
        return {c['address']:c for c in self.hypr.query('clients')}

    def current(self, record):
        client = self.clients().get(record['address'])
        return client if client and client.get('pid') == record['pid'] else None

    def restore(self, data):
        failures = []
        for record in data['windows']:
            if record.get('restored'):
                continue
            try:
                client = self.current(record)
                if client:
                    selector = 'address:' + record['address']
                    parked = client['workspace']['name'] == PARK
                    if parked:
                        monitors = self.hypr.query('monitors')
                        if not monitors:
                            raise RuntimeError('Connect a display before restoring desktop windows.')
                        workspaces = self.hypr.query('workspaces')
                        target = record['workspace']
                        origin_monitor = next((m for m in monitors if m['name'] == record['output']), None)
                        if record['pinned']:
                            target = (origin_monitor or next((m for m in monitors if m.get('focused')), monitors[0]))['activeWorkspace']['id']
                        elif not origin_monitor and not any(
                                w['id'] == target for w in workspaces):
                            target = next((m for m in monitors if m.get('focused')), monitors[0])['activeWorkspace']['id']
                        record['restoreTarget'] = target
                        self.save(data)
                        self.hypr.dispatch('window.move', window=selector, workspace=target, follow=False)
                        client = self.current(record)
                        if client and client['workspace']['name'] == PARK:
                            raise RuntimeError('A desktop window is still hidden; use Restore again.')
                    # A crash can occur after unpinning but before moving. Restore
                    # that flag too; manually recovered windows keep their new workspace.
                    if client and record['pinned'] and not client.get('pinned'):
                        self.hypr.dispatch('window.pin', window=selector, action='set')
                    if client and not client.get('fullscreen') and record.get('floating') and record.get('geometry') and (parked or record.get('restoreTarget')):
                        monitors = self.hypr.query('monitors')
                        if not monitors:
                            raise RuntimeError('Connect a display before restoring desktop geometry.')
                        destination = next((m for m in monitors if m['name'] == record['output']), None) or next(
                            (m for m in monitors if m.get('focused')), monitors[0])
                        geometry = record['geometry']
                        width = destination['width']/destination['scale']
                        height = destination['height']/destination['scale']
                        size = [min(geometry['size'][0], width), min(geometry['size'][1], height)]
                        self.hypr.dispatch('window.resize', window=selector, x=size[0], y=size[1], relative=False)
                        self.hypr.dispatch('window.move', window=selector,
                            x=destination['x']+max(0, min(geometry['offset'][0], width-size[0])),
                            y=destination['y']+max(0, min(geometry['offset'][1], height-size[1])), relative=False)
                    if client and (parked or client['workspace']['id'] == record.get('restoreTarget')) and record['fullscreen']:
                        self.hypr.dispatch('window.fullscreen_state', window=selector,
                                           internal=record['fullscreen'], client=record['fullscreenClient'], action='set')
                record['restored'] = True
                self.save(data)
            except (RuntimeError, OSError, subprocess.SubprocessError, ValueError) as error:
                failures.append(str(error))
        if failures:
            raise RuntimeError('Some desktop windows still need restoration. Use Restore again.')
        data['windows'] = []
        self.save(data)

    def hide(self, data, output):
        monitors = self.hypr.query('monitors')
        monitor = next((m for m in monitors if m['name'] == output), None) if output else next(
            (m for m in monitors if m.get('focused')), None)
        if not monitor:
            raise ValueError('Choose an available output for Show Desktop.')
        if monitor.get('specialWorkspace', {}).get('id', 0):
            raise ValueError('Close the special workspace before showing this desktop.')
        workspace = monitor['activeWorkspace']['id']
        if workspace <= 0:
            raise ValueError('Show Desktop requires an ordinary numbered workspace.')
        clients = self.clients().values()
        selected = [c for c in clients if c.get('mapped', True) and c.get('monitor') == monitor['id']
                    and c['workspace']['id'] > 0 and (c['workspace']['id'] == workspace or c.get('pinned'))]
        # Never mix untracked parked windows into a new journal.
        if any(c['workspace']['name'] == PARK for c in clients):
            raise RuntimeError('Untracked desktop windows exist. Open special:hyprshell-desktop to recover them.')
        for c in selected:
            if not re.fullmatch(r'0x[0-9a-fA-F]+', c['address']):
                raise ValueError('The compositor returned an invalid window identity.')
        data['windows'] = [dict(address=c['address'], pid=c['pid'], workspace=workspace if c.get('pinned') else c['workspace']['id'],
                                output=monitor['name'], pinned=bool(c.get('pinned')),
                                fullscreen=c.get('fullscreen', 0), fullscreenClient=c.get('fullscreenClient', 0),
                                floating=bool(c.get('floating')), geometry=dict(
                                    offset=[c.get('at', [0,0])[0]-monitor.get('x', 0), c.get('at', [0,0])[1]-monitor.get('y', 0)],
                                    size=c.get('size', [360,240])))
                           for c in selected]
        # Write every origin before the first compositor mutation.
        self.save(data)
        try:
            for record in data['windows']:
                client = self.current(record)
                if not client:
                    continue
                selector = 'address:' + record['address']
                if record['pinned']:
                    self.hypr.dispatch('window.pin', window=selector, action='unset')
                self.hypr.dispatch('window.move', window=selector, workspace=PARK, follow=False)
                client = self.current(record)
                if client and client['workspace']['name'] != PARK:
                    raise RuntimeError('A desktop window could not be hidden.')
        except (RuntimeError, OSError, subprocess.SubprocessError, ValueError):
            self.restore(data)
            raise RuntimeError('Show Desktop failed; the original windows were restored.')

    def action(self, name, output=''):
        if not self.instance:
            raise ValueError('Show Desktop needs a live Hyprland session.')
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with open(self.path.with_suffix('.lock'), 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            data = self.load()
            if name == 'restore' or name == 'toggle' and data['windows']:
                self.restore(data)
            elif name == 'toggle':
                self.hide(data, output)
            elif name != 'status':
                raise ValueError('Unknown desktop action.')
            return dict(ok=True, hidden=bool(data['windows']), count=len(data['windows']))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'toggle', 'restore'))
    parser.add_argument('--output', default='')
    args = parser.parse_args()
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home()/'.local/state')))/'hyprshell/show-desktop.json'
    try:
        result = Desktop(state).action(args.action, args.output)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        result = dict(ok=False, message=str(error))
    print(json.dumps(result))


if __name__ == '__main__':
    main()
