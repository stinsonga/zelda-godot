# Dungeon monsters

Implemented families: Stalfos, Goriyas, Gels, Zols, Keese, Ropes, Darknuts,
Gibdos, Bubbles, Like Likes, Vires, Pols Voices, Wallmasters, blade traps, and
blue and red Wizzrobes, and the bosses Aquamentus, Dodongo, Gohma, Digdogger, Manhandla, Gleeok, Moldorm, Lanmola, Patra, and Ganon, plus Zelda and her guard fires. Dungeon residents and rupee
stashes are in too (see DUNGEONS.md). 215 of the 216 first-quest dungeon rooms
that hold monsters are populated, and every cellar holds its four blue Keese.
The last, level 7's hungry Goriya, waits for bait. It stays empty rather than
substituting a different monster. The manifest records the counts.

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

Dodongo does not yet drop its bombs. Grumble (type $36) needs the bait item. Second-quest Stalfos
shooting, the clock's freeze, and keys carried by monsters are also not
implemented. The boomerang's stun is in; see Link's items in CAVES_AND_SECRETS.md.

## Manhandla

`InitManhandla`, `UpdateManhandla`, `Manhandla_Move`, and `Manhandla_CheckCollisions`
are translated into a shared group with four independently damageable hands and
an invulnerable center. Each hand has source HP, separate invulnerability, and
immunity to fire/boomerangs. It ignores knockback. All parts move together in eight
directions, turning every 16 ticks and bouncing when an outer part reaches room
bounds. Speed starts at 0.5 pixels/tick and increases by 0.5 after a tick in which
a hand dies. Each hand's independent animation can trigger a fireball when its
mouth closes (random >= $E0); shots share the encounter cap. The last hand kills
the center, allowing room rewards and shutters to use the existing clear rules.

Hand deaths do not increment persistent encounter kills or the world loot cycle.
The room stores one boss defeat; leaving a partial fight rebuilds its hands.
Source HP, palettes, and part sprites stay under ignored imported/. Native
`content/enemies/manhandla*.tres` are authored fixture presets; body speed,
acceleration, turn interval, hand definition, and offsets are editable resources.
Group links use weak references so replacing a room does not retain the actors.

`tests/manhandla.gd` runs without a ROM and checks independent HP, damage masks,
knockback, acceleration, bomb multi-hits, partial-fight reconstruction, and room
persistence. With imports it also runs the level 3 encounter. Python tests compare
all ten imported part images pixel by pixel against the original patterns and
palette. `visual_preview.gd -- manhandla` renders the assembled boss.

Exact within-frame collision/movement ordering, per-part boundary bounce delays,
and original boss cries still need emulator comparison; this is a native boss
implementation, not a claim of frame-perfect parity.

## Gleeok

All four neck-count variants ($42–$45) now import, including the first-quest
encounters in levels 4, 6, and 8. The fixed 24x32 body draws at ($74,$57); its
collision reference is the bottom neck segment at ($7C,$6F). Five segments per
neck begin five pixels apart. One neck moves each video frame, selected by
frame & 3. Head movement preserves the original counters: initially 6 horizontal,
3 vertical, reversing after 12/6 groups of four selected updates; initial delays
are neck index times 12 selected updates. Neck contraction, expansion, reference
alignment, and the original same-X subtraction quirk are translated from
`Gleeok_MoveNeck` and `Gleeok_StretchNeck`.

The source shares a 10-HP pool and damage cooldown across attached heads. Only
swords and sword beams hurt them. Severing the struck head resets the pool to 6
for the surviving necks (`Gleeok_CheckCollisions`, STA ObjHP,#$60). The detached
head cannot be damaged, ignores terrain, and flies at speed $BF increasing to
$E0, choosing chase/wander states without ever resting. It and the selected
attached head can shoot Fireball2 ($56), which penetrates even the magical shield.
The fireball model now distinguishes these from blockable Aquamentus fireballs.
Base hits cause fast body writhing without killing the boss. Neck links are
visual; only their base and heads cause contact damage. Weapon hits do not shove
any Gleeok component.

After the final attached head falls, the body dies and all detached heads vanish.
The encounter counts and persists once; partial fights rebuild on room entry.
Existing room-clear logic then releases shutters and rewards. The general
four-shot cap is retained; exact NES shot-slot scheduling and which leftover
fireball survives the death sequence remain fidelity follow-ups.

`EnemyDefinition.gleeok_head`, `gleeok_neck_count`, `gleeok_head_delay`, and
`gleeok_next_head_health` configure native variants. The head resource's HP controls
the initial pool. Native presets in content/enemies/ contain authored placeholder
settings. All original patterns, palettes, and imported boss variants stay under
ignored imported/.

`tests/gleeok.gd` runs with or without a ROM: selected-neck timing, shared HP and
cooldown, masks, detachment, continuous flight, shield rules, final cleanup,
partial-fight reconstruction, persistent defeat, and editable four-head variants.
With imports it exercises every Gleeok room. `tests/test_gleeok.py` checks variants
and every body/neck/attached-head pixel in level groups 4/6/8. Preview arguments
are `gleeok2`, `gleeok4`, and optional `detached`. Frame-by-frame emulator
comparison, sprite priority/flash details, and boss cries remain pending.

## Moldorm

`InitMoldorm` creates two five-segment worms, with every segment initially at
($80,$70). Heads occupy the highest slot in each chain (5 and 10), choose random
eight-way directions, and start moving at half a pixel per tick. Other segments
start with no direction: they are hidden and cannot collide until direction
propagation activates them. Heads chase or wander for eight turns, choosing chase
when random >= $40. Every 16 ticks, each segment receives the preceding segment's
old direction. This creates the original eight-pixel following delay. Head bounces
are deferred until the next propagation; followers ignore terrain.

Segments retain individual HP and nonlethal damage cooldowns. `UpdateMoldorm`
handles a lethal hit by removing the lowest remaining slot (the tail). The death
spark appears at the struck position. If the struck part was not the tail, it
continues in the same slot with two HP, preserving the head and chain ordering.
Lethal hits reset invulnerability; weapon hits never shove Moldorm. Only a chain's
last/head segment advances the world loot cycle and rolls its original drop group;
removed body segments produce no drops. The invisible native encounter controller
never draws, collides, advances loot, or produces a reward.

All ten segments must die to clear the live room. Separately, the original
`InitMoldorm` sets RoomObjCount to eight, the history format's maximum kill count.
Imported Moldorm rooms use `persistence_enemy_count = 8`: resolved segment deaths
are capped at eight, and a retained eight-kill room does not respawn, even if two
segments were still alive when Link left. Below the cap, reentry instantiates the
original full ten segments; the previous kill count remains in history. Native
authored fixtures leave that override at zero and persist one complete encounter.
Checkpoint format remains version 3; live segment positions and fractional motion
are transient, as for other enemy families.

`EnemyDefinition.moldorm_segment`, `moldorm_chain_count`,
`moldorm_segments_per_chain`, `moldorm_segment_reset_health`, and `boss_turn_ticks`
configure variants. The segment resource controls HP, speed, contact damage,
art, and damage masks. The authored content/enemies/moldorm*.tres presets and
`tests/moldorm.gd` work without a ROM. Tests cover real sword collision, individual
HP, head-preserving tail replacement, activation/following, no knockback, history,
full room clearance, and a faster one-chain/three-segment variant. With imports,
they simulate all Moldorm rooms. Python checks source stats and each sprite pixel
in levels 2 and 7. `visual_preview.gd -- moldorm` renders a deterministic encounter.

Per-slot movement/collision order, initial timer phase, exact death-spark timing,
and boss cries remain emulator-comparison follow-ups.

## Lanmola

Lanmolas reuse the Moldorm chain machinery with `chain_style = "lanmola"`
(`LanmolaGroup` extends `MoldormGroup`), so setup, tail replacement, kill history,
and persistence are shared. `InitLamnola` places both five-segment worms at
($40, $8D) with only the heads moving, upward. Speed is the type minus $39: red
($3A) one pixel a frame, blue ($3B) two (`chain_speed`). `UpdateLamnola` moves
every segment that has a direction. At every 8-pixel point, the head copies
directions one segment back, tail first. At every 16-pixel square it picks a new
direction that never reverses:

- half the time toward Link, sideways only if that is allowed and Link faces that way;
- otherwise straight on (random+1 >= $80), or turning to the first perpendicular
  ($40-$7F) or the second (< $40);
- then rotating past the room bounds and walls (`BoundByRoom`, walker tile probe).

A lethal hit kills the chain's tail in the hit segment's place and revives the hit segment
at HP $20 (2). Rooms remember at most eight kills. Sprites are narrow 8x16 tiles,
head $9E and body $A0, in the row the speed XOR 3 selects. The authored
content/enemies/lanmola*.tres fixture and `tests/lanmola.gd` need no ROM.
`tests/test_lanmola.py` checks stats, rooms, and sprite pixels. Original art, palettes,
room data, and extracted definitions stay under ignored imported/.

## Patra

`InitPatra` starts Patra at ($80, $70) facing up and fills slots 2-9 with eight
children: type $25 for Patra $47 and $26 for $48. Everything except the sword
(and its beam) is parried. Patra uses the shared flyer states: speed $1F rising
to $40, then `Flyer_PatraDecideState` chases for eight turns on random >= $40 and
otherwise wanders. It never slows or rests. While any child lives, Patra can hurt
Link but cannot be hurt (`CheckLinkCollision` only).

The update loop runs from slot $B down to 1, so the children (`PatraGroup.tick_child`)
move before the parent and add the parent's movement from the previous frame.
A child's first update is its own initialization. Slot 2 then appears straight
above the parent at angle $18 (north). Each later child appears when slot 2 reaches
its `PatraChildStartAngles` entry. Children collide only once the last has appeared.
Each frame a child's angle drops by $70 ($25) or $60 ($26) out of 32 whole steps
a circle. `RotateObjectLocation` then adds q-speed $20 times the top bits of the
`PatraSines` value to X and Y. The bits come from the maneuver:

| Child | Radius | Maneuver 0 (X, Y bits) | Maneuver 1 |
| --- | --- | --- | --- |
| $25 | $2C | 6, 6: wide circle | 6, 5: flattened, wobbling ring |
| $26 | $18 | 5, 5: small circle | 6, 6: large circle |

Positions are integrated rather than computed from the angle, so the ring's
centre can drift from Patra, as in the original. The maneuver flips when its
timer is out and the slot 3 child is at angle 0, and the timer reloads $FF. The
timer is slot 2's `ObjTimer`, which that child's initialization clears, and room
entry zeroes the angles, so a Patra without a spawn cloud flips on its first update.
A dead child keeps its last angle.

Sprites: Patra is one frame, tiles $F8/$FA, flipped horizontally every two frames.
Children are half-width (attribute $C3), tiles $FC and $FE, in the red row 6.
Only Patra counts toward the room. Partial fights rebuild on entry, like the other
bosses. (The original stores any kill in this non-recurring template as a full
clear; see ROOM_PERSISTENCE.md.) Child count, orbit radius, angle step, rotation
bits, and maneuver time are editable. The authored content/enemies/patra*.tres
fixture and `tests/patra.gd` need no ROM. `tests/test_patra.py` checks tables,
stats, rooms, and pixels.

## Ganon

`InitGanon` halts Link. `UpdateGanon` then runs three scene phases:

1. Link holds up the Triforce in the dark room. Ganon stays unseen for $40 frames,
   then shows pose 0 while the room brightens in four steps ten frames apart
   (`UpdateCandle`, `AnimateWorldFading`).
2. Ganon stays shown for $C0 more frames.
3. The fight: monsters keep updating while Link is held (`combat.holds_player()`),
   and Link is released when this phase begins.

Dark rooms are not drawn yet, so a dimming overlay stands in for the palette
cycles in Ganon's room.

In the fight Ganon is blue and invisible, moving like a teleporting blue Wizzrobe
(`BlueWizzrobe_TurnSometimesAndMoveAndCheckTile` with `ObjRemDistance` 1):

- He changes pose every frame, so a hit shows him in a random one.
- He idles until the turn counter reaches $40. Then every $40 frames he turns
  toward Link, alternating axes, and snaps to the nearest square.
- He moves a pixel a frame and reverses at walls (the Wizzrobe probe points).
  Blocks and water are treated as walls; his room has none.
- He fires an unblockable fireball ($56) every $40 frames.

Only the sword reaches him (slot $0D; beams, bombs, and the rest pass through),
and only while he is unseen. A hit shows him for $40 frames with no flash or
recoil. On the frame that timer reads 1 he moves to ($30, $A0) or ($B0, $A0) by
the frame counter. Damage that would kill him instead restores HP $F0 (15) and
turns him brown (`GanonColorSets`).

Brown Ganon stands still for $FF steps, one every other frame. Below $30 he
flickers. Then he turns blue again at one of the two spots, keeping the restored
HP. While brown, only an arrow in flight with silver arrows owned (`InvArrow` 2)
hurts him: wooden arrows pass through.

A silver-arrow hit starts `Ganon_Dying`. He flashes $28 frames. At phase $50
the palette turns to the Triforce colors and he becomes ashes. `ADC #$07` runs
with the carry still set from the compare, so the ashes land 8 right and 8 down.
Eight rays leave from the ashes' centre (`GanonBurstDirs`): the cardinal ones every
frame, the diagonals three frames in four. Eight clouds close in from distance 8,
one step every 8 frames. At $A0 the burst ends, the room item (the Triforce of
Power) appears on the ashes, and the room counts as clear, opening the shutters.

`InitZelda` puts Zelda at ($78, $88) and four guard fires at
`GuardFireXs`/`GuardFireYs`. The fires burn on contact and can be struck. When
Link stands at Y $95 with X in [$70, $81), `UpdateZelda` places him at ($88, $88)
facing left and halts him. After $80 frames play stops,
`state.flags.zelda_rescued` is set, and `combat.ending` asks the front end for the
ending (mode $13, not yet built).

The roar, the Triforce/Ganon song, and Zelda's fanfare are not synthesized.
Existing cues stand in for them.

Ganon's hit time, brown HP, reappearance spots, and ash offset are editable. The
authored content/enemies/ganon.tres, zelda.tres, and guard_fire.tres fixtures and
`tests/ganon.gd` need no ROM. `tests/test_ganon.py` checks the tables, rooms,
stats, and body pixels. `tests/visual_preview.gd -- ganon`, `ganon_brown`,
`ganon_burst`, or `zelda` renders review screenshots.
