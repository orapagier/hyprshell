#!/usr/bin/env python3
"""Manual printer/scanner access; no service or device polling."""
import argparse
import json
import shutil
import subprocess

from optional_tools import install


def status():
    tools = {name: bool(shutil.which(name)) for name in ('system-config-printer', 'simple-scan', 'lpstat', 'scanimage')}
    return {'ok': True, 'tools': tools}


def open_tool(tool):
    if not shutil.which(tool): raise ValueError('Install printing and scanning tools first, then Refresh.')
    subprocess.Popen([tool], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return {'ok': True, 'message': 'Opening ' + ('printer settings.' if tool == 'system-config-printer' else 'Document Scanner.')}


def request(payload):
    operation = payload.get('operation')
    if operation == 'status': return status()
    if operation == 'install': return install('printing')
    if operation == 'printers': return open_tool('system-config-printer')
    if operation == 'scanner': return open_tool('simple-scan')
    if operation == 'enable-printing':
        if payload.get('confirmed') is not True: raise ValueError('Confirm enabling printing first.')
        if not shutil.which('kitty'): raise ValueError('Kitty is required for administrator authentication.')
        result = subprocess.run(['kitty', '--detach', '--hold', '--title', 'Enable printing on demand', 'sudo', 'systemctl', 'enable', '--now', 'cups.socket'], capture_output=True, text=True, timeout=15)
        if result.returncode: raise ValueError('Could not open the printing setup terminal. Retry from the desktop session.')
        return {'ok': True, 'message': 'Complete authentication in the terminal to enable the CUPS socket. Printing will start on request.'}
    if operation == 'check-printers':
        if not shutil.which('lpstat'): raise ValueError('Install the printer tools first.')
        result = subprocess.run(['lpstat', '-p', '-d'], capture_output=True, text=True, timeout=10)
        if result.returncode: raise ValueError('No available printer queue was reported. Open printer settings to configure a printer; enable printing if CUPS is unavailable.')
        return {'ok': True, 'details': result.stdout[:12000] or 'No printers configured.'}
    if operation == 'check-scanners':
        if not shutil.which('scanimage'): raise ValueError('Install the scanner tools first.')
        result = subprocess.run(['scanimage', '-L'], capture_output=True, text=True, timeout=25)
        if result.returncode: raise ValueError('Scanner discovery failed. Check connections, permissions, and device drivers in Document Scanner.')
        return {'ok': True, 'details': result.stdout[:12000] or 'No scanners found. Your device may need a SANE backend or manufacturer driver.'}
    raise ValueError('Unknown printing/scanning operation.')


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--request-json', required=True); args = parser.parse_args()
    try: result = request(json.loads(args.request_json))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        result = {'ok': False, 'message': str(error) if isinstance(error, ValueError) else 'The tool could not be reached. Check desktop access and retry.'}
    print(json.dumps(result)); return 0 if result['ok'] else 1


if __name__ == '__main__': raise SystemExit(main())
