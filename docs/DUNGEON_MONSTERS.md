# Dungeon monsters

The first dungeon families are in: Stalfos, Goriyas (blue and red), Gels, Zols,
Keese (blue, red, and black), and Ropes. 59 of the 216 first-quest dungeon rooms
that hold monsters contain only these families. They now spawn, fight, and drop loot. All 59 cellars hold
their four blue Keese. Rooms with other monsters stay empty until those families
exist, rather than substituting a different monster. The manifest records the counts.

## Behaviors

| Family | Source | Behavior |
| --- | --- | --- |
| Stalfos | `UpdateStalfos` | Walker: turn rate $80, half a pixel a frame; never shoots in the first quest. Its image flips every eight frames. |
| Goriya | `UpdateGoriya` | Walker aiming along the longer axis within $51. Throws a boomerang that flies 2.5 pixels a frame for $51 pixels and returns. The Goriya stands still until it comes back, then waits up to $3F frames. Blue Goriyas throw when ready; red ones only on random byte $23 or $77. |
| Gel / Zol | `UpdateNormalZolOrGel` | Walk only while the timer is below 5, and pause at each square for a `ZolGelDelays` delay: Gel 8-56 frames at one pixel a frame, Zol 24-72 at 0.375. |
| Zol split | `Zol_CheckCollisions` | A hit that does not kill turns the Zol into two Gels. They dart perpendicular to it for up to five frames, then snap to the grid. The room needs one more kill and the Zol drops nothing. |
| Keese | `UpdateKeese`, `InitBlueKeese` | Flyer with max speed $C0. Starts at speed $1F (blue) or $7F (red and black) in one of eight random directions. Chases at random >= $A0 and can be hit while flying. |
| Rope | `UpdateRope` | Wanders at half a pixel a frame, turning to a random open direction every 0-63 frames. At a square within 8 pixels of Link's row or column, it rushes at 1.5 pixels a frame. |

Health and contact damage come from the original tables; HP 0 means any hit
kills. Loot uses the original groups. Spawning reuses the overworld spawn lists
(`AssignObjSpawnPositions`). Dungeon rooms use `ObjectRoomBoundsUW` for monster bounds
and shots: X $21-$D0, Y $5E-$BD. Killing every monster opens shutters,
allows push blocks, and releases "defeat the enemies" items.

Sprites are rendered per level, from that level's sprite pattern block
(levels 1/2/7, 3/5/8, 4/6/9) and palettes. They are named `lN_<sprite>` and used
automatically in that level. The editable definitions are in `imported/enemies`;
copy one into `content/` to make variants, as with overworld enemies.

## Verification

- `tests/dungeon_monsters.gd`: ROM stats, Stalfos speed, Gel pauses, Keese
  flight bounds, Rope rushes, Goriya boomerang throw, wait, and return, Zol
  splitting, spawning inside dungeon bounds, shutters opening on kills, kill-gated
  keys, and cellar Keese.
- `tests/test_dungeons.py`: monster lists and stats from the ROM.
- `tests/visual_preview.gd -- monsters1` or `monsters2` shows every family in a level 1 or 2 room.

## Not yet

Wallmasters, Darknuts, Gibdos, Like Likes, Pols Voices, Vires, Bubbles,
Wizzrobes, Lanmolas, Moldorms, Digdoggers, Patras, traps, and all bosses. Second-quest
Stalfos shooting, monster stun from the boomerang and clock, and keys carried by
monsters are also not implemented.
