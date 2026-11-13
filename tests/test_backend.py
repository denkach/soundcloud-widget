import array
import importlib.util
import math
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backend', Path(__file__).resolve().parents[1]/'app/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class BackendTests(unittest.TestCase):
    def test_audio_is_only_a_single_active_matching_browser_stream(self):
        def stream(index, binary, corked=False):
            return {'index':index,'corked':corked,'properties':{'application.process.binary':binary}}
        chrome=stream(1,'chrome')
        self.assertEqual(backend.choose_stream([stream(2,'spotify'),chrome], 'chromium'),chrome)
        self.assertIsNone(backend.choose_stream([stream(1,'chrome',True)], 'chromium'))
        self.assertIsNone(backend.choose_stream([chrome,stream(3,'chrome')], 'chromium'))
        self.assertIsNone(backend.choose_stream([stream(2,'spotify')], 'chromium'))
        self.assertIsNone(backend.choose_stream([chrome], ''))

    def test_real_pcm_produces_bounded_wave_and_silence_is_zero(self):
        silence=b'\0'*2048
        self.assertEqual(backend.waveform(silence),[0.]*44)
        pcm=array.array('h',(int(7000*math.sin(i*.2)) for i in range(1024)))
        if __import__('sys').byteorder!='little':pcm.byteswap()
        bars=backend.waveform(pcm.tobytes())
        self.assertEqual(len(bars),44)
        self.assertGreater(max(bars),.1)
        self.assertTrue(all(0<=x<=1 and math.isfinite(x) for x in bars))
        self.assertEqual(len(backend.waveform(b'\0')),44)

    def test_settings_validate_and_survive_restart(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(backend,'CONFIG',Path(directory)/'settings.json'):
            backend.save_settings({'accent':'#ff9955','background':'#102030','opacity':.55,'position':'top-left','onTop':False})
            saved=backend.load_settings()
            self.assertEqual(saved['accent'],'#ff9955')
            self.assertEqual(saved['background'],'#102030')
            self.assertEqual(saved['opacity'],.55)
            self.assertEqual(saved['position'],'top-left')
            self.assertFalse(saved['onTop'])
            invalid=backend.validate({'accent':'$(touch nope)','opacity':float('nan'),'position':'elsewhere'})
            self.assertEqual(invalid['accent'],backend.DEFAULTS['accent'])
            self.assertEqual(invalid['opacity'],.9)
            self.assertEqual(invalid['position'],'bottom-right')

    def test_focus_only_toggles_the_widgets_named_blur_rule(self):
        worker=backend.Backend.__new__(backend.Backend)
        worker.interacting=False
        with patch.object(backend,'command',return_value='ok') as run:
            worker.handle({'cmd':'interaction','active':True})
            self.assertTrue(worker.interacting)
            self.assertEqual(run.call_args.args[0],['hyprctl','eval','if soundcloud_widget_set_active then soundcloud_widget_set_active(true) end'])
            worker.handle({'cmd':'interaction','active':False})
            self.assertFalse(worker.interacting)
            self.assertIn('soundcloud_widget_set_active(false)',run.call_args.args[0][-1])
            with self.assertRaises(ValueError):worker.handle({'cmd':'interaction','active':'true; do something else'})

    def test_default_window_opacities_are_read_from_hyprland(self):
        worker=backend.Backend.__new__(backend.Backend)
        worker.interacting=False
        worker.window_style=dict(activeOpacity=1.,inactiveOpacity=.6)
        output='{"option":"decoration:active_opacity","float":0.95}\n{"option":"decoration:inactive_opacity","float":0.45}\n'
        with patch.object(backend,'command',return_value=output):worker.refresh_window_style()
        self.assertEqual(worker.window_style,{'activeOpacity':.95,'inactiveOpacity':.45})


if __name__=='__main__':unittest.main()
