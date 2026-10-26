import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
from test_import_rom import pixels

class EnemyImportTests(unittest.TestCase):
    def test_authored_mixed_list_and_count(self):
        data = bytearray(131072)
        data[99328+256] = 0x22 | 0x40
        data[99328+384] = 0x80
        data[103168+37] = 3
        data[83775:83777] = (0x9000).to_bytes(2,'little')
        data[0x15000:0x15003] = bytes([3,7,26])
        self.assertEqual(rom.room_enemy_types(data,0),[3,7,26])
        ext,sub,field,count = rom.enemy_resources(data,0,[],(80,77))
        self.assertEqual(count,3)
        self.assertIn('blue_moblin.tres',ext)
        self.assertIn('red_octorok.tres',ext)
        self.assertIn('peahat.tres',ext)
        data[0x15001] = 0x4B  # An unsupported type here: do not substitute another monster.
        self.assertEqual(rom.enemy_resources(data,0,[],(80,77)),('','','',0))

    def local(self):
        inputs = list((ROOT/'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT/'imported/enemies/peahat.tres').exists(): self.skipTest('No local ROM enemy import')
        return rom.read_rom(inputs[0])

    def test_local_stats_and_mixed_encounters(self):
        data = self.local()
        for kind,(name,behavior) in rom.ENEMY_TYPES.items():
            text = (ROOT/'imported/enemies'/f'{name}.tres').read_text()
            pair = data[0x1fb4e+kind//2]
            self.assertIn(f'health = {pair&15 if kind&1 else pair>>4}\n',text)
            self.assertIn(f'behavior = "{behavior}"',text)
            raw = data[0x72ba+kind]
            # The boulder set is an invisible generator that never touches Link.
            expected = 0 if kind in (0x1F, 0x2F) else (raw&15)*2+bool(raw&240)
            self.assertIn(f'contact_damage = {expected}\n',text)
        supported = mixed = 0
        for i in range(128):
            types = rom.room_enemy_types(data,i)
            if not types or any(t not in rom.ENEMY_TYPES for t in types): continue
            text = (ROOT/'imported/rooms'/f'ow_{i:02x}.tres').read_text()
            self.assertEqual(text.count('id = &"slot_'),len(types))
            for slot,kind in enumerate(types):
                self.assertIn(f'enemy = ExtResource("enemy_def_{kind}")',text)
            supported += 1
            mixed += len(set(types))>1
        # 100 common encounters, six Ghini rooms, six boulder rooms, and two fairy ponds.
        self.assertEqual((supported,mixed),(114,32))

    def test_local_enemy_pose_pixels(self):
        data = self.local()
        # OW sprite pattern block, just as loaded by the NES; decode individual bits.
        def color(tile,x,y,palette):
            offset = 53595 + (tile-0x8e)*16
            bit = 7-x
            index = ((data[offset+y]>>bit)&1) | (((data[offset+y+8]>>bit)&1)<<1)
            return rom.COLORS[palette[index]]+bytes([255 if index else 0])
        for kind,(name,behavior) in rom.ENEMY_TYPES.items():
            if behavior == 'nes_octorok': continue
            base = data[0x6e04+kind+1]
            frames = []
            if kind in (0x1F, 0x2F): continue
            if kind == 0x20:
                frames = [(f'{name}_{i}',base+i,False,False) for i in range(2)]
            elif kind in (0x21, 0x22):
                # DrawGhiniAndCheckCollisions: back (0) and front (1), each also flipped.
                frames = [(f'{name}_{view}{suffix}',base+offset,False,suffix != '') for view,offset in (('back',0),('front',1)) for suffix in ('','_mirrored')]
            elif kind == 0x1E:
                # DrawArmosAndCheckCollisions: four unmirrored front/back frames.
                frames = [(f'{name}_{i}',base+i,False,False) for i in range(4)]
            elif behavior == 'walker':
                for direction in ('up','down','left','right'):
                    for pose in range(2):
                        frame = base + (3 if direction=='up' else 2 if direction=='down' else pose)
                        flip = pose==1 if direction in ('up','down') else direction=='left'
                        frames.append((f'{name}_{direction}_{pose}',frame,False,flip))
            else:
                frames = [(f'{name}_{i}',base+i,True,False) for i in range(10 if behavior in ('burrower','zora') else 2)]
            for key,frame,mirrored,flip in frames:
                image = pixels(ROOT/'imported'/f'{key}.png')
                tile,attr = data[0x6e83+frame],data[0x6f4f+frame]
                palette = data[103171+(4+(attr&3))*4:103175+(4+(attr&3))*4]
                for y in range(16):
                    sy = 15-y if attr&128 else y
                    for x in range(16):
                        sx = 15-x if flip else x
                        tx = 15-sx if mirrored and sx>=8 else sx%8
                        actual_tile = (tile&254)+sy//8+(0 if mirrored else (sx//8)*2)
                        self.assertEqual(image[y][x],color(actual_tile,tx,sy%8,palette),(key,x,y))
