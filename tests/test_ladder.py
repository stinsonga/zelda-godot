from pathlib import Path
import re
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_dungeons as dungeon

def water_mask(text):
    return [int(v.strip()) for v in re.search(r'ladder_water = PackedByteArray\(([^)]*)\)', text)[1].split(',')]

class LadderImportTests(unittest.TestCase):
    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files or not (ROOT / 'imported/deployed_ladder.png').exists():
            self.skipTest('No local ladder import')
        return rom.read_rom(files[0])

    def test_overworld_permissions_and_water(self):
        prg = self.local()
        # Source LadderRoomsOW and GetCollidingTileMoving's $8D..$98 range.
        for room, layout in enumerate(rom.decode_room(prg, room) for room in range(128)):
            text = (ROOT / 'imported/rooms' / f'ow_{room:02x}.tres').read_text()
            self.assertIn('ladder_allowed = ' + str(room in (0x17,0x18,0x19,0x27,0x4F,0x5F)).lower(), text)
            expected = [0] * 704
            for y, row in enumerate(layout):
                for x, square in enumerate(row):
                    for part, tile in enumerate(rom.square_tiles(prg, square)):
                        expected[(y*2+part%2)*32+x*2+part//2] = int(0x8D <= tile < 0x99)
            self.assertEqual(water_mask(text), expected, room)

    def test_dungeon_water(self):
        prg = self.local()
        for level in range(1,10):
            layouts = dungeon.Layouts(prg, level)
            _, rooms, _ = dungeon.level_rooms(prg, level)
            for room in rooms:
                tiles, _ = layouts.room(room)
                # Only interior F4 water qualifies; door variants never touch water.
                text = (ROOT / 'imported/rooms' / f'l{level}_{room:02x}.tres').read_text()
                expected = [int(dungeon.tile_at(tiles,x,y) == 0xF4) for y in range(22) for x in range(32)]
                self.assertEqual(water_mask(text), expected, (level,room))
