#!/usr/bin/env python3
"""Local MPRIS control and browser-only PCM waveform. No microphone or network."""
import array
import json
import math
import os
import re
import selectors
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

DEFAULTS = dict(accent='#c4d7bc', background='#17201b', opacity=0.9,
                position='bottom-right', onTop=True, player='auto', workspace=0, monitor='',
                accentEnd='#8cbecb', backgroundEnd='#28384c', accentGradient=False,
                backgroundGradient=False, gradientDirection='horizontal')
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'soundcloud-widget/settings.json'
POSITIONS = {'bottom-right', 'bottom-left', 'top-right', 'top-left'}
BROWSER = re.compile(r'chrome|chromium|firefox|brave|vivaldi|zen|librewolf', re.I)


def validate(values):
    result = dict(DEFAULTS)
    for key in ('accent', 'background', 'accentEnd', 'backgroundEnd'):
        if isinstance(values.get(key), str) and re.fullmatch(r'#[0-9a-fA-F]{6}', values[key]):
            result[key] = values[key].lower()
    value = values.get('opacity')
    if isinstance(value, (int, float)) and math.isfinite(value):
        result['opacity'] = max(.25, min(1., value))
    if values.get('position') in POSITIONS:
        result['position'] = values['position']
    if isinstance(values.get('onTop'), bool):
        result['onTop'] = values['onTop']
    for key in ('accentGradient', 'backgroundGradient'):
        if isinstance(values.get(key), bool):
            result[key] = values[key]
    if values.get('gradientDirection') in ('horizontal', 'vertical'):
        result['gradientDirection'] = values['gradientDirection']
    workspace = values.get('workspace')
    if type(workspace) is int and 0 <= workspace <= 9999:
        result['workspace'] = workspace
    if isinstance(values.get('monitor'), str) and len(values['monitor']) <= 128:
        result['monitor'] = values['monitor']
    if isinstance(values.get('player'), str) and (values['player'] == 'auto' or re.fullmatch(r'org\.mpris\.MediaPlayer2\.[\w.\-]+', values['player'])):
        result['player'] = values['player']
    return result


def load_settings():
    try:
        values = json.loads(CONFIG.read_text())
        return validate(values if isinstance(values, dict) else {})
    except (OSError, ValueError):
        return dict(DEFAULTS)


def save_settings(settings):
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=CONFIG.parent, prefix='.settings-')
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(validate(settings), stream, ensure_ascii=False, indent=2)
            stream.write('\n')
        os.replace(name, CONFIG)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def unpack(value):
    if isinstance(value, GLib.Variant):
        return unpack(value.unpack())
    if isinstance(value, dict):
        return {k: unpack(v) for k, v in value.items()}
    if isinstance(value, (tuple, list)):
        return [unpack(v) for v in value]
    return value


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=1.2, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip()[:200])
    return result.stdout


def browser_family(value):
    value = value.lower()
    if any(s in value for s in ('chrome', 'chromium')):
        return 'chromium'
    if any(s in value for s in ('firefox', 'zen', 'librewolf')):
        return 'firefox'
    if 'brave' in value:
        return 'brave'
    if 'vivaldi' in value:
        return 'vivaldi'
    return ''


def choose_stream(streams, family):
    matches = []
    for stream in streams:
        props = stream.get('properties', {})
        name = ' '.join(str(props.get(k, '')) for k in ('application.name', 'application.process.binary'))
        if family and browser_family(name) == family and not stream.get('corked', True):
            matches.append(stream)
    return matches[0] if len(matches) == 1 else None


def waveform(pcm, count=44):
    samples = array.array('h')
    samples.frombytes(pcm[:len(pcm)//2*2])
    if sys.byteorder != 'little':
        samples.byteswap()
    if not samples:
        return [0.] * count
    width = max(1, len(samples)//count)
    bars = []
    for i in range(count):
        part = samples[i*width:(i+1)*width]
        rms = math.sqrt(sum(x*x for x in part) / max(1, len(part))) / 32768
        bars.append(min(1., rms ** .58 * 2.6))
    return bars


class Backend:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.settings = load_settings()
        self.ack = 0
        self.media = {}
        self.players = []
        self.stream = None
        self.capture = None
        self.capture_key = None
        self.audio_status = 'Ожидаем музыку в браузере'
        self.bars = [0.] * 44
        self.selector = selectors.DefaultSelector()
        self.selector.register(sys.stdin, selectors.EVENT_READ, 'input')
        self.last_audio = time.monotonic()
        self.error = ''
        self.interacting = False
        self.window_style = dict(activeOpacity=1., inactiveOpacity=.6)
        self.next_style_refresh = 0

    def apply_focus_blur(self):
        active = 'true' if self.interacting else 'false'
        command(['hyprctl', 'eval', 'if soundcloud_widget_set_active then soundcloud_widget_set_active('+active+') end'])

    def refresh_window_style(self):
        try:
            output = command(['hyprctl', '--batch', '-j',
                'getoption decoration:active_opacity; getoption decoration:inactive_opacity'])
            values = {d['option']:d.get('float') for d in
                      (json.loads(s) for s in re.findall(r'\{[^{}]*\}', output))}
            for key, option in [('activeOpacity','decoration:active_opacity'),
                                ('inactiveOpacity','decoration:inactive_opacity')]:
                value = values.get(option)
                if isinstance(value,(int,float)) and math.isfinite(value):
                    self.window_style[key] = max(0.,min(1.,value))
            # Reconcile our named rule after a Hyprland theme/config reload.
            self.apply_focus_blur()
        except (OSError,ValueError,RuntimeError,subprocess.TimeoutExpired):
            pass

    def call(self, name, interface, method, parameters=None):
        return unpack(self.bus.call_sync(name, '/org/mpris/MediaPlayer2', interface, method,
                      parameters, None, Gio.DBusCallFlags.NONE, 500, None))

    def props(self, name, interface):
        return self.call(name, 'org.freedesktop.DBus.Properties', 'GetAll', GLib.Variant('(s)', (interface,)))[0]

    def refresh(self):
        names = unpack(self.bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus',
                        'org.freedesktop.DBus', 'ListNames', None, None, Gio.DBusCallFlags.NONE, 500, None))[0]
        found = []
        for name in names:
            if not name.startswith('org.mpris.MediaPlayer2.') or not BROWSER.search(name):
                continue
            try:
                p = self.props(name, 'org.mpris.MediaPlayer2.Player')
                base = self.props(name, 'org.mpris.MediaPlayer2')
                meta = p.get('Metadata', {})
                artists = meta.get('xesam:artist', [])
                url = str(meta.get('xesam:url', ''))
                art = str(meta.get('mpris:artUrl', ''))
                known = bool(re.search(r'https?://(?:[^/]+\.)?soundcloud\.com/', url)) or 'sndcdn.com/' in art
                duration = max(0, meta.get('mpris:length', 0)/1e6)
                if duration > 7*24*3600:  # Chromium's live streams use INT64_MAX.
                    duration = 0
                found.append(dict(id=name, identity=base.get('Identity', 'Браузер'), title=str(meta.get('xesam:title', '')),
                    artist=', '.join(artists) if isinstance(artists, list) else str(artists), art=art,
                    url=url, soundcloud=known, playing=p.get('PlaybackStatus') == 'Playing',
                    length=duration, position=max(0, p.get('Position', 0)/1e6),
                    canPlay=bool(p.get('CanPlay')), canPause=bool(p.get('CanPause')),
                    canNext=bool(p.get('CanGoNext')), canPrevious=bool(p.get('CanGoPrevious')),
                    canSeek=bool(p.get('CanSeek')), trackId=meta.get('mpris:trackid', ''),
                    family=browser_family(name+' '+base.get('Identity', ''))))
            except GLib.Error:
                continue
        self.players = [dict(id=p['id'], identity=p['identity']) for p in found]
        preferred = self.settings['player']
        selected = next((p for p in found if p['id'] == preferred), None) if preferred != 'auto' else None
        if preferred == 'auto' and found:
            selected = max(found, key=lambda p: (p['soundcloud'], p['playing'], bool(p['title'])))
        self.media = selected or {}
        self.stream = None
        try:
            streams = json.loads(command(['pactl', '--format=json', 'list', 'sink-inputs']))
            if selected and selected['playing']:
                self.stream = choose_stream(streams, selected['family'])
                matches = [s for s in streams if not s.get('corked', True) and browser_family(' '.join(str(s.get('properties', {}).get(k, '')) for k in ('application.name', 'application.process.binary'))) == selected['family']]
                self.audio_status = 'Несколько потоков браузера — оставь один' if len(matches) > 1 else 'Ожидаем звук браузера'
            if self.stream:
                sink_id = self.stream['sink']
                sinks = json.loads(command(['pactl', '--format=json', 'list', 'sinks']))
                sink = next((s for s in sinks if s['index'] == sink_id), {})
                monitor = sink.get('monitor_source')
                key = (self.stream['index'], monitor)
                if monitor and str(monitor).endswith('.monitor'):
                    if key != self.capture_key or not self.capture or self.capture.poll() is not None:
                        self.stop_capture()
                        self.capture = subprocess.Popen(['parec', '--raw', '--format=s16le', '--rate=22050', '--channels=1',
                            '--latency-msec=60', '--device='+str(monitor), '--monitor-stream='+str(key[0]),
                            '--client-name=SoundCloud Widget', '--stream-name=Browser waveform'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                        os.set_blocking(self.capture.stdout.fileno(), False)
                        self.selector.register(self.capture.stdout, selectors.EVENT_READ, 'audio')
                        self.capture_key = key
                        self.last_audio = time.monotonic()
                    self.audio_status = 'Звук браузера'
            else:
                self.stop_capture()
                if not selected:
                    self.audio_status = 'Открой SoundCloud и включи трек'
                elif not selected['playing']:
                    self.audio_status = 'На паузе'
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
            self.stop_capture()
            self.audio_status = 'Звуковой поток недоступен'
            self.error = str(exc)[:150]

    def stop_capture(self):
        if self.capture:
            try:
                self.selector.unregister(self.capture.stdout)
            except (KeyError, ValueError):
                pass
            self.capture.terminate()
            try:
                self.capture.wait(timeout=.4)
            except subprocess.TimeoutExpired:
                self.capture.kill()
                self.capture.wait()
            self.capture.stdout.close()
        self.capture = None
        self.capture_key = None
        self.bars = [0.] * 44

    def handle(self, request):
        cmd = request.get('cmd')
        if cmd == 'focus-workspace':
            workspace = self.settings['workspace']
            if workspace > 0:
                command(['hyprctl', 'eval', 'hl.dispatch(hl.dsp.focus({workspace = '+str(workspace)+'}))'])
        elif cmd == 'interaction':
            if not isinstance(request.get('active'), bool):
                raise ValueError('Interaction state must be boolean')
            self.interacting = request['active']
            self.apply_focus_blur()
        elif cmd == 'settings':
            self.settings = validate(request.get('settings', {}))
            save_settings(self.settings)
            self.ack = int(request.get('serial', 0))
        elif cmd == 'volume' and self.stream:
            percent = max(0, min(100, int(request.get('value', 0))))
            command(['pactl', 'set-sink-input-volume', str(self.stream['index']), str(percent)+'%'])
        elif cmd == 'open':
            subprocess.Popen(['xdg-open', 'https://soundcloud.com/you/library'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif self.media:
            method = {'toggle':'PlayPause', 'next':'Next', 'previous':'Previous'}.get(cmd)
            allowed = {'toggle':self.media['canPause'] if self.media['playing'] else self.media['canPlay'],
                       'next':self.media['canNext'], 'previous':self.media['canPrevious']}
            if method and allowed.get(cmd):
                self.call(self.media['id'], 'org.mpris.MediaPlayer2.Player', method)
            elif cmd == 'seek' and self.media['canSeek'] and self.media['trackId']:
                position = max(0, min(self.media['length'], float(request.get('seconds', 0))))
                self.call(self.media['id'], 'org.mpris.MediaPlayer2.Player', 'SetPosition',
                          GLib.Variant('(ox)', (self.media['trackId'], int(position*1e6))))

    def run(self):
        next_refresh = 0
        next_frame = 0
        pcm = bytearray()
        try:
            while True:
                for key, _ in self.selector.select(.025):
                    if key.data == 'input':
                        line = sys.stdin.readline()
                        if not line:
                            return
                        try:
                            self.handle(json.loads(line))
                        except (ValueError, TypeError, OSError, RuntimeError, GLib.Error, subprocess.TimeoutExpired) as exc:
                            self.error = str(exc)[:150]
                    elif self.capture:
                        data = os.read(key.fd, 16384)
                        if data:
                            pcm.extend(data)
                            if len(pcm) > 8192:
                                del pcm[:-8192]
                            self.last_audio = time.monotonic()
                now = time.monotonic()
                if now >= self.next_style_refresh:
                    self.refresh_window_style()
                    self.next_style_refresh = now + 3
                if now >= next_refresh:
                    self.refresh()
                    next_refresh = now + .65
                if now >= next_frame:
                    if pcm and self.media.get('playing'):
                        target = waveform(bytes(pcm[-2048:]))
                        self.bars = [old + (new-old)*(.55 if new > old else .20)
                                     for old,new in zip(self.bars,target)]
                        pcm.clear()
                    else:
                        self.bars = [v*.72 for v in self.bars]
                    if now-self.last_audio > .3 or not self.media.get('playing'):
                        self.bars = [v*.5 for v in self.bars]
                    volume = 65
                    if self.stream:
                        channels = list(self.stream.get('volume', {}).values())
                        if channels:
                            volume = round(sum(v.get('value',0) for v in channels)/len(channels)/65536*100)
                    print(json.dumps(dict(settings=self.settings, configAck=self.ack, media=self.media, players=self.players,
                        bars=self.bars, audioStatus=self.audio_status, volume=volume,
                        hasStream=bool(self.stream), error=self.error, windowStyle=self.window_style,
                        interacting=self.interacting), ensure_ascii=False), flush=True)
                    next_frame = now + .04
        finally:
            self.stop_capture()


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        Backend().run()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
