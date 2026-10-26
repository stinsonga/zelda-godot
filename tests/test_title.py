from pathlib import Path
import json
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_title as title


class TitleImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files: self.skipTest('No local ROM')
        return rom.read_rom(files[0])

    def test_table_locations(self):
        prg = self.local()
        # Each palette record opens with its $3F00 header; the glow record writes $3F04.
        self.assertEqual(len(title.record_palette(prg, title.TITLE_PALETTE)), 32)
        self.assertEqual(len(title.record_palette(prg, title.STORY_PALETTE)), 32)
        self.assertEqual(list(prg[title.GLOW_RECORD:title.GLOW_RECORD + 3]), [0x3F, 0x04, 0x04])
        self.assertEqual(prg[title.GLOW_RECORD + 7], 0xFF)
        # The fade ends on black and holds two steps for $C0 frames.
        self.assertEqual(set(prg[title.FADE_PALETTES + 13 * 32:title.FADE_PALETTES + 14 * 32]), {0x0F})
        self.assertEqual(list(prg[title.FADE_DELAYS:title.FADE_DELAYS + 14]).count(0xC0), 2)
        # Item rows: the left list ends with the four picture rows ($30-$33).
        self.assertEqual(list(prg[title.LEFT_ITEMS + 18:title.LEFT_ITEMS + 22]), [0x30, 0x31, 0x32, 0x33])
        self.assertEqual(list(prg[title.COLUMN_XS:title.COLUMN_XS + 2]), [0x44, 0xAC])

    def test_story_lines_and_tables(self):
        prg = self.local()
        lines = title.text_lines(prg)
        self.assertEqual(len(lines), title.TEXT_LINES)
        for line in lines: self.assertLessEqual(line[0] + len(line) - 1, 32)
        # One text line for each line marked $80, one item row for each $20.
        attrs = list(prg[title.LINE_ATTRS:title.LINE_ATTRS + 175])
        self.assertEqual(sum(1 for a in attrs if a & 0x80), title.TEXT_LINES)
        self.assertEqual(sum(1 for a in attrs if a & 0x20), 22)
        tables = title.blank_tables()
        title.apply_records(prg, title.STORY_BUFFER, tables)
        self.assertTrue(any(t != 0x24 for t in tables[0][:960]))
        self.assertEqual(set(tables[1][:960]), {0x24})

    def test_export(self):
        path = ROOT / 'imported/title/title.json'
        if not path.exists(): self.skipTest('No local title import')
        data = json.loads(path.read_text())
        self.assertEqual(data['format'], 1)
        self.assertEqual(len(data['title_sprites']), 112)
        self.assertEqual(len(data['items']['35']['frames']), 2)
        self.assertEqual(len(data['colors']), 64)


if __name__ == '__main__':
    unittest.main()
