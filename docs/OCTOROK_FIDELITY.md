# Octorok fidelity

Imported enemy types 7–10 use `nes_octorok` behavior. Native enemy definitions
retain the configurable prototype AI, so custom encounters work without a ROM.
ROM-derived enemy definitions, spawn lists, edge eligibility, and cloud/death
sprites remain entirely under ignored `imported/`.

## Source rules translated

- `Z_04.asm`, `InitSlowOctorockOrGhini`, `InitFastOctorock`, `UpdateOctorock`:
  slow movement is 0.5 pixels per tick; fast movement starts at 0.75 and becomes
  1.0 after the shooting routine updates speed. Position retains fractional bits.
- `Wanderer_TargetPlayer` and `Z_07.asm`, `Walker_GetNextAltDir`: move before
  targeting; choose turns at 16-pixel grid boundaries; try the original direction,
  a random perpendicular direction, its opposite, then reverse when blocked.
  Alignment uses strict nine-pixel thresholds, a per-enemy turn timer, and red/blue
  turn probabilities. The chase target alternates between Link and a reflected
  or stale target using the original ten-frame long-timer cadence.
- `_TryShooting`: red requires a random byte of at least $F8 to start; blue
  bypasses that gate. Stop for a 48-tick timer, emit at 16, then recover until zero.
  Temporary invulnerability cancels the timer. At most four rocks can coexist.
- `AssignObjSpawnPositions`: select one of four entry-direction lists, reject
  blocked positions or positions within 34 pixels of Link on both axes, and
  advance the shared nine-position cycle. Save/load preserves this cycle.
  An entirely unusable custom list defers spawning and retries instead of hanging.
- Edge-spawn rooms use eligible perimeter cells, descending enemy slots, and
  random two-to-five long-timer intervals. Edge entrants have no cloud; ordinary
  spawns use staggered clouds and imported original animation frames.
- Enemy terrain checks use directional leading probes at Y+11 and the original
  bounds. Contact requires separation below nine pixels on each axis.
- Rocks originate at the shooter, move three pixels per tick, use leading terrain
  probes and a half-width collision center. An idle facing shield sends them into
  the original diagonal bounce for sixteen ticks. Death uses imported spark frames.

## Limits

This is a translation into the native simulation, not an emulator-verified
frame-perfect port. The random generator uses the NES feedback/rotate rule with
an explicit deterministic seed; it does not reproduce boot RAM and input history.
Enemy slots update in descending order, but the simulation still groups enemies
and projectiles instead of reproducing the complete NES object-slot scheduler.
Native checkpoints preserve room outcomes and the spawn cycle, not in-flight AI,
random state, timers, or projectiles. Loading rebuilds the encounter.
Only repeated Octorok lists are imported; other enemy types and mixed lists remain
future work. Unsupported drops and help-drop counters are described in COMBAT.md.

## Verification

Run `Godot --headless --path . --script res://tests/octorok_fidelity.gd` using your
Godot executable. The suite checks random carry propagation, grid turns, blocked
turn order, targeting timers, red/blue firing, recovery, slot refusal, shove
cancellation, collision boundaries, reflected targeting, directional spawn lists,
unsafe-position rejection, edge spawning, rock speed, and shield bounces.
With local imports present it also simulates the first east-screen encounter.
`tests/run.gd`, `tests/save_load.gd`, and `tests/room_persistence.gd` cover the
surrounding gameplay and persistence. Python tests verify imported sprite pixels.

Visual previews accept `octorok` and `octorok_cloud`; see the command pattern in
COMBAT.md. Review images belong outside the source tree.
