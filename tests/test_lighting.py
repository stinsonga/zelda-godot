from pathlib import Path
import re
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_dungeons as d
from test_import_rom import pixels

class LightingImportTests(unittest.TestCase):
    def local(self):
        files=list((ROOT/'reference-inputs').glob('*.nes'))
        if not files or not (ROOT/'imported/levels/level_1_dark_3.png').exists():self.skipTest('No local dark palette import')
        return rom.read_rom(files[0])
    def test_room_dark_flags(self):
        prg=self.local()
        for level in range(1,10):
            block=d.level_block(prg,level)
            _,rooms,_=d.level_rooms(prg,level)
            for room in rooms:
                text=(ROOT/'imported/rooms'/f'l{level}_{room:02x}.tres').read_text()
                self.assertIn(f'dark_room = {str(bool(block[512+room]&128)).lower()}',text)
                self.assertIn('dark_tile_atlases = Array[Texture2D]',text)
    def test_source_palette_pixels(self):
        prg=self.local()
        patterns=bytearray(8192)
        for source,length,target in [(34687,1792,0x1000),(36479,224,0x1f20),(49435,0x820,0x1700)]:patterns[target:target+length]=prg[source:source+length]
        for level in (4,9):
            info=d.level_info(prg,level)
            _,rooms,_=d.level_rooms(prg,level)
            room=next(r for r in rooms if d.level_block(prg,level)[512+r]&128)
            tiles,attrs=d.Layouts(prg,level).room(room)
            text=(ROOT/'imported/rooms'/f'l{level}_{room:02x}.tres').read_text()
            indices=[int(v.strip()) for v in re.search(r'tile_indices = PackedInt32Array\(([^)]*)\)',text)[1].split(',')]
            for stage in range(1,4):
                actual=pixels(ROOT/'imported/levels'/f'level_{level}_dark_{stage}.png')
                palettes=[list(info[3+4*i:7+4*i]) for i in range(4)]
                cycle=info[0xbc+stage*8:0xc4+stage*8]
                palettes[2],palettes[3]=cycle[:4],cycle[4:]
                for cy in range(11):
                    for cx in range(16):
                        index=indices[cy*16+cx]
                        palette=palettes[d.palette_at(attrs,cx*2,cy*2)]
                        for y in range(16):
                            for x in range(16):
                                tile=d.tile_at(tiles,cx*2+x//8,cy*2+y//8)
                                value=rom.chr_pixels(patterns[0x1000:],tile)[y%8][x%8]
                                self.assertEqual(actual[index//16*16+y][index%16*16+x],rom.COLORS[palette[value]]+bytes([255]),(level,stage,cx,cy,x,y))
