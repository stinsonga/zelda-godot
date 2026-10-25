from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_dungeons as dungeons
import import_rom as rom
from nes_cpu import Cpu


def program(code, bank_code=b''):
    """A 128 KiB image: code at $8000 of bank 0, bank_code in bank 1, fixed bank 7 code at $C000."""
    prg = bytearray(131072)
    prg[0:len(code)] = code
    prg[0x4000:0x4000 + len(bank_code)] = bank_code
    return prg


class CpuTests(unittest.TestCase):
    def test_arithmetic_flags(self):
        # LDA #$7F; CLC; ADC #$01; STA $00; PHP; PLA; STA $01; LDA #$00; SEC; SBC #$01; STA $02; RTS
        cpu = Cpu(program(bytes([0xA9, 0x7F, 0x18, 0x69, 0x01, 0x85, 0x00, 0x08, 0x68, 0x85, 0x01,
                                 0xA9, 0x00, 0x38, 0xE9, 0x01, 0x85, 0x02, 0x60])))
        cpu.call(0x8000)
        self.assertEqual(cpu.ram[0], 0x80)
        self.assertTrue(cpu.ram[1] & 0x40, 'overflow set on signed carry')
        self.assertEqual(cpu.ram[2], 0xFF)
        self.assertEqual(cpu.c, 0, 'borrow clears carry')

    def test_mmc1_bank_switch_and_subroutines(self):
        # Five serial writes of 1 to $E000 select bank 1, then JSR $8000 in that bank.
        code = bytes([0xA9, 0x01, 0x8D, 0x00, 0xE0, 0x4A, 0x8D, 0x00, 0xE0, 0x8D, 0x00, 0xE0,
                      0x8D, 0x00, 0xE0, 0x8D, 0x00, 0xE0, 0x20, 0x00, 0x80, 0x60])
        cpu = Cpu(program(b'', bytes([0xA9, 0x42, 0x85, 0x10, 0x60])), bank=7)
        cpu.prg = bytearray(cpu.prg)
        cpu.prg[-0x4000:-0x4000 + len(code)] = code
        cpu.call(0xC000)
        self.assertEqual(cpu.bank, 1)
        self.assertEqual(cpu.ram[0x10], 0x42)

    def test_indirect_jump_page_wrap(self):
        cpu = Cpu(program(bytes([0x6C, 0xFF, 0x02])))
        cpu.ram[0x2FF], cpu.ram[0x200] = 0x34, 0x12
        cpu.pc = 0x8000
        cpu.step()
        self.assertEqual(cpu.pc, 0x1234)

    def test_unsupported_opcode_fails(self):
        cpu = Cpu(program(bytes([0x02])))
        with self.assertRaises(RuntimeError):
            cpu.call(0x8000)


class DungeonImportTests(unittest.TestCase):
    def test_palette_quadrants(self):
        attrs = bytes([0b11100100] + [0] * 47)
        self.assertEqual([dungeons.palette_at(attrs, x, y) for x, y in ((0, 0), (2, 0), (0, 2), (2, 2))], [0, 1, 2, 3])

    def local(self):
        inputs = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not inputs: self.skipTest('No local ROM')
        return rom.read_rom(inputs[0])

    def test_local_level_structure(self):
        prg = self.local()
        starts = {level: dungeons.level_rooms(prg, level)[0] for level in range(1, 10)}
        self.assertEqual(starts, {1: 0x73, 2: 0x7D, 3: 0x7C, 4: 0x71, 5: 0x76, 6: 0x79, 7: 0x79, 8: 0x7E, 9: 0x76})
        start, rooms, cellars = dungeons.level_rooms(prg, 1)
        self.assertEqual((len(rooms), cellars), (17, [0x7F]))
        self.assertEqual(len(dungeons.level_rooms(prg, 9)[2]), 8)
        block = dungeons.level_block(prg, 1)
        self.assertEqual([dungeons.door_kind(block, 0x73, d) for d in ('up', 'down', 'left', 'right')], ['key', 'open', 'open', 'open'])

    def test_local_layout_matches_original_frame(self):
        prg = self.local()
        tiles, attrs = dungeons.Layouts(prg, 1).room(0x73)
        self.assertEqual(dungeons.tile_at(tiles, 0, 0), 0xF6)  # FillTileMap brick margin.
        self.assertEqual(dungeons.tile_at(tiles, 1, 1), 0xE0)  # WallTileList corner.
        self.assertEqual([dungeons.tile_at(tiles, x, 19) for x in (15, 16)], [0x24, 0x24])  # Open south doorway.
        opened, _ = dungeons.Layouts(prg, 1).room(0x73, 0x0F)
        self.assertNotEqual([dungeons.tile_at(tiles, x, 2) for x in range(14, 18)], [dungeons.tile_at(opened, x, 2) for x in range(14, 18)])
        cellar, _ = dungeons.Layouts(prg, 1).cellar(0x7F)
        self.assertEqual([dungeons.tile_at(cellar, 6, 0), dungeons.tile_at(cellar, 6, 2)], [0x24, 0x6F])  # Ladder top and rungs.

    def test_local_items(self):
        prg = self.local()
        info = dungeons.level_info(prg, 1)
        block = dungeons.level_block(prg, 1)
        self.assertEqual(dungeons.ITEMS[block[512 + 0x36] & 0x1F], 'triforce')
        self.assertEqual(dungeons.ITEMS[block[512 + 0x7F] & 0x1F], 'bow')
        self.assertEqual(dungeons.item_position(info, block[640 + 0x7F])[0] % 16, 0)


if __name__ == '__main__':
    unittest.main()
