from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_dungeons as dungeon
import import_rom as rom
import import_caves as caves


class SecondQuestImportTests(unittest.TestCase):
    def test_variants_are_known_monsters(self):
        names = {name for name, _ in dungeon.MONSTERS.values()}
        self.assertTrue(set(dungeon.SECOND_QUEST_VARIANTS) <= names)
        # InitRope: $40 HP is four of the importer's sixteen-point health units.
        self.assertEqual(dungeon.SECOND_QUEST_VARIANTS['rope']['health'], 0x40 // 0x10)

    def local(self):
        files = list((ROOT / 'reference-inputs').glob('*.nes'))
        if not files: self.skipTest('No local ROM')
        return rom.read_rom(files[0])

    def test_overworld_patches(self):
        prg = self.local()
        patched = rom.second_quest_prg(prg)
        changed = [i for i in range(99328, 99328 + 768) if prg[i] != patched[i]]
        # Fifteen patched bytes (eight from the table, seven immediates); two already hold their values.
        self.assertEqual(len(changed), 13)
        # Outside the overworld block, only the level blocks and level info change.
        self.assertEqual(prg[:0x18000], patched[:0x18000])
        self.assertEqual(prg[0x1A000:], patched[0x1A000:])

    def test_level_patches(self):
        prg = self.local()
        patched = rom.second_quest_prg(prg)
        for level in range(1, 10):
            # The second quest's blocks replace the first quest's, and level info from $29 changes.
            self.assertEqual(dungeon.level_block(patched, level), prg[0x18D00 if level <= 6 else 0x19000:][:768])
            self.assertEqual(dungeon.level_info(patched, level)[:0x29], dungeon.level_info(prg, level)[:0x29])
            self.assertNotEqual(dungeon.level_info(patched, level)[0x2F], None)
        # Level 1 starts in room $77 (LevelInfoUWQ2Replacements1 at offset 6).
        self.assertEqual(dungeon.level_info(patched, 1)[0x2F], 0x77)
        self.assertEqual(dungeon.level_info(prg, 1)[0x2F], 0x73)
        for level in range(1, 10):
            start, rooms, cellars = dungeon.level_rooms(patched, level)
            self.assertIn(start, rooms)

    def test_one_entrance_per_level(self):
        prg = self.local()
        for quest, data in ((1, prg), (2, rom.second_quest_prg(prg))):
            layouts = [rom.decode_room(data, i) for i in range(128)]
            entrances = caves.overworld_entrances(data, layouts, rom.square_tiles, quest)
            for level in range(1, 10):
                ways = [r for r, e in entrances.items() if e['destination'] == level
                        and (e['visible'] or e['secret'] or (r in rom.SECRET_ARMOS and quest == 2 and level == 3))]
                self.assertEqual(len(ways), 1, (quest, level, ways))

    def test_world(self):
        path = ROOT / 'imported/world_q2.tres'
        if not path.exists(): self.skipTest('No local import')
        text = path.read_text()
        self.assertIn('id = &"original_quest_2"', text)
        self.assertIn('quest = 2', text)
        for name in dungeon.SECOND_QUEST_VARIANTS:
            self.assertIn(f'&"{name}": ExtResource("{name}_q2")', text)
            self.assertTrue((ROOT / f'imported/enemies/{name}_q2.tres').exists())


if __name__ == '__main__':
    unittest.main()
