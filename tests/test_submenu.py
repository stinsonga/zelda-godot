from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon
import import_submenu as submenu
from test_import_rom import pixels


class SubmenuImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files or not (ROOT / 'imported/submenu.tres').exists(): self.skipTest('No local submenu import')
        return rom.read_rom(files[0])

    def test_transfer_buffers(self):
        prg = self.local()
        # Selector $30 is InventoryTextTransferBuf: NT2 $2984, nine characters.
        offset = submenu.buffer_at(prg, 0x30)
        self.assertEqual((prg[offset], prg[offset + 1], prg[offset + 2]), (0x29, 0x84, 9))
        tiles, attrs = bytearray([0x24] * 0x3C0), bytearray(64)
        submenu.apply_records(prg, offset, tiles, attrs)
        self.assertEqual(list(tiles[12 * 32 + 4:12 * 32 + 13]), list(prg[offset + 3:offset + 12]))

    def test_triforce_slots(self):
        prg = self.local()
        slots = submenu.triforce_slots(prg)
        self.assertEqual(len(slots), 24)
        # Every slot lies inside the Triforce rows (NT2 rows 23-26).
        for x, y, empty, full in slots:
            self.assertTrue(15 * 8 <= y <= 18 * 8 and 0 < x < 256, (x, y))
        # Levels 5 and 6 share a tile that one half fills.
        self.assertEqual(slots[12][:2], slots[15][:2])
        self.assertEqual(slots[12][3], 0xE5)

    def test_maps_and_images(self):
        prg = self.local()
        text = (ROOT / 'imported/submenu.tres').read_text()
        rotations = [dungeon.level_info(prg, level)[submenu.LEVEL_INFO_ROTATION] for level in range(1, 10)]
        self.assertIn('map_rotations = PackedByteArray(' + ', '.join(map(str, rotations)) + ')', text)
        image = pixels(ROOT / 'imported/submenu_l1.png')
        self.assertEqual((len(image[0]), len(image)), (256, 176))
        # The blank map sheet tile fills the map area in each level backdrop.
        info = dungeon.level_info(prg, 1)
        palette = list(info[3 + 4:7 + 4])
        patterns = bytearray(8192)
        for source, length, target in [(34687, 1792, 0x1000), (36479, 224, 0x1F20), (49435, 0x820, 0x1700)]:
            patterns[target:target + length] = prg[source:source + length]
        value = rom.chr_pixels(patterns[0x1000:], submenu.BLANK_MAP)[0][0]
        self.assertEqual(image[13 * 8][12 * 8], rom.COLORS[palette[value]] + bytes([255]))


if __name__ == '__main__':
    unittest.main()
