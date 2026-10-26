# Second quest

The original keeps one set of rules and swaps data by the file's quest number
(`QuestNumbers`): `Z_06 InitMode2_Sub0` copies the second quest's level blocks,
`UpdateMode2Load_Full` patches the level info and some overworld rooms, and a few
routines check the quest directly. Here a quest is a `WorldDefinition`:
`imported/world.tres` (`original_quest_1`) and `imported/world_q2.tres`
(`original_quest_2`, `quest = 2`).

## Plan

1. **Foundation (done).** A world per quest, chosen by the file; quest-wide
   monster rules; the file menu's marker.
2. **Overworld.** Quest-only secrets (`IsQuestSecretMismatch`), the patched room
   attributes (`LevelBlockAttrsBQ2Replacement*` and the A/D/F patches), the
   recorder secrets (`FluteRoomSecretsOW`), and the second quest's dungeon
   entrances.
3. **Dungeon layouts.** `LevelBlockUW1Q2` and `LevelBlockUW2Q2` for levels 1-9,
   with `LevelInfoUWQ2Replacements1-9` (start rooms, maps, shortcut and item
   positions).
4. **Dungeon contents.** Monsters, items, doors, cellars, and old men, checked room
   by room.
5. **Verification.** Every level and item reachable; docs.

## Foundation

- **Choosing the world.** The front end loads the second quest's world for a
  second-quest file (a name starting ZELDA, or a file that has finished the game),
  and the first quest's otherwise. Without the import, every file plays the first
  quest. Saves are kept per world, so the two never mix.
- **Monster variants.** `WorldDefinition.enemy_variants` maps a monster ID to a
  replacement definition, applied when a room fills. The second quest uses:
  - `rope_q2` (`Z_04 InitRope`, `UpdateRope`): $40 HP instead of $10, and the
    sprite palette cycles with `FrameCounter & 3` (`sprite_palette_cycle`, drawn
    from the `_p0`-`_p3` sprites);
  - `stalfos_q2` (`UpdateStalfos`): throws sword shots ($57) on the walker's
    timer, starting when `Random >= $F8`.
- **File menu.** `Mode1_WriteLinkSprites` draws a sword $C right of and 3 above
  a second-quest Link. The white sword image stands in for menu palette 7.
- **Finishing the game.** `SwitchProfileToSecondQuest` clears items and world
  flags and leaves three full hearts; the file keeps its deaths and next plays
  the second quest from the start.

Until steps 2-4 land, the second quest's world has the first quest's places.

`tests/second_quest.gd` checks variants without a ROM, and the worlds, monster
rules, and file switching with an import. `tests/test_second_quest.py` checks
the importer's variants.
