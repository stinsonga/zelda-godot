from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_dungeons as dungeon
from test_import_rom import pixels

class MoldormImportTests(unittest.TestCase):
    def local(self):
        files=list((ROOT/'reference-inputs').glob('*.nes'))
        if not files or not (ROOT/'imported/l2_moldorm.png').exists():self.skipTest('No local Moldorm import')
        return rom.read_rom(files[0])
    def test_stats_and_original_encounters(self):
        prg=self.local()
        text=(ROOT/'imported/enemies/moldorm_segment.tres').read_text()
        self.assertIn(f'health = {prg[0x1fb4e+0x41//2]&15}',text)
        raw=prg[0x72ba+0x41]
        self.assertIn(f'contact_damage = {(raw&15)*2+bool(raw&240)}',text)
        self.assertIn('counts_for_persistence = false',text)
        self.assertIn('spawn_cloud = false',text)
        self.assertEqual(dungeon.FIXED_POSITIONS[0x41],(0x80,0x70))
        for level in (2,7):
            found=0
            for path in (ROOT/'imported/rooms').glob(f'l{level}_*.tres'):
                text=path.read_text()
                if 'moldorm.tres' in text:
                    self.assertIn('persistence_enemy_count = 8',text)
                    found+=1
            self.assertGreater(found,0)
    def test_segment_pixels(self):
        prg=self.local()
        patterns=bytearray(8192)
        patterns[:1792]=prg[32895:32895+1792]
        for level in (2,7):
            info=dungeon.level_info(prg,level)
            palette=info[3+6*4:7+6*4]
            actual=pixels(ROOT/'imported'/f'l{level}_moldorm.png')
            for y in range(16):
                for x in range(16):
                    if x>=8:self.assertEqual(actual[y][x][3],0)
                    else:
                        value=rom.chr_pixels(patterns,0x44+y//8)[y%8][x]
                        self.assertEqual(actual[y][x],rom.COLORS[palette[value]]+bytes([255 if value else 0]),(level,x,y))
