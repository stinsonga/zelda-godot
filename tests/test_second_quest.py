from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import import_dungeons as dungeon


class SecondQuestImportTests(unittest.TestCase):
    def test_variants_are_known_monsters(self):
        names = {name for name, _ in dungeon.MONSTERS.values()}
        self.assertTrue(set(dungeon.SECOND_QUEST_VARIANTS) <= names)
        # InitRope: $40 HP is four of the importer's sixteen-point health units.
        self.assertEqual(dungeon.SECOND_QUEST_VARIANTS['rope']['health'], 0x40 // 0x10)

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
