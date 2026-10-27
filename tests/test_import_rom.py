"""Run: python3 -m unittest discover -s godot/tests -p 'test_*.py'."""
import importlib.util
from pathlib import Path
import tempfile
import struct
import zlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('import_rom', ROOT / 'tools/import_rom.py')
rom_import = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rom_import)


def pixels(path):
    data = path.read_bytes()
    offset, compressed = 8, b''
    width, height = struct.unpack_from('>II', data, 16)
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        if data[offset + 4:offset + 8] == b'IDAT':
            compressed += data[offset + 8:offset + 8 + size]
        offset += size + 12
    raw = zlib.decompress(compressed)
    stride = width * 4 + 1
    return [[raw[y * stride + 1 + x * 4:y * stride + 5 + x * 4]
             for x in range(width)] for y in range(height)]


class ImportValidation(unittest.TestCase):
    def test_bad_inputs_are_rejected(self):
        header = b'NES\x1a' + bytes([8, 0, 0x12, 0]) + bytes(8)
        samples = [b'not a rom', header + bytes(10), header + bytes(131072),
                   header[:6] + b'\x16' + header[7:] + bytes(131072)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'input.nes'
            for sample in samples:
                with self.subTest(size=len(sample), header=sample[:8]):
                    path.write_bytes(sample)
                    with self.assertRaises(ValueError):
                        rom_import.read_rom(path)

    def test_vertical_pairs_keep_the_higher_tile(self):
        # Room $64's corner: solid $DD beside walkable $DF reads as $DF, so it is open.
        codes = [0x26] * 704
        codes[5 * 32 + 4], codes[5 * 32 + 5] = 0xDD, 0xDF
        pairs = rom_import.pair_collision(codes)
        self.assertEqual((pairs[5 * 32 + 4], pairs[5 * 32 + 3]), (0, 1))
        # A solid tile numbered above its walkable neighbour still blocks, so the
        # pairs match checking each column and the map is omitted.
        codes[5 * 32 + 4], codes[5 * 32 + 5] = 0xDF, 0xE0
        self.assertEqual(rom_import.pair_collision(codes), [])

    def test_monsters_turn_after_hitting_link_unless_flagged(self):
        prg = bytearray(0x20000)
        prg[rom_import.import_dungeons.OBJECT_ATTRIBUTES + 0x07] = 0x05
        prg[rom_import.import_dungeons.OBJECT_ATTRIBUTES + 0x0D] = 0x81
        self.assertEqual(rom_import.turns_after_hitting_link(prg, 0x07), 'true')
        self.assertEqual(rom_import.turns_after_hitting_link(prg, 0x0D), 'false')
        self.assertEqual(rom_import.turns_after_hitting_link(prg, 0x12), 'false')   # Vire

    def test_bitplanes_have_correct_order(self):
        pattern = bytes([0b10000000] + [0] * 7 + [0b01000000] + [0] * 7)
        self.assertEqual(rom_import.chr_pixels(pattern, 0)[0], [1, 2, 0, 0, 0, 0, 0, 0])

    def test_tile_outside_memory_is_rejected(self):
        with self.assertRaises(ValueError):
            rom_import.chr_pixels(bytes(16), 1)

    def test_local_fire_frames_are_horizontal_flips(self):
        paths = [ROOT / 'imported' / ('fire_%d.png' % i) for i in range(2)]
        if not all(path.exists() for path in paths):
            self.skipTest('No local imported fire sprites')
        first, second = map(pixels, paths)
        self.assertEqual(second, [list(reversed(row)) for row in first])
        self.assertTrue(any(first[y][x][3] for y in range(16) for x in range(8)))
        self.assertTrue(any(first[y][x][3] for y in range(16) for x in range(8, 16)))

    def test_local_lifting_pose_matches_original_sprite_halves(self):
        roms = list((ROOT / 'reference-inputs').glob('*.nes')) + list(ROOT.glob('*.nes'))
        path = ROOT / 'imported/lift.png'
        if not roms or not path.exists():
            self.skipTest('No local ROM and imported lifting pose')
        prg = rom_import.read_rom(roms[0])
        actual = pixels(path)
        palette = prg[103168 + 19:103168 + 23]
        for y in range(16):
            for x in range(16):
                # Left: $78/$79 from persistent demo patterns. Right: $08/$09
                # from common patterns, retaining the original horizontal flip.
                if x < 8:
                    tile = 0x78 + y // 8
                    source = prg[19892:19892 + 2304]
                    tile -= 0x70
                    column = x
                else:
                    source = prg[32895:32895 + 1792]
                    tile = 0x08 + y // 8
                    column = 15 - x
                value = rom_import.chr_pixels(source, tile)[y % 8][column]
                expected = rom_import.COLORS[palette[value]] + bytes([255 if value else 0])
                self.assertEqual(actual[y][x], expected, (x, y))

    def test_local_enemy_and_reward_sprite_composition(self):
        roms = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not roms or not (ROOT / 'imported/heart_0.png').exists():
            self.skipTest('No local ROM and imported combat sprites')
        prg = rom_import.read_rom(roms[0])
        def rgba(tile, x, y, palette, background=False):
            offset = (36479 + (tile - 0xF2) * 16) if background else 53595 + (tile - 0x8E) * 16
            value = ((prg[offset + y] >> (7 - x)) & 1) | (((prg[offset + y + 8] >> (7 - x)) & 1) << 1)
            return rom_import.COLORS[palette[value]] + bytes([255 if value else 0])
        for family, palette_index in [('red_octorok', 6), ('blue_octorok', 5)]:
            palette = prg[103171 + palette_index * 4:103175 + palette_index * 4]
            for direction in ('left', 'right', 'up', 'down'):
                for pose in range(2):
                    actual = pixels(ROOT / 'imported' / f'{family}_{direction}_{pose}.png')
                    base = (0xB4 + pose * 4) if direction in ('left', 'right') else (0xB0 + pose * 2)
                    for y in range(16):
                        for x in range(16):
                            sx = 15 - x if direction == 'right' else x
                            column = sx // 8
                            tile = base + y // 8 + (column * 2 if direction in ('left', 'right') else 0)
                            tx = sx % 8
                            if direction in ('up', 'down') and column == 1: tx = 7 - tx
                            self.assertEqual(actual[y][x], rgba(tile, tx, y % 8, palette), (family, direction, pose, x, y))
        rock = pixels(ROOT / 'imported/rock.png')
        for y in range(16):
            for x in range(16):
                if x < 4 or x >= 12: self.assertEqual(rock[y][x][3], 0)
        for pose in range(2):
            heart = pixels(ROOT / 'imported' / f'heart_{pose}.png')
            palette = prg[103171 + (5 + pose) * 4:103175 + (5 + pose) * 4]
            for y in range(16):
                for x in range(4, 12):
                    self.assertEqual(heart[y][x], rgba(0xF2 + y // 8, x - 4, y % 8, palette, True))

    def test_local_beam_palettes_and_directional_flips(self):
        roms = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not roms or not (ROOT / 'imported/beam_up_0.png').exists():
            self.skipTest('No local beam sprites and ROM')
        prg = rom_import.read_rom(roms[0])
        for palette_index in range(4):
            images = {direction: pixels(ROOT / 'imported' / f'beam_{direction}_{palette_index}.png')
                      for direction in ('left', 'right', 'up', 'down')}
            self.assertEqual(images['left'], [list(reversed(row)) for row in images['right']])
            self.assertEqual(images['down'], list(reversed(images['up'])))
            palette = prg[103171 + (4 + palette_index) * 4:103175 + (4 + palette_index) * 4]
            for y in range(16):
                for x in range(4, 12):
                    offset = 32895 + (0x20 + y // 8) * 16
                    value = ((prg[offset + y % 8] >> (11 - x)) & 1) | (((prg[offset + y % 8 + 8] >> (11 - x)) & 1) << 1)
                    expected = rom_import.COLORS[palette[value]] + bytes([255 if value else 0])
                    self.assertEqual(images['up'][y][x], expected)
            corners = [pixels(ROOT / 'imported' / f'beam_burst_{corner}_{palette_index}.png') for corner in range(4)]
            self.assertEqual(corners[1], list(reversed(corners[0])))
            self.assertEqual(corners[2], [list(reversed(row)) for row in corners[1]])
            self.assertEqual(corners[3], [list(reversed(row)) for row in corners[0]])

    def test_hud_hearts_keep_fill_and_empty_palette_colors(self):
        roms = list((ROOT / 'reference-inputs').glob('*.nes'))
        path = ROOT / 'imported/hud_hearts.png'
        if not roms or not path.exists():
            self.skipTest('No local ROM and HUD hearts')
        prg = rom_import.read_rom(roms[0])
        actual = pixels(path)
        palette = prg[103175:103179]
        for frame, offset in enumerate((36479, 34687 + 0x65 * 16, 34687 + 0x66 * 16)):
            for y in range(8):
                for x in range(8):
                    value = ((prg[offset + y] >> (7 - x)) & 1) | (((prg[offset + y + 8] >> (7 - x)) & 1) << 1)
                    expected = rom_import.COLORS[palette[value]] + bytes([255 if value else 0])
                    self.assertEqual(actual[y][frame * 8 + x], expected)
        red = rom_import.COLORS[palette[1]] + bytes([255])
        filled = [sum(actual[y][frame * 8 + x] == red for y in range(8) for x in range(8)) for frame in range(3)]
        self.assertGreater(filled[0], filled[1])
        self.assertGreater(filled[1], filled[2])
        self.assertEqual(filled[2], 0)

    def test_supported_local_rom(self):
        candidates = list(ROOT.glob('*.nes')) + list((ROOT / 'reference-inputs').glob('*.nes'))
        if not candidates:
            self.skipTest('No local ROM supplied')
        prg = rom_import.read_rom(candidates[0])
        starting_room = rom_import.decode_room(prg, 0x77)
        self.assertEqual(len(starting_room), 11)
        self.assertTrue(all(len(row) == 16 for row in starting_room))
        self.assertEqual(starting_room[1][4], 0x0C)  # Visible cave entrance.
        self.assertEqual(starting_room[5], [0x0E] * 16)  # East-west corridor.
        self.assertEqual(starting_room[0][7:9], [0x0E, 0x0E])  # North opening.
        self.assertEqual(rom_import.square_tiles(prg, 0x0E), [0x26] * 4)
        for room_id in range(128):
            rom_import.decode_room(prg, room_id)


if __name__ == '__main__':
    unittest.main()
