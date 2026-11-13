import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

spec=importlib.util.spec_from_file_location('opener',Path(__file__).resolve().parents[1]/'app/open_soundcloud.py')
opener=importlib.util.module_from_spec(spec)
spec.loader.exec_module(opener)


def browser(address='0x123',title='SoundCloud',history=0):
    return dict(address=address,title=title,**{'class':'google-chrome'},mapped=True,focusHistoryID=history)


class OpenSoundCloudTests(unittest.TestCase):
    def test_selects_changed_or_new_soundcloud_tab_not_unrelated_windows(self):
        previous=[browser('0x123','SoundCloud'),browser('0x456','Other site',2)]
        changed=browser('0x456','SoundCloud library',2)
        self.assertEqual(opener.soundcloud_window([previous[0],changed],previous),changed)
        self.assertIsNone(opener.soundcloud_window([browser(title='Another site'),dict(browser(),**{'class':'kitty'})],[]))

    def test_rejects_invalid_window_address_and_unmapped_browser(self):
        self.assertIsNone(opener.soundcloud_window([browser("0x123\"); os.execute('nope')")],[]))
        self.assertIsNone(opener.soundcloud_window([dict(browser(),mapped=False)],[]))

    def test_hands_url_to_default_browser_and_focuses_only_validated_address(self):
        target=browser(title='SoundCloud "); os.execute("nope")')
        child=Mock();child.poll.return_value=0
        with patch.object(opener,'hyprland',side_effect=[json.dumps([browser(title='Old tab')]),json.dumps([target]),'ok']) as hypr, \
             patch.object(opener.subprocess,'Popen',return_value=child) as launch, \
             patch.object(opener.time,'monotonic',side_effect=[0,.5,.5]):
            opener.open_soundcloud()
        self.assertEqual(launch.call_args.args[0],['xdg-open',opener.URL])
        self.assertEqual(hypr.call_args.args,('eval','hl.dispatch(hl.dsp.focus({window = "address:0x123"}))'))

    def test_reports_failed_browser_launch(self):
        child=Mock();child.poll.return_value=127
        with patch.object(opener,'hyprland',return_value='[]'), \
             patch.object(opener.subprocess,'Popen',return_value=child), \
             patch.object(opener.time,'monotonic',side_effect=[0,.1]):
            with self.assertRaisesRegex(RuntimeError,'127'):
                opener.open_soundcloud()
