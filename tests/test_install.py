import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[1]/'install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def test_install_preserves_preferences_and_other_lua_and_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            config=home/'.config/hypr';config.mkdir(parents=True)
            (config/'hyprland.lua').write_text('require("custom")\n')
            custom=config/'custom.lua';original='-- existing customization\nlocal preserved = 42\n'
            custom.write_text(original)
            settings=home/'.config/soundcloud-widget/settings.json';settings.parent.mkdir(parents=True)
            settings.write_text('{"opacity":0.55}')
            target,backup=installer.install(home,True)
            self.assertEqual(backup.read_text(),original)
            self.assertIn(original.strip(),custom.read_text())
            self.assertEqual(custom.read_text().count(installer.BEGIN),1)
            self.assertTrue((target/'app/backend.py').is_file())
            self.assertTrue((target/'app/SettingsPanel.qml').is_file())
            self.assertTrue((target/'app/ColorPalette.qml').is_file())
            self.assertTrue((home/'.local/bin/soundcloud-widget').stat().st_mode & 0o100)
            again=custom.read_text()
            installer.install(home,True)
            self.assertEqual(custom.read_text(),again)
            self.assertEqual(settings.read_text(),'{"opacity":0.55}')

    def test_unknown_lua_layout_and_broken_marker_are_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            with self.assertRaises(ValueError):installer.install(home,True)
            self.assertFalse((home/'.local/share/soundcloud-widget').exists())
        with self.assertRaises(ValueError):installer.managed_config('-- BEGIN soundcloud-widget\nunfinished')

    def test_manual_install_does_not_change_hyprland(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            target,_=installer.install(home,False)
            self.assertTrue((target/'hyprland.lua').exists())
            self.assertFalse((home/'.config/hypr/custom.lua').exists())
