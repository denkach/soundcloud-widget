#!/usr/bin/env python3
"""Open SoundCloud with the default browser and reveal its window in Hyprland."""
import json
import re
import subprocess
import sys
import tempfile
import time

URL = 'https://soundcloud.com/you/library'
BROWSER = re.compile(r'chrome|chromium|firefox|brave|vivaldi|zen|librewolf|msedge|microsoft-edge|floorp|waterfox', re.I)
ADDRESS = re.compile(r'0x[0-9a-fA-F]+')


def hyprland(*args):
    result = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=2)
    if result.returncode or result.stdout.lstrip().startswith('error:'):
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Hyprland command failed')
    return result.stdout


def soundcloud_window(clients, previous):
    before = {client.get('address'): client for client in previous}
    candidates = [client for client in clients
                  if ADDRESS.fullmatch(str(client.get('address', '')))
                  and client.get('mapped', True)
                  and BROWSER.search(str(client.get('class', '')) + ' ' + str(client.get('initialClass', '')))
                  and 'soundcloud' in str(client.get('title', '')).lower()]
    # Prefer the window whose active tab just changed, or a newly opened window.
    return max(candidates, key=lambda c: (
        c['address'] not in before or c.get('title') != before[c['address']].get('title'),
        -c.get('focusHistoryID', 10000)), default=None)


def open_soundcloud():
    previous = json.loads(hyprland('-j', 'clients'))
    with tempfile.TemporaryFile() as errors:
        opener = subprocess.Popen(['xdg-open', URL], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.DEVNULL, stderr=errors, start_new_session=True)
        started = time.monotonic()
        deadline = started + 10
        while time.monotonic() < deadline:
            result = opener.poll()
            if result is not None and result != 0:
                errors.seek(0)
                raise RuntimeError(errors.read(1200).decode(errors='replace').strip()
                                   or 'Не удалось запустить браузер: код '+str(result))
            clients = json.loads(hyprland('-j', 'clients'))
            window = soundcloud_window(clients, previous)
            # Allow the URL handoff to finish before focusing an existing tab.
            if window and time.monotonic() - started >= .25:
                address = window['address']
                # Only a validated hexadecimal address enters Lua, never a page title.
                hyprland('eval', 'hl.dispatch(hl.dsp.focus({window = "address:'+address+'"}))')
                return
            time.sleep(.1)
        raise RuntimeError('Ссылка передана браузеру, но окно SoundCloud не найдено. Проверь браузер.')


if __name__ == '__main__':
    try:
        open_soundcloud()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
