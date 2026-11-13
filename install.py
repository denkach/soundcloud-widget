#!/usr/bin/env python3
"""Install into the current user's home; preserve settings and back up Lua edits."""
import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
BEGIN = '-- BEGIN soundcloud-widget'
END = '-- END soundcloud-widget'


def atomic_write(path, content, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.install-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def managed_config(text):
    block = BEGIN + '\n' + (SOURCE/'config/hyprland.lua').read_text().rstrip() + '\n' + END
    first = text.find(BEGIN)
    if first < 0:
        return text.rstrip() + '\n\n' + block + '\n'
    last = text.find(END, first)
    if last < 0:
        raise ValueError('The existing widget block has no END marker; leaving it untouched.')
    return text[:first] + block + text[last+len(END):]


def install(home, autostart=False):
    custom = (home/'.config/hypr/custom.lua').resolve()
    old = custom.read_text() if custom.exists() else ''
    updated = None
    if autostart:
        main = home/'.config/hypr/hyprland.lua'
        if not main.exists() or not re.search(r'''require\s*\(\s*['"]custom['"]\s*\)''', main.read_text()):
            raise ValueError('--autostart requires an ML4W-style hyprland.lua that loads require("custom"). '
                             'Install without that flag and use the manual Lua integration in README.md.')
        updated = managed_config(old)
    target = home/'.local/share/soundcloud-widget'
    for name in ('backend.py', 'shell.qml'):
        atomic_write(target/'app'/name, (SOURCE/'app'/name).read_text())
    atomic_write(target/'hyprland.lua', (SOURCE/'config/hyprland.lua').read_text())
    atomic_write(home/'.local/bin/soundcloud-widget', (SOURCE/'soundcloud-widget').read_text(), 0o755)
    (home/'.config/soundcloud-widget').mkdir(parents=True, exist_ok=True)
    (home/'.local/state/soundcloud-widget').mkdir(parents=True, exist_ok=True)
    backup = None
    if updated is not None and updated != old:
        if custom.exists():
            backup = home/'.local/state/soundcloud-widget/backups'/('custom.lua.install-'+str(time.time_ns()))
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(custom, backup)
        mode = custom.stat().st_mode & 0o777 if custom.exists() else 0o644
        atomic_write(custom, updated, mode)
    return target, backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--autostart', action='store_true', help='Add the managed block to an ML4W custom.lua.')
    args = parser.parse_args()
    missing = [binary for binary in ('qs', 'pactl', 'parec', 'hyprctl') if not shutil.which(binary)]
    if importlib.util.find_spec('gi') is None:
        missing.append('Python PyGObject (gi)')
    if missing:
        parser.exit(1, 'Missing dependencies: '+', '.join(missing)+'\nSee README.md.\n')
    try:
        target, backup = install(Path.home(), args.autostart)
    except (OSError, ValueError) as exc:
        parser.exit(1, str(exc)+'\n')
    print('Installed:', target)
    if backup:
        print('Hyprland backup:', backup)
    if args.autostart and os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
        result = subprocess.run(['hyprctl', 'reload', 'config-only'], capture_output=True, text=True)
        if result.returncode:
            print('Reload Hyprland after checking the Lua integration:', result.stderr.strip())
    if not args.autostart:
        print('Load', target/'hyprland.lua', 'from your Hyprland Lua config for blur and autostart.')
    print('Start: ~/.local/bin/soundcloud-widget start')


if __name__ == '__main__':
    main()
