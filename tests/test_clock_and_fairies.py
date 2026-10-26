from pathlib import Path
import re
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_rom as rom
import import_caves as caves
from test_import_rom import pixels

class ClockFairyImportTests(unittest.TestCase):
    def local(self):
        inputs = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT / 'imported/fairy_1.png').exists():
            self.skipTest('No local clock/fairy import')
        return rom.read_rom(inputs[0])

    def test_drop_rows(self):
        prg = self.local()
        text = (ROOT / 'imported/world.tres').read_text()
        supported = {0x22:'heart',0x18:'rupee',0x0F:'five_rupees',0:'bomb_drop',0x21:'clock',0x23:'fairy'}
        for group in range(4):
            row = text.split(f'[sub_resource type="Resource" id="loot_{group}"]')[1].split('[',1)[0]
            self.assertIn(f'chance = {prg[0x1303E+group]}', row)
            block = text.split(f'[sub_resource type="Resource" id="loot_{group}"]')[1].split('[sub_resource',1)[0].split('[resource]',1)[0]
            actual = re.findall(r'ExtResource\("([^" ]+)"\)', block)[1:]
            self.assertEqual(actual, [supported[v] for v in prg[0x13042+group*10:0x1304C+group*10]])
        # The source descriptor's low nibble is hearts-minus-one.
        self.assertEqual((prg[caves.ITEM_ID_TO_DESCRIPTOR+0x23] & 15)+1,3)

    def test_reward_sprite_pixels(self):
        prg = self.local()
        patterns = bytearray(8192)
        for source,length,target in [(32895,1792,0),(34687,1792,0x1000),(36479,224,0x1F20),(19892,2304,0x700),(51515,2080,0x1700),(53595,1824,0x8E0)]:
            patterns[target:target+length] = prg[source:source+length]
        palettes = [list(prg[103171+p*4:103175+p*4]) for p in range(8)]
        for name,item,frame in [('clock',0x21,0),('fairy_0',0x23,0),('fairy_1',0x23,1)]:
            tile, attr = caves.item_tile(prg,item,frame)
            expected = caves.render_item(prg,patterns,palettes,tile,2 if item==0x23 else attr,rom.blit_tile)
            actual = pixels(ROOT/'imported'/f'{name}.png')
            self.assertEqual(b''.join(pixel for row in actual for pixel in row), bytes(expected), name)

    def test_clock_player_palettes(self):
        prg = self.local()
        # Palette variants preserve each pixel's pattern index and transparency.
        base = pixels(ROOT/'imported/player.png')
        original = [rom.COLORS[v] for v in prg[103187:103191]]
        for palette in range(1,4):
            actual = pixels(ROOT/'imported'/f'clock_player_{palette}.png')
            colors = [rom.COLORS[v] for v in prg[103187+palette*4:103191+palette*4]]
            for y,row in enumerate(base):
                for x,pixel in enumerate(row):
                    if pixel[3] == 0:
                        self.assertEqual(actual[y][x][3],0)
                    else:
                        index = original.index(pixel[:3])
                        self.assertEqual(actual[y][x],colors[index]+bytes([255]),(palette,x,y))
