from pathlib import Path
import sys
import unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import import_rom as rom
import import_dungeons as d
from render_audio import CUES, Driver

class BossAudioImportTests(unittest.TestCase):
    def test_source_requests(self):
        expected={'player_hurt':(0x601,8),'sword_beam':(0x601,1),'boss_hit':(0x601,2),
                  'roar_aquamentus':(0x601,0x10),'roar_dodongo':(0x601,0x20),'roar_manhandla':(0x601,0x40),
                  'ambient_boss_roar_aquamentus':(0x601,0x10),'ambient_boss_roar_dodongo':(0x601,0x20),'ambient_boss_roar_manhandla':(0x601,0x40),
                  'ambient_roar_aquamentus':(0x601,0x90),'ambient_roar_dodongo':(0x601,0xA0),'ambient_roar_manhandla':(0x601,0xC0),
                  'end_level':(0x600,4),'ganon_song':(0x600,2),'death':(0x602,0x80)}
        for cue,request in expected.items():self.assertEqual(CUES[cue][:2],request,cue)
    def local(self):
        inputs=list((ROOT/'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT/'imported/audio/boss_hit.wav').exists():self.skipTest('No local boss audio import')
        return rom.read_rom(inputs[0])
    def test_room_ambience_both_quests(self):
        original=self.local()
        for quest in (1,2):
            prg=bytearray(original)
            if quest==2:d.apply_second_quest_levels(original,prg)
            folder=ROOT/('imported/rooms' if quest==1 else 'imported/q2/rooms')
            for level in range(1,10):
                block,info=d.level_block(prg,level),d.level_info(prg,level)
                _,rooms,_=d.level_rooms(prg,level)
                for room in rooms:
                    index=(block[512+room]>>5)&3
                    text=(folder/f'l{level}_{room:02x}.tres').read_text()
                    if index:
                        cue=['','ambient_roar_aquamentus','ambient_roar_dodongo','ambient_roar_manhandla'][index]
                        self.assertIn(f'ambient_sample = &"{cue}"',text)
                        self.assertIn(f'ambient_boss_room = &"l{level}_{info[0x3E]:02x}"',text)
                    else:self.assertNotIn('ambient_sample = ',text)
    def test_songs_record_to_completion(self):
        prg=self.local()
        for cue,state in [('end_level',0x609),('ganon_song',0x609),('death',0x607)]:
            address,request,seconds=CUES[cue]
            cpu=Driver(prg)
            cpu.m[address]=request
            for frame in range(round(seconds*60)):
                cpu.m[0x15]=frame&255
                cpu.run()
                if cpu.m[state]==0:break
            else:self.fail(cue+' recording ends before source driver finishes')
