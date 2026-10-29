"""Distribution must include the separate editor, without its generated cache."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import prepare_public_project as packaging

class EditorPackagingTests(unittest.TestCase):
    def source_tree(self, folder):
        source=Path(folder)/'source'; source.mkdir()
        for name in packaging.FILES:(source/name).write_text('authored')
        for name in packaging.DIRECTORIES:(source/name).mkdir()
        for name in ['editor/project.godot','editor/shared/room_pack.gd','content/pack.json',
                     'editor/.godot/imported/cache.bin','editor/__pycache__/code.pyc',
                     'editor/local.nes','content/art/custom/library.json',
                     'content/art/custom/tiles.png']:
            path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('test')
        return source
    def test_editor_is_included_but_nested_cache_and_rom_are_not(self):
        with tempfile.TemporaryDirectory() as folder:
            source=self.source_tree(folder); output=Path(folder)/'public'
            with patch.object(packaging,'ROOT',source):packaging.prepare(output)
            self.assertTrue((output/'editor/project.godot').exists())
            self.assertTrue((output/'editor/shared/room_pack.gd').exists())
            self.assertTrue((output/'content/art/custom/library.json').exists())
            self.assertTrue((output/'content/art/custom/tiles.png').exists())
            self.assertFalse((output/'editor/.godot').exists())
            self.assertFalse((output/'editor/__pycache__').exists())
            self.assertFalse((output/'editor/local.nes').exists())
    def test_unreviewed_editor_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            source=self.source_tree(folder)
            (source/'editor/linked.gd').symlink_to(source/'editor/shared/room_pack.gd')
            with patch.object(packaging,'ROOT',source):
                with self.assertRaisesRegex(ValueError,'Symlinks'):packaging.prepare(Path(folder)/'public')

if __name__=='__main__':unittest.main()
