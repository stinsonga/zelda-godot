from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels

class ManhandlaImportTests(unittest.TestCase):
    def local(self):
        paths=list((ROOT/'reference-inputs').glob('*.nes'))
        if not paths or not (ROOT/'imported/l3_manhandla_body_0.png').exists(): self.skipTest('No local Manhandla import')
        return rom.read_rom(paths[0])

    def test_imported_hands_and_stats(self):
        prg=self.local()
        hand=(ROOT/'imported/enemies/manhandla_hand.tres').read_text()
        body=(ROOT/'imported/enemies/manhandla.tres').read_text()
        self.assertIn(f'health = {prg[0x1fb4e+0x3c//2]>>4}',hand)
        self.assertIn('counts_for_persistence = false',hand)
        self.assertIn('advances_kill_cycle = false',hand)
        self.assertIn('boss_hand = ExtResource("hand")',body)

    def test_all_part_frames_match_source(self):
        prg=self.local()
        level=3
        patterns=bytearray(8192)
        for source,length,target in [(32895,1792,0),(19892,2304,0x700),(dungeon.UW_COMMON_SPRITES,0x100,0x8e0),
                                     (dungeon.LEVEL_SPRITES[level],0x220,0x9e0),(dungeon.BOSS_SPRITES[level],0x400,0xc00)]:
            patterns[target:target+length]=prg[source:source+length]
        info=dungeon.level_info(prg,level)
        palette=info[3+5*4:7+5*4]
        base=prg[0x6e04+0x3d]
        for part,offset in [('up',0),('down',0),('left',2),('right',2),('body',4)]:
            for pose in range(2):
                actual=pixels(ROOT/'imported'/f'l3_manhandla_{part}_{pose}.png')
                tile=prg[0x6e83+base+offset+pose]
                for y in range(16):
                    sy=15-y if part=='down' else y
                    for x in range(16):
                        sx=15-x if part=='right' else x
                        mirrored=part not in ('left','right')
                        tx=15-sx if mirrored and sx>=8 else sx%8
                        index=(tile&254)+sy//8+(0 if mirrored else (sx//8)*2)
                        value=rom.chr_pixels(patterns,index)[sy%8][tx]
                        self.assertEqual(actual[y][x],rom.COLORS[palette[value]]+bytes([255 if value else 0]),(part,pose,x,y))
