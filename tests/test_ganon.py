from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels


class GanonImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files or not (ROOT / 'imported/l9_ganon_blue_0.png').exists(): self.skipTest('No local Ganon import')
        return rom.read_rom(files[0])

    def test_tables(self):
        prg = self.local()
        self.assertEqual(list(prg[dungeon.GANON_FRAME_IMAGES:dungeon.GANON_FRAME_IMAGES + 8]), [6, 8, 7, 9, 0, 0, 1, 1])
        self.assertEqual(list(prg[dungeon.GANON_BURST:dungeon.GANON_BURST + 8]), [1, 2, 4, 5, 6, 8, 9, 10])
        self.assertEqual(list(prg[dungeon.GANON_START_XS:dungeon.GANON_START_XS + 2]), [0x30, 0xB0])
        self.assertEqual(list(prg[dungeon.GANON_PALETTE:dungeon.GANON_PALETTE + 8]), [0x3F, 0x1C, 4, 0x0F, 0x16, 0x2C, 0x3C, 0xFF])
        self.assertEqual(list(prg[dungeon.GANON_COLOR_SETS - 8:dungeon.GANON_COLOR_SETS]), [0x3F, 0x1C, 4, 0x0F, 7, 0x17, 0x27, 0xFF])
        xs, ys = prg[dungeon.GUARD_FIRES:dungeon.GUARD_FIRES + 5], prg[dungeon.GUARD_FIRES + 5:dungeon.GUARD_FIRES + 10]
        self.assertEqual(list(zip(xs, ys)), dungeon.GUARD_FIRE_SPOTS)

    def test_rooms_and_stats(self):
        prg = self.local()
        text = (ROOT / 'imported/enemies/ganon.tres').read_text()
        pair = prg[0x1FB4E + 0x3E // 2]
        self.assertIn(f'health = {pair >> 4}', text)
        self.assertIn('projectile_magic_blockable = false', text)
        self.assertIn('ganon_spots = PackedVector2Array(48, 96, 176, 96)', text)
        ganon = (ROOT / 'imported/rooms/l9_42.tres').read_text()
        self.assertIn('ganon.tres', ganon)
        self.assertIn('triforce_of_power.tres', ganon)
        zelda = (ROOT / 'imported/rooms/l9_32.tres').read_text()
        self.assertEqual(zelda.count('ExtResource("enemy_63")'), 4)
        self.assertIn(f'position = Vector2i(120, {0x88 - 64})', zelda)

    def test_pixels(self):
        prg = self.local()
        patterns = bytearray(8192)
        for source, length, target in [(32895, 1792, 0), (19892, 2304, 0x0700), (dungeon.UW_COMMON_SPRITES, 0x100, 0x08E0),
                                        (dungeon.LEVEL_SPRITES[9], 0x220, 0x09E0), (dungeon.BOSS_SPRITES[9], 0x400, 0x0C00)]:
            patterns[target:target + length] = prg[source:source + length]
        blue = prg[dungeon.GANON_PALETTE + 3:dungeon.GANON_PALETTE + 7]
        base = prg[0x6E04 + 0x3F]
        actual = pixels(ROOT / 'imported/l9_ganon_blue_0.png')
        # Part 1 (top right) is flipped horizontally: left tile on the right, mirrored.
        for part in range(4):
            tile = prg[0x6E83 + base + prg[dungeon.GANON_FRAME_IMAGES + part]]
            for y in range(16):
                for x in range(16):
                    sx = 15 - x if part & 1 else x
                    value = rom.chr_pixels(patterns, tile + (sx // 8) * 2 + y // 8)[y % 8][sx % 8]
                    pixel = actual[(part >> 1) * 16 + y][(part & 1) * 16 + x]
                    self.assertEqual(pixel, rom.COLORS[blue[value]] + bytes([255 if value else 0]), (part, x, y))


if __name__ == '__main__':
    unittest.main()
