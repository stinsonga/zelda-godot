from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels


class PatraImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files or not (ROOT / 'imported/l9_patra_0.png').exists(): self.skipTest('No local Patra import')
        return rom.read_rom(files[0])

    def test_tables(self):
        prg = self.local()
        # PatraChildStartAngles directly precede the overlapping rotation bit tables.
        self.assertEqual(list(prg[dungeon.PATRA_BITS - 7:dungeon.PATRA_BITS + 4]),
                         [0x14, 0x10, 0x0C, 0x08, 0x04, 0x00, 0x1C, 6, 5, 6, 6])
        self.assertEqual(list(prg[dungeon.PATRA_MANEUVER_TIMES:dungeon.PATRA_MANEUVER_TIMES + 2]), [0xFF, 0x50])

    def test_stats_and_encounters(self):
        prg = self.local()
        for kind, child_kind in ((0x47, 0x25), (0x48, 0x26)):
            name = dungeon.MONSTERS[kind][0]
            text = (ROOT / 'imported/enemies' / f'{name}.tres').read_text()
            pair = prg[0x1FB4E + kind // 2]
            self.assertIn(f'health = {pair & 15 if kind & 1 else pair >> 4}', text)
            self.assertIn('flight_max_speed = 64', text)
            self.assertIn('invincible_to = PackedStringArray("boomerang", "arrow", "bomb", "fire", "magic")', text)
            child = (ROOT / 'imported/enemies' / f'{name}_child.tres').read_text()
            pair = prg[0x1FB4E + child_kind // 2]
            raw = prg[0x72BA + child_kind]
            self.assertIn(f'health = {pair & 15 if child_kind & 1 else pair >> 4}', child)
            self.assertIn(f'contact_damage = {(raw & 15) * 2 + bool(raw & 240)}', child)
            self.assertIn('counts_for_persistence = false', child)
            self.assertEqual(dungeon.FIXED_POSITIONS[kind], (0x80, 0x70))
        rooms = [p for p in (ROOT / 'imported/rooms').glob('l9_*.tres') if 'patra_' in p.read_text()]
        self.assertEqual(len(rooms), 5)

    def test_pixels(self):
        prg = self.local()
        info = dungeon.level_info(prg, 9)
        patterns = bytearray(8192)
        for source, length, target in [(32895, 1792, 0), (19892, 2304, 0x0700), (dungeon.UW_COMMON_SPRITES, 0x100, 0x08E0),
                                        (dungeon.LEVEL_SPRITES[9], 0x220, 0x09E0), (dungeon.BOSS_SPRITES[9], 0x400, 0x0C00)]:
            patterns[target:target + length] = prg[source:source + length]
        # Patra: table attribute 1, left tile $F8 and right $FA; pose 1 flipped.
        frame = prg[0x6E04 + 0x48]
        tile, attr = prg[0x6E83 + frame], prg[0x6F4F + frame]
        palette = info[3 + (4 + (attr & 3)) * 4:7 + (4 + (attr & 3)) * 4]
        for pose in range(2):
            actual = pixels(ROOT / 'imported' / f'l9_patra_{pose}.png')
            for y in range(16):
                for x in range(16):
                    sx = 15 - x if pose else x
                    value = rom.chr_pixels(patterns, tile + (sx // 8) * 2 + y // 8)[y % 8][sx % 8]
                    self.assertEqual(actual[y][x], rom.COLORS[palette[value]] + bytes([255 if value else 0]), (pose, x, y))
        # Children: half-width, red row 6.
        palette = info[3 + 6 * 4:7 + 6 * 4]
        frame = prg[0x6E04 + 0x26]
        for pose in range(2):
            tile = prg[0x6E83 + frame + pose]
            actual = pixels(ROOT / 'imported' / f'l9_patra_child_{pose}.png')
            for y in range(16):
                for x in range(16):
                    if x >= 8:
                        self.assertEqual(actual[y][x][3], 0)
                        continue
                    value = rom.chr_pixels(patterns, tile + y // 8)[y % 8][x]
                    self.assertEqual(actual[y][x], rom.COLORS[palette[value]] + bytes([255 if value else 0]), (pose, x, y))


if __name__ == '__main__':
    unittest.main()
