from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels


class LanmolaImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files or not (ROOT / 'imported/l9_blue_lanmola_head.png').exists(): self.skipTest('No local Lanmola import')
        return rom.read_rom(files[0])

    def test_stats_and_encounters(self):
        prg = self.local()
        for kind, name in ((0x3A, 'red_lanmola'), (0x3B, 'blue_lanmola')):
            text = (ROOT / 'imported/enemies' / f'{name}.tres').read_text()
            self.assertIn('chain_style = "lanmola"', text)
            self.assertIn(f'chain_speed = {kind - 0x39}', text)
            segment = (ROOT / 'imported/enemies' / f'{name}_segment.tres').read_text()
            pair = prg[0x1FB4E + kind // 2]
            self.assertIn(f'health = {max(1, pair & 15 if kind & 1 else pair >> 4)}', segment)
            self.assertEqual(dungeon.FIXED_POSITIONS[kind], (0x40, 0x8D))
        rooms = [p for p in (ROOT / 'imported/rooms').glob('l9_*.tres') if 'lanmola.tres' in p.read_text()]
        self.assertTrue(rooms)
        for path in rooms: self.assertIn('persistence_enemy_count = 8', path.read_text())

    def test_segment_pixels(self):
        prg = self.local()
        info = dungeon.level_info(prg, 9)
        patterns = bytearray(8192)
        for source, length, target in [(32895, 1792, 0), (19892, 2304, 0x0700), (dungeon.UW_COMMON_SPRITES, 0x100, 0x08E0),
                                        (dungeon.LEVEL_SPRITES[9], 0x220, 0x09E0), (dungeon.BOSS_SPRITES[9], 0x400, 0x0C00)]:
            patterns[target:target + length] = prg[source:source + length]
        # Speed 2 XOR 3 = attribute 1: the blue sprite row.
        palette = info[3 + 5 * 4:7 + 5 * 4]
        for part, tile in (('head', 0x9E), ('body', 0xA0)):
            actual = pixels(ROOT / 'imported' / f'l9_blue_lanmola_{part}.png')
            for y in range(16):
                for x in range(16):
                    if x < 4 or x >= 12:
                        self.assertEqual(actual[y][x][3], 0)
                        continue
                    value = rom.chr_pixels(patterns, tile + y // 8)[y % 8][x - 4]
                    self.assertEqual(actual[y][x], rom.COLORS[palette[value]] + bytes([255 if value else 0]), (part, x, y))


if __name__ == '__main__':
    unittest.main()
