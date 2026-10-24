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
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        if data[offset + 4:offset + 8] == b'IDAT':
            compressed += data[offset + 8:offset + 8 + size]
        offset += size + 12
    raw = zlib.decompress(compressed)
    return [[raw[y * 65 + 1 + x * 4:y * 65 + 5 + x * 4]
             for x in range(16)] for y in range(16)]


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
