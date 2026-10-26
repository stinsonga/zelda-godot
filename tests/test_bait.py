from pathlib import Path
import json
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon

class BaitImportTests(unittest.TestCase):
    def test_hungry_resident_matches_source(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        cave = ROOT / 'imported/caves/uw_l7_28.tres'
        if not files or not cave.exists():
            self.skipTest('No local ROM import')
        prg = rom.read_rom(files[0])
        expected = dungeon.person_cave(prg, 7, 0x28, 0x36)['text']
        self.assertEqual(cave.read_text(), expected)
        self.assertIn('text = ' + json.dumps(dungeon.person_text(prg, 0x24)), expected)
        for field in ['accepts_bait = true', 'remember = true', 'text_line_offset = 2']:
            self.assertIn(field, expected)
        self.assertTrue((ROOT / 'imported/l7_hungry_goriya.png').exists())
