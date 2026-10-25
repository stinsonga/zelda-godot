from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_caves as caves
import import_rom as rom


class CaveImportTests(unittest.TestCase):
    def test_authored_cave_flags(self):
        data = bytearray(131072)
        # One person text at $804C: "HI" terminated by the $C0 high bits.
        data[caves.PERSON_TEXT_ADDRS:caves.PERSON_TEXT_ADDRS + 2] = (0x804C).to_bytes(2, 'little')
        data[0x404C:0x404E] = bytes([0x11, 0x12 | 0xC0])
        # Cave $77: pay + choose selector; ware flags show items and prices.
        data[caves.TEXT_SELECTORS + 13] = 0xC0
        base = caves.OW_ATTRS + 512 + 13 * 3
        data[base:base + 3] = bytes([0x1C, 0x00, 0x08 | 0xC0])
        data[base + 60:base + 63] = bytes([130, 20, 80])
        for index in range(20):
            if index != 13: data[caves.OW_ATTRS + 512 + index * 3:caves.OW_ATTRS + 515 + index * 3] = bytes([0x3F] * 3)
        shop = caves.cave_types(data)[13]
        self.assertEqual(shop['text'], 'HI')
        self.assertTrue(shop['pay'] and shop['choose'] and shop['show_items'] and shop['show_prices'])
        self.assertFalse(shop['remember'] or shop['hint'] or shop['money_game'] or shop['negative_prices'])
        self.assertEqual([w['item'] for w in shop['wares']], ['magic_shield', 'bombs', 'arrows'])
        self.assertEqual([w['price'] for w in shop['wares']], [130, 20, 80])
        data[base] = 0x21  # The clock has no native definition: refuse rather than guess.
        with self.assertRaises(ValueError):
            caves.cave_types(data)

    def test_untimed_space_text(self):
        data = bytearray(131072)
        data[caves.PERSON_TEXT_ADDRS:caves.PERSON_TEXT_ADDRS + 2] = (0x804C).to_bytes(2, 'little')
        data[0x404C:0x4050] = bytes([0x25, 0x0A | 0x80, 0x24, 0x0B | 0xC0])
        self.assertEqual(caves.person_text(data, 0), '_A\n B')

    def local(self):
        inputs = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not inputs or not (ROOT / 'imported/caves').exists(): self.skipTest('No local ROM cave import')
        return rom.read_rom(inputs[0])

    def test_local_cave_types(self):
        prg = self.local()
        table = {cave['type']: cave for cave in caves.cave_types(prg)}
        self.assertEqual(table[0x6A]['wares'][1]['item'], 'wooden_sword')
        self.assertTrue(table[0x6A]['remember'] and table[0x6A]['text'].strip('_ ').startswith("IT'S DANGEROUS TO GO"))
        self.assertEqual((table[0x6C]['heart_requirement'], table[0x6D]['heart_requirement']), (5, 12))
        self.assertTrue(table[0x70]['money_game'] and table[0x70]['negative_prices'])
        self.assertEqual(table[0x71]['door_charge'], 20)
        self.assertTrue(table[0x74]['requires_letter'] and table[0x74]['pay'])
        self.assertEqual([w['price'] for w in table[0x76]['wares']], [10, 30, 50])
        self.assertIn('FOREST', table[0x76]['wares'][1]['hint'])
        self.assertIn("YOU'RE RICH", table[0x76]['wares'][2]['hint'])
        self.assertTrue(all(table[t]['gift_money'] and table[t]['remember'] for t in (0x7B, 0x7C, 0x7D)))
        self.assertEqual([table[t]['wares'][1]['price'] for t in (0x7B, 0x7C, 0x7D)], [30, 100, 10])

    def test_local_entrances_and_secrets(self):
        prg = self.local()
        layouts = [rom.decode_room(prg, i) for i in range(128)]
        rooms = caves.overworld_entrances(prg, layouts, rom.square_tiles)
        self.assertEqual(rooms[0x77]['visible'], [{'cell': (4, 1), 'mouth': True}])
        self.assertEqual(rooms[0x77]['exit'], (64, 13))
        self.assertEqual(rooms[0x0D]['secret'], {'kind': 'wall', 'cell': (9, 1), 'square': rooms[0x0D]['secret']['square'], 'reveal': (9, 1), 'persistent': True})
        self.assertEqual(rooms[0x28]['secret']['kind'], 'tree')
        # Gravestone stairs appear on the gravestone square and are not remembered.
        self.assertEqual((rooms[0x21]['secret']['reveal'], rooms[0x21]['secret']['persistent']), ((9, 5), False))
        # Rock rings remember their stairs, revealed at the ring's center.
        self.assertEqual((rooms[0x23]['secret']['reveal'], rooms[0x23]['secret']['persistent']), ((4, 5), True))
        # Second-quest secrets stay ordinary terrain in the first quest.
        self.assertIsNone(rooms[0x00]['secret'])
        self.assertEqual(list(prg[103168 + 52:103168 + 56]), [0x1D, 0x23, 0x49, 0x79])

    def test_local_text_stays_out_of_shared_content(self):
        """docs/ASSET_BOUNDARY.md: original dialogue may only live in imported/."""
        prg = self.local()
        lines = set()
        for selector in range(0, 0x4C, 2):
            for line in caves.person_text(prg, selector).replace('_', ' ').split('\n'):
                if len(line.strip()) >= 8: lines.add(line.strip())
        for folder in ('content', 'scenes'):
            for path in (ROOT / folder).rglob('*'):
                if path.suffix not in ('.tres', '.tscn', '.gd'): continue
                text = path.read_text(errors='ignore').replace('\\n', ' ')
                for line in lines:
                    self.assertNotIn(line, text, f'{path} contains original text')

    def test_local_item_sprites(self):
        self.local()
        for name in ['bombs', 'blue_candle', 'heart_container', 'magic_shield', 'letter', 'old_woman', 'merchant', 'cave_moblin', 'bomb_cloud_1', 'white_sword_up']:
            self.assertTrue((ROOT / 'imported' / f'{name}.png').exists(), name)


if __name__ == '__main__':
    unittest.main()
