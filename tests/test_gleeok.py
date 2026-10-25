from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels

class GleeokImportTests(unittest.TestCase):
    def local(self):
        files=list((ROOT/'reference-inputs').glob('*.nes'))
        if not files or not (ROOT/'imported/l4_gleeok_body_0.png').exists():self.skipTest('No local Gleeok import')
        return rom.read_rom(files[0])
    def test_variants(self):
        self.local()
        for count in range(1,5):
            text=(ROOT/'imported/enemies'/f'gleeok_{count}.tres').read_text()
            self.assertIn(f'gleeok_neck_count = {count}',text)
            self.assertIn('gleeok_head = ExtResource("head")',text)
        text=(ROOT/'imported/enemies/gleeok_head.tres').read_text()
        self.assertIn('health = 10',text)
        self.assertIn('counts_for_persistence = false',text)
        self.assertIn('projectile_magic_blockable = false',text)
    def test_original_body_necks_and_head_pixels(self):
        prg=self.local()
        for level in (4,6,8):
            patterns=bytearray(8192)
            for source,length,target in [(32895,1792,0),(19892,2304,0x700),(dungeon.UW_COMMON_SPRITES,0x100,0x8e0),
                                         (dungeon.LEVEL_SPRITES[level],0x220,0x9e0),(dungeon.BOSS_SPRITES[level],0x400,0xc00)]:
                patterns[target:target+length]=prg[source:source+length]
            info=dungeon.level_info(prg,level)
            palette=info[3+7*4:7+7*4]
            def color(tile,x,y):
                value=rom.chr_pixels(patterns,tile)[y][x]
                return rom.COLORS[palette[value]]+bytes([255 if value else 0])
            for frame in range(4):
                actual=pixels(ROOT/'imported'/f'l{level}_gleeok_body_{frame}.png')
                offset=prg[0x1281b+frame]
                for y in range(32):
                    for x in range(24):
                        tile=prg[0x12809+offset+(y//16)*3+x//8]
                        self.assertEqual(actual[y][x],color((tile&254)+(y%16)//8,x%8,y%8),(level,frame,x,y))
            for name,tile in [('neck',0xda),('head',0xdc)]:
                actual=pixels(ROOT/'imported'/f'l{level}_gleeok_{name}.png')
                for y in range(16):
                    for x in range(16):
                        if x>=8:self.assertEqual(actual[y][x][3],0)
                        else:self.assertEqual(actual[y][x],color(tile+y//8,x,y%8))
