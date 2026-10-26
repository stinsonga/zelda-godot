import array
import importlib.util
import json
from pathlib import Path
import sys
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from render_audio import Driver, Apu, Dmc, CUES

class AudioTests(unittest.TestCase):
    def cpu(self, code):
        cpu = Driver.__new__(Driver)
        cpu.m = bytearray(65536)
        cpu.entry = 0x8000
        cpu.m[0x8000:0x8000+len(code)] = bytes(code)
        cpu.a = cpu.x = cpu.y = cpu.c = cpu.z = cpu.n = 0
        cpu.writes = set()
        cpu.events = []
        return cpu

    def test_indirect_indexed_and_absolute_indexed(self):
        cpu = self.cpu([0xa0,3,0xb1,0x10,0x99,0,0x40,0x60])
        cpu.m[0x10:0x12] = bytes([0,0x90])
        cpu.m[0x9003] = 0x8f
        cpu.run()
        self.assertEqual(cpu.m[0x4003],0x8f)
        self.assertEqual(cpu.n,1)

    def test_subroutine_carry_and_wrapping(self):
        cpu = self.cpu([0xa9,255,0x18,0x69,1,0x20,0x0a,0x80,0x60,0,0x6a,0x60])
        cpu.run()
        self.assertEqual(cpu.a,128)
        self.assertEqual(cpu.c,0)

    def test_unsupported_instruction_fails(self):
        with self.assertRaises(ValueError): self.cpu([0]).run()

    def test_apu_disable_clears_length_even_when_reenabled(self):
        cpu = self.cpu([0x60])
        cpu.events = [(0x400b, 9), (0x4015, 0), (0x4015, 15)]
        cpu.m[0x4008] = 255
        cpu.m[0x400a] = 64
        cpu.m[0x4015] = 15
        apu = Apu()
        self.assertFalse(any(apu.frame(cpu,368)))
        self.assertEqual(apu.length[2],0)

    def test_dmc_bit_order_and_saturation(self):
        memory=bytearray(65536)
        memory[0xC000]=0b00001111
        dmc=Dmc()
        dmc.write(0x4011,64)
        dmc.write(0x4012,0)
        dmc.write(0x4013,0)
        dmc.write(0x4015,16)
        levels=[]
        for _ in range(8):
            dmc.clock(memory)
            levels.append(dmc.output)
        self.assertEqual(levels,[66,68,70,72,70,68,66,64])
        self.assertEqual((dmc.remaining,dmc.bits),(0,0))
        memory[0xC000]=255
        dmc.output=127
        dmc.write(0x4015,16)
        for _ in range(8):dmc.clock(memory)
        self.assertEqual(dmc.output,127)
        dmc.output=0
        memory[0xC000]=0
        dmc.write(0x4015,16)
        for _ in range(8):dmc.clock(memory)
        self.assertEqual(dmc.output,0)

    def test_dmc_address_wrap_loop_and_disable(self):
        memory=bytearray(65536)
        dmc=Dmc()
        dmc.address=0xFFFF
        dmc.remaining=2
        dmc.clock(memory)
        self.assertEqual(dmc.address,0x8000)
        for _ in range(8):dmc.clock(memory)
        self.assertEqual(dmc.address,0x8001)
        dmc=Dmc()
        dmc.write(0x4010,64)
        dmc.write(0x4012,1)
        dmc.write(0x4013,0)
        dmc.write(0x4015,16)
        dmc.clock(memory)
        self.assertEqual((dmc.address,dmc.remaining),(0xC040,1))
        dmc.write(0x4015,0)
        self.assertEqual(dmc.remaining,0)
        dmc.write(0x4011,255)
        self.assertEqual(dmc.output,127)

    def test_missing_cue_requests(self):
        self.assertEqual(CUES['door'][:2],(0x601,4))
        self.assertEqual(CUES['menu_select'][:2],(0x602,1))
        self.assertEqual(CUES['low_health'][:2],(0x604,64))

    def test_local_rendered_cues(self):
        path = ROOT / 'imported/audio/manifest.json'
        if not path.exists(): self.skipTest('No local audio import')
        manifest = json.loads(path.read_text())
        self.assertEqual(set(manifest['cues']),set(CUES))
        for cue,data in manifest['cues'].items():
            with wave.open(str(path.parent/data['file'])) as stream:
                self.assertEqual((stream.getnchannels(),stream.getsampwidth(),stream.getframerate()),(1,2,22050))
                samples = array.array('h',stream.readframes(stream.getnframes()))
                self.assertEqual(len(samples),data['frames'])
                self.assertGreater(max(abs(v) for v in samples),1000,cue)
                if cue in ('overworld','cave'):
                    self.assertLess(0,data['loop_begin'])
                    self.assertEqual(data['loop_end'],len(samples))
                    self.assertGreater(data['loop_end']-data['loop_begin'],22050)
