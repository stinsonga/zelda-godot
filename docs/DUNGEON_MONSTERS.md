# Dungeon monsters

Implemented families: Stalfos, Goriyas, Gels, Zols, Keese, Ropes, Darknuts,
Gibdos, Bubbles, Like Likes, Vires, Pols Voices, Wallmasters, blade traps, and
blue and red Wizzrobes, and the bosses Aquamentus, Dodongo, Gohma, and Digdogger. 172 of the 216 first-quest dungeon rooms that hold monsters now contain only implemented
families, and every cellar holds its four blue Keese. Rooms with other monsters
(the other bosses, Lanmolas, Moldorms, Patras, and the old men) stay empty until those exist,
rather than substituting a different monster. The manifest records the counts.

## Behaviors

| Family | Source | Behavior |
| --- | --- | --- |
| Stalfos | `UpdateStalfos` | Walker: turn rate $80, half a pixel a frame; never shoots in the first quest. Its image flips every eight frames. |
| Goriya | `UpdateGoriya` | Walker aiming along the longer axis within $51. Throws a boomerang that flies 2.5 pixels a frame for $51 pixels and returns. The Goriya stands still until it comes back, then waits up to $3F frames. Blue Goriyas throw when ready; red ones only on random byte $23 or $77. |
| Gel / Zol | `UpdateNormalZolOrGel` | Walk only while the timer is below 5, and pause at each square for a `ZolGelDelays` delay: Gel 8-56 frames at one pixel a frame, Zol 24-72 at 0.375. |
| Zol split | `Zol_CheckCollisions` | A hit that does not kill turns the Zol into two Gels. They dart perpendicular to it for up to five frames, then snap to the grid. The room needs one more kill and the Zol drops nothing. |
| Keese | `UpdateKeese`, `InitBlueKeese` | Flyer with max speed $C0. Starts at speed $1F (blue) or $7F (red and black) in one of eight random directions. Chases at random >= $A0 and can be hit while flying. |
| Rope | `UpdateRope` | Wanders at half a pixel a frame, turning to a random open direction every 0-63 frames. At a square within 8 pixels of Link's row or column, it rushes at 1.5 pixels a frame. |
| Darknut | `InitDarknut`, `UpdateDarknut` | Wanderer, turn rate $80, q-speed $20 red or $28 blue. Mask $F6: only the sword and bombs hurt it, and it parries any weapon arriving head-on (`ParryOrShove`). |
| Gibdo | `UpdateGibdo` | Wanderer, turn rate $80 at the default q-speed $20. |
| Bubble | `UpdateBubble` | Wanderer, turn rate $40, one pixel a frame; unkillable and harmless. A flashing one blocks the sword for $A0 frames, a red one curses it, a blue one lifts the curse. Bubbles do not keep a room uncleared. |
| Like Like | `UpdateLikeLike` | Wanderer, turn rate $80. On contact it holds Link in place without knocking him back. After $60 frames it eats the magical shield. Killing it frees him. |
| Vire | `UpdateVire` | Wanderer, turn rate $80, hopping by `VireJumpOffsets` while moving sideways. Wounded, it becomes two red Keese. |
| Pols Voice | `UpdatePolsVoice` | Only the sword hurts it (mask $FE). Walks a random cardinal distance every other frame and hops with gravity $38/256. Provisional: the original's eight-way jump table is simplified. |
| Wallmaster | `UpdateWallmaster` | Waits until Link stands against a wall, then emerges ahead of him ($24 pixels, or $32 when he is walking). It follows a seven-square `WallmasterDirsAndAttrs` path at q-speed $18, with $60 frames between emergences. If it catches Link, it carries him back to the level's first room. |
| Blade trap | `InitTrap_Full`, `UpdateTrap_Full` | Six or four at `TrapXs`/`TrapYs`. When Link lines up within $0E, a trap slides toward the room's middle at 1.75 pixels a frame, stops within 5 pixels, and creeps home at 0.5. Invulnerable; does not count toward clearing. |
| Blue Wizzrobe | `UpdateBlueWizzrobe` | Walks one pixel every other frame toward Link, switching axes every 64 steps, and reverses at walls. When its timer ends it teleports $20 pixels diagonally, flickering. Every 32 frames it shoots magic if facing Link along his row or column. |
| Red Wizzrobe | `UpdateRedWizzrobe` | A 256-frame cycle. It appears on a square at a `RedWizzrobeOffsets` spot near Link, facing him, flickers in, and stands solid. It shoots at $B0, flickers out, and hides. |
| Aquamentus | `InitAquamentus`, `UpdateAquamentus`, `UpdateFireball` | 24x32 boss at ($B0, $80) with its own palette row. Paces between X $88 and $C7, one pixel every eight frames. When its timer ends (random OR $70), it breathes three fireballs drifting 0, +1, and -1 pixels every other frame. Fireballs aim at Link on one of nine `FireballQSpeeds` angles, wait 16 frames, then fly through walls; the magical shield stops them. Immune to the boomerang and fire (mask $E2). The heart container appears once it falls. |
| Dodongo | `UpdateDodongo`, `Dodongo_CheckBombHit` | Walks with turn rate $20, steering from its head when facing right, up, or down. It is 32x16 sideways and 16x16 vertically, in the orange boss palette. Weapons cannot hurt it. A ticking bomb at its mouth is eaten: it bloats for $20 then $40 frames, and a second eaten bomb makes it flicker for $40 more and die. A bomb blast beside it stuns it, and any sword hit then kills it. |
| Gohma | `InitGohma`, `UpdateGohma`, `Gohma_HandleWeaponCollision` | 48x16, the middle starting at ($80, $70), tinted by type (blue $33: 6 HP, red $34: 2). Moves half a pixel a frame: 32 pixels out and back, then picks right, left, or down. The eye opens for $80 frames every $C0 OR random half-frames, fully open between $70 and $10. It fires a fireball every $41 frames. Only an arrow flying up into the open eye hurts it; everything else is parried. |
| Digdogger | `UpdateDigdogger`, `InitDigdogger1/2` | A big 32x32 body in the orange boss palette that weapons cannot hurt. It drifts in eight directions with speed swinging between $40 and $80, turning every 16 frames at random or toward Link. After the recorder plays in its room, it flickers small for $40 frames, then splits into three ($38) or one ($39) little Digdoggers. Those move a pixel a frame faster and can be killed. |

Wizzrobe magic ($58 and $59) flies through walls; only the magical shield stops
it. It uses the sword-beam images for now. Health and contact damage come from the original tables; HP 0 means any hit
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

Lanmolas, Moldorms, Patras, and the remaining bosses: Manhandla, Gleeok, and
Ganon. Dodongo does not yet drop its bombs. Second-quest
Stalfos shooting, monster stun from the boomerang and clock, and keys carried by
monsters are also not implemented.
