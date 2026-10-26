#!/usr/bin/env python3
"""Render verified-ROM audio with its original 6502 driver and a small APU model.

No music notes, envelopes, or sound scripts are distributed in this tool.
The CPU subset intentionally fails on unsupported instructions. APU output is
an approximation (frame-level register timing, approximate DMC timing and no full analog filter model).
"""
import array
import json
import math
from pathlib import Path
import struct
import wave

RATE = 22050
FPS = 60
CLOCK = 1789773

class Driver:
    def __init__(self, prg):
        self.m = bytearray(65536)
        self.m[0x8000:0xc000] = prg[:0x4000]
        self.m[0xc000:] = prg[-0x4000:]
        signature = bytes.fromhex('a5e0f00ca9008d1540a90f8d1540')
        at = prg[:0x4000].find(signature)
        if at < 0:
            # Branch displacement may vary, but the supported revision is fixed.
            signature = bytes.fromhex('a5e0')
            candidates = [i for i in range(0x1800, 0x1900) if prg[i:i+2] == signature]
            if len(candidates) != 1: raise ValueError('Audio driver signature missing')
            at = candidates[0]
        self.entry = 0x8000 + at
        self.a = self.x = self.y = self.c = self.z = self.n = 0
        self.m[0x4015] = 15
        self.writes = set()
        self.events = []

    def flags(self, value):
        value &= 255
        self.z, self.n = int(value == 0), value >> 7
        return value

    def run(self):
        self.pc = self.entry
        stack = []
        self.writes.clear()
        self.events.clear()
        for _ in range(20000):
            op = self.m[self.pc]; self.pc += 1
            if op == 0x60:
                if not stack: return
                self.pc = stack.pop(); continue
            if op in (0x20, 0x4c):
                dest = self.m[self.pc] | self.m[self.pc+1] << 8
                if op == 0x20: stack.append(self.pc + 2)
                self.pc = dest; continue
            branches = {0x90: not self.c, 0xb0: self.c, 0xf0: self.z, 0xd0: not self.z, 0x30: self.n, 0x10: not self.n}
            if op in branches:
                offset = self.m[self.pc]; self.pc += 1
                if branches[op]: self.pc += offset if offset < 128 else offset - 256
                continue
            if op in (0x18, 0x38): self.c = int(op == 0x38); continue
            if op in (0xaa, 0xa8, 0x8a, 0x98, 0xc8, 0xe8, 0xca, 0x88):
                if op == 0xaa: self.x = self.flags(self.a)
                elif op == 0xa8: self.y = self.flags(self.a)
                elif op == 0x8a: self.a = self.flags(self.x)
                elif op == 0x98: self.a = self.flags(self.y)
                elif op == 0xc8: self.y = self.flags(self.y+1)
                elif op == 0xe8: self.x = self.flags(self.x+1)
                elif op == 0xca: self.x = self.flags(self.x-1)
                else: self.y = self.flags(self.y-1)
                continue
            # 6502 group-one addressing (ORA/AND/EOR/ADC/STA/LDA/CMP/SBC).
            if op & 3 == 1:
                group, mode = op >> 5, (op >> 2) & 7
                addr = self.address(mode)
                v = self.m[addr]
                if group == 0: self.a = self.flags(self.a | v)
                elif group == 1: self.a = self.flags(self.a & v)
                elif group == 2: self.a = self.flags(self.a ^ v)
                elif group in (3, 7):
                    total = self.a + (v if group == 3 else v ^ 255) + self.c
                    self.c = int(total > 255); self.a = self.flags(total)
                elif group == 4: self.store(addr, self.a)
                elif group == 5: self.a = self.flags(v)
                elif group == 6: self.c = int(self.a >= v); self.flags(self.a-v)
                continue
            modes = {0xa0:2,0xa4:1,0xac:3,0xb4:5,0xbc:7,0xa2:2,0xa6:1,0xae:3,0xb6:5,0xbe:7,
                     0x84:1,0x8c:3,0x94:5,0x86:1,0x8e:3,0x96:5,0xc0:2,0xc4:1,0xcc:3,0xe0:2,0xe4:1,0xec:3}
            if op in modes:
                addr = self.address(modes[op], self.y if op in (0xb6,0xbe,0x96) else self.x)
                v = self.m[addr]
                if op in (0xa0,0xa4,0xac,0xb4,0xbc): self.y = self.flags(v)
                elif op in (0xa2,0xa6,0xae,0xb6,0xbe): self.x = self.flags(v)
                elif op in (0x84,0x8c,0x94): self.store(addr,self.y)
                elif op in (0x86,0x8e,0x96): self.store(addr,self.x)
                else:
                    r = self.y if op < 0xe0 else self.x
                    self.c = int(r >= v); self.flags(r-v)
                continue
            if op & 3 == 2:
                group, mode = op >> 5, (op >> 2) & 7
                addr = None if mode == 2 else self.address({1:1,3:3,5:5,7:7}[mode])
                v = self.a if addr is None else self.m[addr]
                old_c = self.c
                if group == 0: self.c = v >> 7; v <<= 1
                elif group == 1: self.c = v >> 7; v = v*2 + old_c
                elif group == 2: self.c = v & 1; v >>= 1
                elif group == 3: self.c = v & 1; v = (v >> 1) | old_c << 7
                elif group == 6: v -= 1
                elif group == 7: v += 1
                else: raise ValueError(f'Unsupported group {op:02x}')
                v = self.flags(v)
                if addr is None: self.a = v
                else: self.store(addr,v)
                continue
            raise ValueError(f'Unsupported audio opcode {op:02x} at {self.pc-1:04x}')
        raise ValueError('Audio driver exceeded instruction budget')

    def address(self, mode, index=None):
        v = self.m[self.pc]; self.pc += 1
        if mode == 2: return self.pc-1
        if mode in (3,6,7):
            v |= self.m[self.pc] << 8; self.pc += 1
        if mode == 0:
            v = (v+self.x)&255
            return self.m[v] | self.m[(v+1)&255] << 8
        if mode == 4:
            v = self.m[v] | self.m[(v+1)&255] << 8
        if mode in (4,6): v += self.y
        if mode in (5,7): v += self.x if index is None else index
        return v & (255 if mode == 5 else 65535)

    def store(self, addr, value):
        self.m[addr] = value
        self.writes.add(addr)
        self.events.append((addr,value))

class Dmc:
    """Delta decoder. Frame-level register writes; no DMA stalls or IRQ handling.

    NTSC periods and register semantics follow the NES DMC hardware (see
    Mesen2 Core/NES/APU/DeltaModulationChannel). Sample bytes stay in the ROM.
    """
    PERIODS = (428,380,340,320,286,254,226,214,190,160,142,128,106,85,72,54)

    def __init__(self):
        self.control = self.start = self.size = self.output = 0
        self.address = self.remaining = self.bits = self.shift = 0
        self.phase = self.dc = 0.0

    def write(self, address, value):
        if address == 0x4010: self.control = value
        elif address == 0x4011: self.output = value & 127
        elif address == 0x4012: self.start = 0xC000 + value * 64
        elif address == 0x4013: self.size = value * 16 + 1
        elif address == 0x4015:
            if not value & 16: self.remaining = 0
            elif self.remaining == 0: self.address, self.remaining = self.start, self.size

    def clock(self, memory):
        if self.bits == 0:
            if self.remaining == 0: return
            self.shift = memory[self.address]
            self.address = 0x8000 if self.address == 0xFFFF else self.address + 1
            self.remaining -= 1
            self.bits = 8
            if self.remaining == 0 and self.control & 64:
                self.address, self.remaining = self.start, self.size
        if self.shift & 1:
            if self.output <= 125: self.output += 2
        elif self.output >= 2: self.output -= 2
        self.shift >>= 1
        self.bits -= 1

    def sample(self, memory):
        self.phase += CLOCK / RATE
        period = self.PERIODS[self.control & 15]
        while self.phase >= period:
            self.phase -= period
            self.clock(memory)
        # Remove the DAC's held DC level so completed samples do not leave a
        # constant offset. This is a simple high-pass, not the full NES mixer.
        signal = self.output / 127.0
        self.dc += 0.002 * (signal - self.dc)
        return (signal - self.dc) * 0.35

class Apu:
    def __init__(self):
        self.phase = [0.,0.,0.]
        self.env = [0.,0.,0.]
        self.length = [0,0,0,0]
        self.dmc = Dmc()
        self.noise = 1
        self.noise_phase = 0.

    def frame(self, driver, count):
        m, writes = driver.m, driver.writes
        lengths = (10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30)
        bases = (0x4000,0x4004,0x4008,0x400c)
        for address,value in driver.events:
            self.dmc.write(address,value)
            if address == 0x4015:
                for ch in range(4):
                    if not value & (1 << ch): self.length[ch] = 0
            for ch,base in enumerate(bases):
                if address == base+3:
                    self.length[ch] = lengths[value >> 3]
                    if ch != 2: self.env[ch if ch < 2 else 2] = 15.
        for ch,base in enumerate(bases):
            if not (m[base] & 32 if ch != 2 else m[base]&128): self.length[ch] = max(0,self.length[ch]-2)
        periods = [m[b+2] | (m[b+3]&7)<<8 for b in (0x4000,0x4004,0x4008)]
        rates = [CLOCK/(16*(v+1)*RATE) for v in periods[:2]] + [CLOCK/(32*(periods[2]+1)*RATE)]
        duties = (.125,.25,.5,.75)
        noise_periods = (4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068)
        volumes = []
        for i,base in enumerate((0x4000,0x4004,0x400c)):
            control = m[base]
            vol = (control&15) if control&16 else self.env[i]
            volumes.append(vol/15)
            self.env[i] -= 4/(1+(control&15))
            if self.env[i] < 0: self.env[i] = 15. if control&32 else 0.
        out = array.array('h')
        for _ in range(count):
            value = self.dmc.sample(m)
            for ch,base in enumerate((0x4000,0x4004)):
                self.phase[ch] = (self.phase[ch]+rates[ch])%1
                if self.length[ch] and periods[ch] >= 8 and m[0x4015] & (1<<ch):
                    value += (1 if self.phase[ch] < duties[m[base]>>6] else -1)*volumes[ch]*.14
            self.phase[2] = (self.phase[2]+rates[2])%1
            if self.length[2] and m[0x4008]&127 and periods[2] > 1 and m[0x4015]&4:
                value += (4*abs(self.phase[2]-.5)-1)*.14
            self.noise_phase += CLOCK/(noise_periods[m[0x400e]&15]*RATE)
            while self.noise_phase >= 1:
                tap = 6 if m[0x400e]&128 else 1
                self.noise = (self.noise>>1) | (((self.noise ^ (self.noise>>tap))&1)<<14)
                self.noise_phase -= 1
            if self.length[3] and m[0x4015]&8: value += (1 if self.noise&1 else -1)*volumes[2]*.10
            out.append(round(max(-1,min(1,value))*32767))
        return out

CUES = {
    'overworld': (0x600,1,100), 'cave': (0x600,0x40,50),
    'item_fanfare': (0x600,8,4), 'attack': (0x603,1,0.4),
    'player_hurt': (0x604,2,0.7), 'enemy_hit': (0x604,2,0.7),
    'parry': (0x604,1,0.3), 'heart': (0x604,16,0.25),
    'rupee': (0x602,1,0.4), 'item': (0x602,8,1),
    'secret': (0x602,4,3), 'enemy_die': (0x602,0x20,1.5),
    # Z_01 textbox characters, money and secrets, WieldBomb, UpdateBomb, WieldCandle.
    'text': (0x604,0x10,0.25), 'key': (0x604,8,0.6), 'bomb_drop': (0x604,0x20,0.3),
    'bomb_blow': (0x603,0x10,0.8), 'flame': (0x603,4,0.6),
    # Z_07 LevelSongIds: levels 1-8 share $40; level 9 plays $20.
    'dungeon': (0x600,0x40,50), 'level_9': (0x600,0x20,50),
    # Z_05 WieldArrow/WieldBoomerang effect $02; Z_07 WieldFlute tune $10.
    'magic': (0x603,4,0.6), 'arrow': (0x603,2,0.4), 'recorder': (0x602,0x10,2.6),
    # Z_02 InitDemoSubphasePlayTitleSong: one demo cycle, after which the demo requests it again.
    'door': (0x601,4,0.5), 'menu_select': (0x602,1,0.4),
    'low_health': (0x604,0x40,1),
    'title': (0x600,0x80,81),
    # Z_04 UpdateZelda's fanfare ($06); Z_02 UpdateMode13WinGame_Sub0_Flash's ending song ($10).
    'zelda': (0x600,0x06,6), 'ending': (0x600,0x10,70),
}
# Songs that loop: the phrase index (driver byte $6C) where the loop begins.
LOOP_PHRASES = {'overworld': 10, 'cave': 16, 'ending': 21}

def export_audio(prg, destination):
    destination = Path(destination); destination.mkdir(parents=True, exist_ok=True)
    manifest = {'format':1,'sample_rate':RATE,'cues':{}}
    for name,(address,request,seconds) in CUES.items():
        driver, apu = Driver(prg), Apu()
        driver.m[address] = request
        samples = array.array('h'); loop_start = loop_end = 0
        previous_phrase = -1
        repeat_ticks = 0
        for frame in range(round(seconds*FPS)):
            driver.m[0x15] = frame & 255
            driver.run()
            if name == "low_health" and not repeat_ticks and driver.m[0x605] == 0: repeat_ticks = frame + 1
            phrase = driver.m[0x6c]
            if name in LOOP_PHRASES and phrase == LOOP_PHRASES[name] and phrase != previous_phrase:
                if loop_start:
                    loop_end = len(samples); break
                loop_start = len(samples)
            previous_phrase = phrase
            count = (frame+1)*RATE//FPS - frame*RATE//FPS
            samples.extend(apu.frame(driver,count))
        if name in LOOP_PHRASES and not loop_end:
            raise ValueError(f'Could not locate source phrase loop for {name}')
        if not loop_end:
            last = next((i for i in range(len(samples)-1,-1,-1) if samples[i]),0)
            samples = samples[:min(len(samples),last+1+RATE//100)]
        with wave.open(str(destination/f'{name}.wav'),'wb') as output:
            output.setparams((1,2,RATE,0,'NONE','not compressed')); output.writeframes(samples.tobytes())
        manifest['cues'][name] = {'file':f'{name}.wav','loop_begin':loop_start,'loop_end':loop_end,'frames':len(samples)}
        if repeat_ticks: manifest['cues'][name]['repeat_ticks'] = repeat_ticks
        print(f'Audio: {name} ({len(samples)/RATE:.2f}s)')
    (destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    return manifest

if __name__ == '__main__':
    import argparse
    from import_rom import read_rom
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rom',type=Path); parser.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'imported/audio')
    args = parser.parse_args()
    export_audio(read_rom(args.rom),args.output)
