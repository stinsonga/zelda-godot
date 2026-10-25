import array
import importlib.util
import json
from pathlib import Path
import sys
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from render_audio import Driver, Apu, CUES

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
