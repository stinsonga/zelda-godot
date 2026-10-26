from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_caves as caves
from test_import_rom import pixels

class RaftImportTests(unittest.TestCase):
    def local(self):
        inputs=list((ROOT/'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT/'imported/deployed_raft.png').exists(): self.skipTest('No local raft import')
        return rom.read_rom(inputs[0])
    def test_dock_rooms(self):
        self.local()
        for room in range(128):
            text=(ROOT/'imported/rooms'/f'ow_{room:02x}.tres').read_text()
            if room in (0x3F,0x55):
                x=128 if room==0x55 else 96
                self.assertIn('raft_route = SubResource("dock_route")',text)
                for name,y in [('dock',61),('edge',-3),('landing',63)]:self.assertIn(f'{name}_position = Vector2i({x}, {y})',text)
            else:self.assertNotIn('raft_route = ',text)
        for room,target in [('2f','cave_2f'),('45','l4_71')]:
            text=(ROOT/'imported/rooms'/f'ow_{room}.tres').read_text()
            self.assertIn(f'target_room = &"{target}"',text)
    def test_raft_pixels(self):
        prg=self.local()
        patterns=bytearray(8192)
        for source,length,target in [(32895,1792,0),(34687,1792,0x1000),(36479,224,0x1F20),(19892,2304,0x700),(51515,2080,0x1700),(53595,1824,0x8E0)]:patterns[target:target+length]=prg[source:source+length]
        palettes=[list(prg[103171+p*4:103175+p*4]) for p in range(8)]
        tile=prg[caves.ITEM_FRAME_TILES+prg[caves.ITEM_FRAME_OFFSETS+9]]
        expected=caves.render_item(prg,patterns,palettes,tile,0,rom.blit_tile)
        actual=pixels(ROOT/'imported/deployed_raft.png')
        self.assertEqual(b''.join(pixel for row in actual for pixel in row),bytes(expected))
