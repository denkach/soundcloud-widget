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

    def test_workspace_and_gradient_settings_migrate_and_persist(self):
        migrated=backend.validate({'accent':'#c4d7bc'})
        self.assertEqual(migrated['workspace'],0)
        self.assertFalse(migrated['backgroundGradient'])
        with tempfile.TemporaryDirectory() as directory, patch.object(backend,'CONFIG',Path(directory)/'settings.json'):
            values=dict(workspace=3,monitor='DP-3',accentGradient=True,accentEnd='#ABCDEF',
                        backgroundGradient=True,backgroundEnd='#102030',gradientDirection='vertical')
            backend.save_settings(values)
            saved=backend.load_settings()
            self.assertEqual(saved['workspace'],3)
            self.assertEqual(saved['monitor'],'DP-3')
            self.assertEqual(saved['accentEnd'],'#abcdef')
            self.assertTrue(saved['accentGradient'])
            self.assertTrue(saved['backgroundGradient'])
            self.assertEqual(saved['backgroundEnd'],'#102030')
            self.assertEqual(saved['gradientDirection'],'vertical')
        for workspace in (True,-1,10000,3.5,'3'):
            self.assertEqual(backend.validate({'workspace':workspace})['workspace'],0)
        bad=backend.validate({'accentEnd':'#bad','backgroundGradient':'yes','gradientDirection':'diagonal'})
        self.assertEqual(bad['accentEnd'],backend.DEFAULTS['accentEnd'])
        self.assertFalse(bad['backgroundGradient'])
        self.assertEqual(bad['gradientDirection'],'horizontal')

    def test_default_window_opacities_are_read_from_hyprland(self):
        worker=backend.Backend.__new__(backend.Backend)
        worker.window_style=dict(activeOpacity=1.,inactiveOpacity=.6)
        output='{"option":"decoration:active_opacity","float":0.95}\n{"option":"decoration:inactive_opacity","float":0.45}\n'
        with patch.object(backend,'command',return_value=output) as run:
            worker.refresh_window_style()
            # Theme refresh must never race the dedicated UI focus controller.
            run.assert_called_once_with(['hyprctl','--batch','-j',
                'getoption decoration:active_opacity; getoption decoration:inactive_opacity'])
        self.assertEqual(worker.window_style,{'activeOpacity':.95,'inactiveOpacity':.45})

    def test_settings_command_focuses_only_the_saved_workspace(self):
        worker=backend.Backend.__new__(backend.Backend)
        worker.settings=backend.validate({'workspace':3})
        with patch.object(backend,'command',return_value='ok') as run:
            worker.handle({'cmd':'focus-workspace','workspace':'1; os.execute("nope")'})
            self.assertEqual(run.call_args.args[0],['hyprctl','eval','hl.dispatch(hl.dsp.focus({workspace = 3}))'])
            worker.settings=backend.validate({'workspace':0})
            run.reset_mock()
            worker.handle({'cmd':'focus-workspace'})
            run.assert_not_called()


if __name__=='__main__':unittest.main()
