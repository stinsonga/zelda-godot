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
2. **Overworld (done).** Quest-only secrets (`IsQuestSecretMismatch`), the patched room
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

## Overworld

The second quest shares the overworld's layouts and attribute block; the
importer applies `UpdateMode2Load_Full`'s patches to a copy of the ROM
(`import_rom.second_quest_prg`) and runs the same overworld import on it, into
`imported/q2/rooms/`. The patches are:
- the eight bytes of `LevelBlockAttrsBQ2Replacement*`: destinations, including
  level 6's old two-square entrance, which becomes a two-square cave mouth;
- seven immediates: new layouts (attribute D) for rooms $0B, $3C, and $74, and
  their palettes and exits.

Secrets follow `IsQuestSecretMismatch`: attribute F's top bits 1 and 2 keep a
secret to the first or second quest. Every recorder pond drains to stairs at
($60, $90) (`UpdateFluteSecret`). `FluteRoomSecretsOW`'s first room ($42, level
7) is a pond in the first quest only; the other ten rooms are ponds in the
second. Elsewhere the recorder summons the whirlwind, whose stops are the same
table in both quests.

The second quest's levels are reached by:
- level 1, as before ($37);
- level 2, a recorder pond ($3C);
- level 3, an Armos ($34);
- level 4, as before ($45);
- level 5, a pushed rock ($1B);
- level 6, a recorder pond ($30);
- level 7, a bombed wall ($19);
- level 8, a burned tree ($6C);
- level 9, a bombed wall ($00).

70 caves are reachable, against 63 in the first quest. The nine left out are the
first quest's own secrets.

Until step 3, these entrances lead into the first quest's levels, whose exits
still return to the first quest's entrance rooms.

`tests/second_quest.gd` checks the variant swap without a ROM. With an import, it
also checks the worlds, monster rules, file switching, the patched rooms and
quest secrets, and draining a pond. `tests/test_second_quest.py` checks the
variants, the patch bytes, and that each quest has one entrance per level.
`tests/visual_preview.gd -- q2_<room>` renders a second-quest room.
