# Dungeon foundations

After a ROM import, all nine first-quest levels are connected and walkable. There
are 255 rooms, cellars included. Enter a level through its overworld entrance and leave through the
start room's south doorway. Level 7's entrance needs the recorder, which is not
implemented, but its rooms and exit are imported.

The first dungeon monster families are in; see [dungeon monsters](DUNGEON_MONSTERS.md).
Rooms whose monsters are not implemented yet are empty, so their shutters and
"defeat the enemies" items open or appear at once. Boss-room heart containers can
be taken immediately.

## Rooms from the original code

`tools/nes_cpu.py` is a complete official-opcode 6502 core with MMC1 PRG banking.
`tools/import_dungeons.py` loads the level block ($18700 for levels 1-6,
$18A00 for 7-9) and the level info ($19300 + $FC per level). It copies the common
code and data the game places in save RAM at reset. Then it runs the original
routines:

- `LayOutRoom`'s underworld branch ($A8CB): `FillTileMap` brick, `FillWalls`,
  `LayOutDoors`, and `LayoutUWFloor`;
- `FillPlayAreaAttrs` ($83D7) for palettes;
- `PatchColumnDirectoryForCellar` and `LayoutCellarAndAdvanceSubmode` for cellars,
  with `CellarAttrsTransferBuf`'s fixed palette.

Each room is laid out twice: with no doors open, and with all doors open. Every
16-pixel square becomes an entry in a per-level atlas (`imported/levels/level_N.png`).
Collision uses `ObjectRoomBoundsUW`: tiles from $78 up block. Level membership
is a flood fill from `LevelInfo_StartRoomId` through non-wall doors and cellar
stairs.

## Doors

`DoorDefinition` holds a direction, a kind (`FindDoorTypeByDoorBit`), and the
squares that change while it is passable: the open layout, plus the lane to the
room edge that `CheckDoorway` lets Link walk.

| Kind | Behavior |
| --- | --- |
| open | Always passable. |
| false | Looks like a wall; Link walks through. |
| key | Opens when Link presses into it (`DoorwayBoundsMinOver/MaxOver`) holding a key, or the magical key without spending it. |
| bombable | Opens when a detonating bomb is within $18 of its `BombableWallHotspots` point. |
| shutter | Closes behind Link and reopens when the room's trigger fires (`CheckSecretTrigger`): triggers 1, 2, 3, and 7 when the monsters are gone, 4 when the block is pushed, 6 when the money-or-life man leaves. Triggers 0 and 5 never open them; trigger 0 shutters are one-way. Seen from the next room, a shutter is open. |

Opening a key or bombable door sets `door/<room>/<direction>` for both sides.
Authored doors need only direction and kind: empty cell arrays use the standard
doorway geometry the importer derives (`DoorDefinition.STANDARD_CELLS`). See
[EXTENDING.md](EXTENDING.md).

## Rooms, items, and secrets

- Room items come from attribute E. Their position comes from attribute F
  through `LevelInfo_ShortcutOrItemPosArray`. Triggers 3 and 7 hide the item
  until the room is clear (`requires_clear`). Room items are taken without lifting;
  cellar treasure is lifted.
- Map, compass, and triforce are `level` items, stored as `map/N`, `compass/N`,
  and `triforce/N`. The HUD shows `LEVEL-N`. The map shows the level's rooms; the
  compass flashes the triforce room. Taking the triforce refills hearts. After the
  fanfare, Link returns to the level's entrance.
- Push blocks (attribute D bit 6) follow `UpdateBlock0Idle`: Link must be
  aligned and push away from himself for 16 ticks, with no monsters left. Trigger 4
  opens shutters; trigger 5 reveals stairs at ($D0, $60).
- Stairs squares lead to the cellar whose attribute A or B names the room. Link starts
  at ladder X $30 or $C0 and climbs down 28 pixels. Leaving above the screen
  uses attribute A left of $80, else B, and arrives at attribute C's position.

Entry walks stop exactly on their target, as mode 4 does.

## Carried room items

`MoveAndDrawRoomItem` puts an active room item on a Like Like, Stalfos, or Gibdo
in monster slot 1. It is not used for triggers 3 and 7, whose items wait for the
room to clear. The importer marks those pickups `carrier_slot = 1`. The item moves
with the monster, Link can take it by touching the monster, and it stays where the
monster died. Level 1's key Stalfos is the best-known case. A triforce piece sits 8
pixels left of its item position (`CreateRoomObjects`).

## Residents, statues, and rupee stashes

- Types $4B-$52 are residents (`InitUnderworldPerson`). Each imports as a
  `CaveDefinition` on the room (`imported/caves/uw_l<N>_<room>.tres`) with the old
  man at ($78, $80) and his two fires. His text comes from the level group's selector table:
  A for levels 1, 2, 5, and 7; B for 3, 4, 6, and 8; C for 9. He holds Link until
  the text ends, then blocks the way north (Y $8E) while present.
- In levels 1, 2, 5, and 7 the $4F man sells bomb capacity: Link stands on the
  rupee at ($78, $98) with 100 rupees. Capacity rises by four and fills, without
  lifting. The man flickers away and stays gone (`bomb_upgrade`, `lifts_wares = false`).
- The level 9 entrance man (`triforce_gate`) leaves on entry once Link holds the
  triforce of levels 1-8, and sets `shutters/<room>` to open his trigger-0 shutters.
- Striking a resident with the sword enables the fires' fireballs: statue pattern 2
  from ($48, $82) and ($A8, $86).
- Statue rooms (unique layout $24: four statues, $23: two) shoot `$55` fireballs
  (`UpdateStatues`). Each statue keeps a timer. When it runs out, random >= $F0 waits 256
  frames, otherwise a start time of $50, $80, $F0, or $60 is chosen. The shot is
  skipped when Link is within $18 on both axes or no object slot from 6 up is free.
  Rooms list them in `statues` and `provoked_statues`; each fireball starts 4
  pixels right of its statue.
- A rupee stash ($35) makes ten rupees at `RupeeStashXs`/`Ys`. Each is taken within 9
  pixels. Taking one sets the room's count to zero, so after leaving none return.
  Leaving without taking any keeps all ten.

## Verification

- `tests/dungeon_people.gd` covers shutter triggers, the gate man, the bomb offer,
  statues and provoked fires, and rupee stashes with built-in fixtures; with an
  import it checks the original rooms.
- `tests/dungeons.gd` covers level structure, entrance and exit, key, magical-key,
  and bombable doors, open doorways, the level 1 cellar and bow, map and triforce,
  the level exit, push-block shutters, and saving inside a level.
- `tests/test_dungeons.py` covers the 6502 core (flags, MMC1, indirect jump)
  and level starts, membership, door kinds, original frame tiles, cellar
  ladders, and items.
- `tests/visual_preview.gd -- dungeon`, `dungeon opened`, `cellar`, and `level9`
  render screenshots for review.

## Known gaps

- Dark rooms are not implemented. The money-or-life man ($51) appears only in the
  second quest and is not implemented. The hungry Goriya needs bait.
- Only the sword provokes a resident; the original's `CheckMonsterCollisions`
  also counts other weapons.
- False walls do not wait the original 24 frames. Doorway movement uses lanes
  instead of `Link_ModifyDirInDoorway`. Room-to-room walks scroll as outdoors.
- Cellar keese are not spawned. Link is drawn 2 pixels high in cellars.
- There is no door sound cue yet (`door` is played but unmapped).
