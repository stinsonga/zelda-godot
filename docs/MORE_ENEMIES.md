# Common overworld enemies and editable variants

The imported overworld now includes red/blue Moblins, red/blue Lynels,
red/blue Tektites, red/blue Leevers, and Peahats alongside all four Octorok types.
The verified first-quest data produces 100 populated encounters, including 32
mixed encounters. List templates $62 and above now decode each slot in order;
room history, kill counts, drops, and checkpoint reconstruction work through the
same combat system for every family. Unsupported lists are omitted as complete
encounters rather than substituting another monster.

## Behaviors

| Family | Movement and combat |
| --- | --- |
| Moblin | Grid walking, aligned targeting, red/blue firing gates, two-pixel arrows; basic shield blocks arrows. |
| Lynel | Grid walking, dominant-axis targeting within 80 pixels, three-pixel sword shots; basic shield cannot block them. |
| Tektite | Directional jumps with acceleration, landing and waiting; jumps ignore solid terrain. Blue/red use different launch speeds, acceleration, and wait rules. |
| Blue Leever | Roams through six burrowing states with state-specific speed, duration, and animation; only exposed state collides or accepts damage. |
| Red Leever | Emerges near Link, turns back toward him, travels straight, then burrows when blocked; shared delay and two-active limit. |
| Peahat | Accelerates, chases or wanders in eight directions, slows, then rests. Ignores terrain; can hurt Link in flight, but accepts weapon damage only at rest. |

Original HP, contact damage, loot group, sprite frames, palettes, jump
accelerations, and Leever state tables are extracted into ignored `imported/`.
The player is still using the small shield; equipment upgrades remain future work.
Lynel shots ignore terrain, while arrows and rocks test terrain. Shots share the
four-projectile encounter limit. Enemy movement and projectile behavior are
separate settings, so a custom walker can use any supported shot family.

References in the local disassembly: `Z_04.asm`, `UpdateMoblin`, `UpdateLynel`,
`UpdateGoriya`, `_TryShooting`, `UpdateTektiteOrBoulder`, `UpdateBlueLeever`,
`UpdateRedLeever`, `UpdatePeahat`, `ControlPeahatFlight`, and flyer helpers;
`Z_05.asm`, `ObjListAddrs` and object creation; `Z_07.asm`, HP/attribute tables,
`SetUpWalkingSprites`, and projectile drawing; `Z_01.asm`, damage and sprite heaps.

## Editing and verifying variants

Open `scenes/enemy_gallery.tscn` and run that scene (F6). It contains six family
presets and three custom variants, uses authored positions, and supplies a sword
at the entrance. It needs no ROM. Placeholder graphics are intentional.

Edit or duplicate an `EnemyDefinition` resource under `content/enemies/`, then
assign it to an `EnemySpawn.enemy` in a room. Change `behavior` to select the
family. Common fields control HP, contact damage, tint, sprite family, and loot.
Walker fields control targeting, movement speed, firing threshold, projectile
kind, speed, damage, and shield blocking. Jumper fields control launch velocity,
three accelerations, horizontal speed, target offset, and waiting style. Burrower
fields contain six-element timing, movement, and animation arrays plus roam or
ambush style. Flyer fields control maximum speed, acceleration, turns, and rests.
Definitions are shared immutable configuration; timers, HP, and behavior state
live separately on each actor.

Verified examples:

- `swift_moblin.tres`: three HP, faster walking and arrows, unrestricted shooting
  start gate, and a custom tint.
- `high_tektite.tres`: three HP, stronger jump, adjusted acceleration and speed.
- `resting_peahat.tres`: lower maximum speed, faster acceleration, fewer turns,
  and longer rests, giving the player a wider damage window.

Malformed state-array sizes and invalid speeds, HP, or flight/jump settings are
reported by resource validation before a room runs. `RoomDefinition.source_spawn_lists`
is off for authored rooms, preserving `EnemySpawn.position` even in a world
containing original spawn tables. Imported rooms opt in. Edge spawning is an
independent room option. Set persistence to permanent, reset, or overworld as
appropriate; custom gallery encounters reset on entry.

Keep editable copies in `content/`; regenerating imports replaces `imported/`.
All original graphics and game-data tables remain excluded from source packaging.

## Verification and limits

`tests/more_enemies.gd` checks targeting, firing gates, jumps through terrain,
landing, Leever visibility/damage states, red emergence spacing, Peahat rest
vulnerability, per-actor isolation, custom resources, projectile kinds/damage,
shield rules, shared shot limits, and authored spawn positions. With imports, it
runs 500 ticks in each of the 100 encounters. `tests/test_more_enemies.py` checks
mixed-list decoding, slot order, original stats, and every imported new enemy
pose pixel by pixel. The existing gameplay/save/history/Octorok/audio suites
remain part of regression verification. `visual_preview.gd -- enemies` provides
a deterministic sprite review using the existing movie-preview command pattern.

This is the first native implementation of these families, not a frame-perfect
port. Jump boundary/corner recovery and fractional motion, red Leever long-timer
phase and terrain whitelist nuances, Peahat flight timing, and monster-arrow
startup/spark timing need replay comparisons. Shared native audio mixes and the
actor/projectile update grouping retain the limits documented in AUDIO.md and
OCTOROK_FIDELITY.md. Native checkpoints rebuild encounters; mid-jump/flight/burrow
state is intentionally transient. Zora, Armos, Ghini, and boulders are in (OVERWORLD_ACTORS.md); pond fairies
remain future work.
