# Overworld actors

Overworld monsters that do not come from encounter lists.

## Zora (Z_04 CheckZora, UpdateZora)

A room whose attribute A has bit 3 set keeps one Zora in its water. `RoomDefinition.zora`
names its definition; 37 first-quest rooms have one. With no Zora up, the room tries
the thirteen random bytes as $10-aligned spots: X not 0 or $F0, Y from $50 below $E0,
ORed with $0D. A Zora rises on the first spot whose foot point (X, Y + $0B) is water,
using the ladder's water mask (tiles $8D-$98, or `~` in authored rooms).

It never moves. It runs `UpdateBurrower` on the Blue Leever tables:
- a ripple for $20 frames;
- surfaced for $0F frames, facing Link, or showing its back if it is below him;
- state 3, firing a $55 fireball two frames in, after which the timer drops to $20;
- $10 frames more surfaced;
- sinking for $60 frames.

It can be struck, and hurts, only while surfaced. When it sinks it is removed and
another rises the same frame. A killed Zora leaves `ZoraActive` set, so none returns
until the room is entered again, as in the original. The clock freezes it.

## Armos (Z_01 CheckPassiveTileObjects, Z_04 InitArmosOrFlyingGhini, UpdateArmos)

Statue squares (tiles $C0-$C3) are listed in `RoomDefinition.armos_cells`; 12 rooms
hold 90 of them. Pressing into one wakes an Armos (`armos`) on that square, unless
the object slots are full or something already stands there.

- It fades in for $3F frames (`wake_ticks`), drawn every other frame. It hurts Link
  but cannot be struck yet.
- Then it faces down at q-speed $20 or $60, chosen by a random byte
  (`wake_speeds`). Its grid offset starts at 3 because it stood square-aligned, and it
  walks like a Goriya.
- Its square becomes floor (`armos_floor_tiles`).

It draws front or back (back when facing up), alternating two image sets every six
frames (`sprite_style = "front_back"`). It dies as the dead dummy: no drop, no
kill cycle, no room kill. Statues return when the room is entered again.

`SecretArmosRoomIds`/`SecretArmosXs` hide something under the Armos at ($X, $80):
- In rooms $1C, $34, $3D, and $4E, stairs to a cave that was unreachable before.
- In $0B and $22, stairs into the room's level, as a second entrance.
- In $24, the power bracelet: a `requires_secret` room item at the Armos' square.

These are `SecretDefinition`s with `trigger = "armos"`. They are not remembered: the
stairs appear only after waking the Armos again.

## Ghini (Z_04 UpdateGhini, UpdateFlyingGhini)

The six graveyard rooms hold a Ghini from their encounter lists. It spends
(slot + 1) * $10 frames in its spawn cloud. It wanders at q-speed $20, turning as
often as it can (turn rate $FF), and never shoots.

Gravestone squares (tiles $BC-$BF, `RoomDefinition.grave_cells`) raise a flying
Ghini (`ghost`) when Link presses into one, unless something already stands
there. The stone stays.
- The ghost fades in for $3F frames, like an Armos.
- It then flies on the shared flyer states: speed $1F rising to $A0. It chases on
  random >= $A0, wanders at >= $08 (`flight_rest_threshold`), and otherwise slows
  to rest.
- `UpdateFlyingGhini` never checks weapons, so it is `untouchable`: it can only
  touch Link.
- When the Ghini dies, every flying Ghini dies with it (`defeat_takes`).

Both draw the back image when heading up and the front otherwise, mirrored toward
the side they head (`sprite_style = "ghini"`).

## Boulders (Z_04 UpdateBoulderSet, UpdateTektiteOrBoulder)

Six rooms list boulder sets ($1F). They are invisible, untouchable generators
(`behavior = "boulder_set"`), and they spawn boulders as follows:
- Each starts like a Tektite, waiting its direction times four frames.
- When its timer runs out it drops a boulder (`spawns`) at the top of the screen
  (Y $40), at a random X in the chase target's half. The chase target is Link or,
  at times, his mirror image.
- It then waits (random + 8) AND $1F frames.
- While three boulders are falling (`spawn_limit`), it adds a random byte to its
  timer instead.

A boulder is a jumper with `jump_wait_style = "boulder"`:
- It turns toward the chase target but always heads down.
- It lands $20 lower, starting at speed $FE with acceleration $60
  (`JumperYAccelerations` from $16) and moving a pixel sideways a frame.
- It jumps again at once on landing.
- It reverses only at the room's sides and is destroyed at Y $F0.
- It only touches Link (`untouchable`), and it never drops or counts.

## Pond fairies (Z_04 InitPondFairy, UpdatePondFairy)

Rooms $39 and $43 list a pond fairy ($2F). She stays at ($78, $7D), alternating her
two images every four frames, and neither hurts nor can be hurt.
- When Link stands at the pond's edge (Y $AD, X from $70 below $81), he is held and
  his hearts refill six units a frame, with the heart sound every eight frames.
  The fairy does this herself, since the project's potion refill pauses everything.
- Eight hearts circle meanwhile (`PondFairy_MoveHearts`). The first starts $1C above
  her at angle $18, and each later one appears as the first passes its start angle.
  They move by angle steps of $60 with six-bit sines (`PatraGroup.orbit_step`), a
  ring about 54 pixels in radius centred below her.
- Once Link is full, the hearts keep circling for $50 frames. Then he is free, and
  the fairy is spent for the visit.

## Lost Woods and Lost Hills (Z_01 CheckMazes)

Room $61 (the Lost Woods) takes `ForestMazeDirs`: up, left, down, left. Room $1B
(the Lost Hills) takes `MountainMazeDirs`: up four times. Leaving a maze room:
- by the next direction of the sequence advances a step and leads back into the
  same room, until the last step plays the secret tune and lets Link through;
- by the free direction (east in the woods, west in the hills) leaves normally,
  keeping the progress;
- by any other direction starts the sequence over, in the same room.

Entering any other room resets the step. Rooms carry the sequence as `maze` and
`maze_free_exit`, so authored rooms can be mazes too.

## Verification

`tests/overworld_actors.gd` covers all five with ROM-free fixtures
(`content/enemies/lab_lurker.tres`, `lab_statue.tres`, `lab_ghost*.tres`, `lab_rock*.tres`,
`lab_pond_spirit.tres`): spawning on water, the cycle,
the fireball, replacement, no return after a kill, the clock, waking, the fade,
floor, speed, statues restored on re-entry, stairs and item secrets, ghosts from
stones, their immunity, their defeat with the Ghini, and boulders: the limit of
three, the starting half, the fall and removal, and immunity; the fairy's
hold, refill rate, hearts, linger, and single use; and the maze rules. With an import it checks
the room counts, the bracelet room, an Armos cave, a graveyard, the boulder rooms, and the two ponds.
`tests/visual_preview.gd -- pond` renders a refill.

