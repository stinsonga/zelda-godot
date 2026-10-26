from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_caves as cave
import render_audio as audio
from test_import_rom import pixels

class RodImportTests(unittest.TestCase):
    def local(self):
        inputs=list((ROOT/'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT/'imported/magic_wave_up_0.png').exists():self.skipTest('No local rod import')
        return rom.read_rom(inputs[0])
    def test_directional_pixels(self):
        prg=self.local()
        patterns=bytearray(8192)
        for source,length,target in [(32895,1792,0),(34687,1792,0x1000),(36479,224,0x1F20),(19892,2304,0x700),(51515,2080,0x1700),(53595,1824,0x8E0)]:patterns[target:target+length]=prg[source:source+length]
        palettes=[list(prg[103171+p*4:103175+p*4]) for p in range(8)]
        for kind,slot in [('rod',8),('magic_wave',0x23)]:
            for direction in ['up','down','left','right']:
                tile=prg[cave.ITEM_FRAME_TILES+prg[cave.ITEM_FRAME_OFFSETS+slot]+int(direction in ['left','right'])]
                for palette in ([1] if kind=='rod' else range(4)):
                    expected=cave.render_item(prg,patterns,palettes,tile,palette,rom.blit_tile)
                    actual=pixels(ROOT/'imported'/(f'rod_{direction}.png' if kind=='rod' else f'magic_wave_{direction}_{palette}.png'))
                    for y in range(16):
                        for x in range(16):
                            sx=15-x if direction=='left' else x
                            sy=15-y if direction=='down' else y
                            offset=(sy*16+sx)*4
                            self.assertEqual(actual[y][x],expected[offset:offset+4],(kind,direction,palette,x,y))
    def test_magic_audio_request(self):
        self.assertEqual(audio.CUES['magic'],audio.CUES['flame'])
        self.assertEqual(audio.CUES['magic'][:2],(0x603,4))
