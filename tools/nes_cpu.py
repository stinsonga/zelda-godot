"""A small, complete official-opcode 6502 core with MMC1 PRG banking.

The importer uses it to run the original layout routines against a verified
ROM, so generated rooms match the game's own tile maps. It has no PPU or APU:
writes to $2000-$401F are recorded and otherwise ignored.
"""

BANK_SIZE = 0x4000


class Cpu:
    def __init__(self, prg, bank=0):
        self.prg = prg
        self.ram = bytearray(0x800)
        self.sram = bytearray(0x2000)
        self.bank = bank
        self.shift = 0x10
        self.a = self.x = self.y = 0
        self.s = 0xFD
        self.c = self.z = self.i = self.d = self.v = self.n = 0
        self.pc = 0
        self.io_writes = []

    # Memory -----------------------------------------------------------------
    def read(self, address):
        address &= 0xFFFF
        if address < 0x2000: return self.ram[address & 0x7FF]
        if address < 0x6000: return 0
        if address < 0x8000: return self.sram[address - 0x6000]
        if address < 0xC000: return self.prg[self.bank * BANK_SIZE + address - 0x8000]
        return self.prg[len(self.prg) - BANK_SIZE + address - 0xC000]

    def write(self, address, value):
        address &= 0xFFFF
        value &= 0xFF
        if address < 0x2000: self.ram[address & 0x7FF] = value
        elif address < 0x6000: self.io_writes.append((address, value))
        elif address < 0x8000: self.sram[address - 0x6000] = value
        else: self.mmc1(address, value)

    def mmc1(self, address, value):
        if value & 0x80:
            self.shift = 0x10
            return
        done = self.shift & 1
        self.shift = (self.shift >> 1) | ((value & 1) << 4)
        if done:
            if address >= 0xE000: self.bank = self.shift & 0x0F
            self.shift = 0x10

    def word(self, address):
        return self.read(address) | self.read(address + 1) << 8

    def word_zero_page(self, address):
        return self.read(address & 0xFF) | self.read((address + 1) & 0xFF) << 8

    # Helpers ----------------------------------------------------------------
    def nz(self, value):
        value &= 0xFF
        self.z, self.n = int(value == 0), value >> 7
        return value

    def push(self, value):
        self.write(0x100 + self.s, value)
        self.s = (self.s - 1) & 0xFF

    def pull(self):
        self.s = (self.s + 1) & 0xFF
        return self.read(0x100 + self.s)

    def status(self, brk):
        return (self.c | self.z << 1 | self.i << 2 | self.d << 3 | brk << 4 | 1 << 5 | self.v << 6 | self.n << 7)

    def set_status(self, value):
        self.c, self.z, self.i, self.d = value & 1, value >> 1 & 1, value >> 2 & 1, value >> 3 & 1
        self.v, self.n = value >> 6 & 1, value >> 7 & 1

    def fetch(self):
        value = self.read(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return value

    def operand(self, mode):
        """Effective address for a mode; None for immediate (value returned)."""
        if mode == 'imm': return ('value', self.fetch())
        if mode == 'zp': return self.fetch()
        if mode == 'zpx': return (self.fetch() + self.x) & 0xFF
        if mode == 'zpy': return (self.fetch() + self.y) & 0xFF
        if mode == 'abs':
            low = self.fetch()
            return low | self.fetch() << 8
        if mode == 'abx':
            low = self.fetch()
            return ((low | self.fetch() << 8) + self.x) & 0xFFFF
        if mode == 'aby':
            low = self.fetch()
            return ((low | self.fetch() << 8) + self.y) & 0xFFFF
        if mode == 'izx': return self.word_zero_page(self.fetch() + self.x)
        if mode == 'izy': return (self.word_zero_page(self.fetch()) + self.y) & 0xFFFF
        raise ValueError(mode)

    def load(self, mode):
        address = self.operand(mode)
        return address[1] if isinstance(address, tuple) else self.read(address)

    def adc(self, value):
        total = self.a + value + self.c
        self.v = int(((self.a ^ total) & (value ^ total) & 0x80) != 0)
        self.c = int(total > 0xFF)
        self.a = self.nz(total)

    def compare(self, register, value):
        self.c = int(register >= value)
        self.nz(register - value)

    # Execution ----------------------------------------------------------------
    def call(self, address, limit=2_000_000):
        """Run a subroutine until its final RTS returns to a sentinel."""
        sentinel = 0xFFFF
        self.push((sentinel - 1) >> 8)
        self.push((sentinel - 1) & 0xFF)
        self.pc = address
        for _ in range(limit):
            if self.pc == sentinel: return
            self.step()
        raise RuntimeError(f'Routine at ${address:04X} did not return')

    def step(self):
        op = self.fetch()
        group = OPCODES.get(op)
        if group is None: raise RuntimeError(f'Unsupported opcode ${op:02X} at ${(self.pc - 1) & 0xFFFF:04X}')
        name, mode = group
        getattr(self, 'op_' + name)(mode)

    def branch(self, condition):
        offset = self.fetch()
        if condition: self.pc = (self.pc + (offset - 256 if offset & 0x80 else offset)) & 0xFFFF

    def op_bpl(self, _): self.branch(not self.n)
    def op_bmi(self, _): self.branch(self.n)
    def op_bvc(self, _): self.branch(not self.v)
    def op_bvs(self, _): self.branch(self.v)
    def op_bcc(self, _): self.branch(not self.c)
    def op_bcs(self, _): self.branch(self.c)
    def op_bne(self, _): self.branch(not self.z)
    def op_beq(self, _): self.branch(self.z)

    def op_lda(self, mode): self.a = self.nz(self.load(mode))
    def op_ldx(self, mode): self.x = self.nz(self.load(mode))
    def op_ldy(self, mode): self.y = self.nz(self.load(mode))
    def op_sta(self, mode): self.write(self.operand(mode), self.a)
    def op_stx(self, mode): self.write(self.operand(mode), self.x)
    def op_sty(self, mode): self.write(self.operand(mode), self.y)
    def op_tax(self, _): self.x = self.nz(self.a)
    def op_tay(self, _): self.y = self.nz(self.a)
    def op_txa(self, _): self.a = self.nz(self.x)
    def op_tya(self, _): self.a = self.nz(self.y)
    def op_tsx(self, _): self.x = self.nz(self.s)
    def op_txs(self, _): self.s = self.x
    def op_pha(self, _): self.push(self.a)
    def op_php(self, _): self.push(self.status(1))
    def op_pla(self, _): self.a = self.nz(self.pull())
    def op_plp(self, _): self.set_status(self.pull())
    def op_and(self, mode): self.a = self.nz(self.a & self.load(mode))
    def op_ora(self, mode): self.a = self.nz(self.a | self.load(mode))
    def op_eor(self, mode): self.a = self.nz(self.a ^ self.load(mode))
    def op_adc(self, mode): self.adc(self.load(mode))
    def op_sbc(self, mode): self.adc(self.load(mode) ^ 0xFF)
    def op_cmp(self, mode): self.compare(self.a, self.load(mode))
    def op_cpx(self, mode): self.compare(self.x, self.load(mode))
    def op_cpy(self, mode): self.compare(self.y, self.load(mode))
    def op_inx(self, _): self.x = self.nz(self.x + 1)
    def op_iny(self, _): self.y = self.nz(self.y + 1)
    def op_dex(self, _): self.x = self.nz(self.x - 1)
    def op_dey(self, _): self.y = self.nz(self.y - 1)
    def op_clc(self, _): self.c = 0
    def op_sec(self, _): self.c = 1
    def op_cli(self, _): self.i = 0
    def op_sei(self, _): self.i = 1
    def op_cld(self, _): self.d = 0
    def op_sed(self, _): self.d = 1
    def op_clv(self, _): self.v = 0
    def op_nop(self, _): pass

    def op_bit(self, mode):
        value = self.load(mode)
        self.z = int(self.a & value == 0)
        self.v, self.n = value >> 6 & 1, value >> 7

    def modify(self, mode, function):
        if mode == 'acc':
            self.a = self.nz(function(self.a))
            return
        address = self.operand(mode)
        self.write(address, self.nz(function(self.read(address))))

    def op_inc(self, mode): self.modify(mode, lambda v: v + 1)
    def op_dec(self, mode): self.modify(mode, lambda v: v - 1)

    def op_asl(self, mode):
        def shift(v):
            self.c = v >> 7
            return (v << 1) & 0xFF
        self.modify(mode, shift)

    def op_lsr(self, mode):
        def shift(v):
            self.c = v & 1
            return v >> 1
        self.modify(mode, shift)

    def op_rol(self, mode):
        def shift(v):
            carry = self.c
            self.c = v >> 7
            return ((v << 1) | carry) & 0xFF
        self.modify(mode, shift)

    def op_ror(self, mode):
        def shift(v):
            carry = self.c
            self.c = v & 1
            return (v >> 1) | carry << 7
        self.modify(mode, shift)

    def op_jmp(self, mode):
        address = self.operand('abs')
        if mode == 'ind':
            # The original 6502 page-wrap quirk on indirect JMP.
            address = self.read(address) | self.read((address & 0xFF00) | ((address + 1) & 0xFF)) << 8
        self.pc = address

    def op_jsr(self, _):
        address = self.operand('abs')
        target = (self.pc - 1) & 0xFFFF
        self.push(target >> 8)
        self.push(target & 0xFF)
        self.pc = address

    def op_rts(self, _):
        low = self.pull()
        self.pc = ((self.pull() << 8 | low) + 1) & 0xFFFF

    def op_rti(self, _):
        self.set_status(self.pull())
        low = self.pull()
        self.pc = self.pull() << 8 | low

    def op_brk(self, _):
        raise RuntimeError(f'BRK at ${(self.pc - 1) & 0xFFFF:04X}')


OPCODES = {}
def _table(name, pairs):
    for op, mode in pairs: OPCODES[op] = (name, mode)

_table('lda', [(0xA9, 'imm'), (0xA5, 'zp'), (0xB5, 'zpx'), (0xAD, 'abs'), (0xBD, 'abx'), (0xB9, 'aby'), (0xA1, 'izx'), (0xB1, 'izy')])
_table('ldx', [(0xA2, 'imm'), (0xA6, 'zp'), (0xB6, 'zpy'), (0xAE, 'abs'), (0xBE, 'aby')])
_table('ldy', [(0xA0, 'imm'), (0xA4, 'zp'), (0xB4, 'zpx'), (0xAC, 'abs'), (0xBC, 'abx')])
_table('sta', [(0x85, 'zp'), (0x95, 'zpx'), (0x8D, 'abs'), (0x9D, 'abx'), (0x99, 'aby'), (0x81, 'izx'), (0x91, 'izy')])
_table('stx', [(0x86, 'zp'), (0x96, 'zpy'), (0x8E, 'abs')])
_table('sty', [(0x84, 'zp'), (0x94, 'zpx'), (0x8C, 'abs')])
for _name, _base in [('ora', 0x00), ('and', 0x20), ('eor', 0x40), ('adc', 0x60), ('cmp', 0xC0), ('sbc', 0xE0)]:
    _table(_name, [(_base + 0x09, 'imm'), (_base + 0x05, 'zp'), (_base + 0x15, 'zpx'), (_base + 0x0D, 'abs'),
                   (_base + 0x1D, 'abx'), (_base + 0x19, 'aby'), (_base + 0x01, 'izx'), (_base + 0x11, 'izy')])
_table('cpx', [(0xE0, 'imm'), (0xE4, 'zp'), (0xEC, 'abs')])
_table('cpy', [(0xC0, 'imm'), (0xC4, 'zp'), (0xCC, 'abs')])
_table('bit', [(0x24, 'zp'), (0x2C, 'abs')])
for _name, _base in [('asl', 0x00), ('rol', 0x20), ('lsr', 0x40), ('ror', 0x60)]:
    _table(_name, [(_base + 0x0A, 'acc'), (_base + 0x06, 'zp'), (_base + 0x16, 'zpx'), (_base + 0x0E, 'abs'), (_base + 0x1E, 'abx')])
_table('inc', [(0xE6, 'zp'), (0xF6, 'zpx'), (0xEE, 'abs'), (0xFE, 'abx')])
_table('dec', [(0xC6, 'zp'), (0xD6, 'zpx'), (0xCE, 'abs'), (0xDE, 'abx')])
for _op, _name in [(0x10, 'bpl'), (0x30, 'bmi'), (0x50, 'bvc'), (0x70, 'bvs'), (0x90, 'bcc'), (0xB0, 'bcs'), (0xD0, 'bne'), (0xF0, 'beq'),
                   (0xAA, 'tax'), (0xA8, 'tay'), (0x8A, 'txa'), (0x98, 'tya'), (0xBA, 'tsx'), (0x9A, 'txs'), (0x48, 'pha'), (0x08, 'php'),
                   (0x68, 'pla'), (0x28, 'plp'), (0xE8, 'inx'), (0xC8, 'iny'), (0xCA, 'dex'), (0x88, 'dey'), (0x18, 'clc'), (0x38, 'sec'),
                   (0x58, 'cli'), (0x78, 'sei'), (0xD8, 'cld'), (0xF8, 'sed'), (0xB8, 'clv'), (0xEA, 'nop'), (0x20, 'jsr'), (0x60, 'rts'),
                   (0x40, 'rti'), (0x00, 'brk')]:
    OPCODES[_op] = (_name, None)
OPCODES[0x4C] = ('jmp', 'abs')
OPCODES[0x6C] = ('jmp', 'ind')
