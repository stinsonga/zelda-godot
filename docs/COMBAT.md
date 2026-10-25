# First combat encounter

Get the wooden sword in the starting cave, leave, and walk east into overworld
room 78. This room has four red Octoroks. Use Z or Space to thrust the sword.
Face an incoming rock without attacking to block it with the basic shield.
Touch dropped hearts and rupees, or collect them with the extended sword.
The HUD preserves distinct full, half, and empty heart colors, so each hit and
healing pickup changes the displayed health. Heart graphics use their own texture
rather than the monochrome text atlas.

Hearts restore one heart, up to the current maximum. Rupees update the HUD and
cap at 255. Link takes half a heart from Octorok contact or an undefended rock.
At zero health the simulation stops; Enter retries the current room with restored
health and existing session inventory. This retry is a prototype convenience,
not the original continue-menu flow.

## Content and expansion

`EnemyDefinition` provides health, movement speed, contact damage, sprite family,
shooting timings, spawn duration, and a loot-table resource. `EnemySpawn` gives
it a stable ID, location, facing, random seed, and optional spawn-duration override.
There is no engine limit of four enemies; that count comes from this room's data.

Red Octoroks have one health unit; blue ones have two. Slow variants move half a
pixel per tick, fast variants one pixel per tick. All animate in six-tick poses.
The custom stout Octorok has three health units, a fractional speed, and a
guaranteed heart/five-rupee loot table, all set in native resources.

Open `scenes/combat_lab.tscn` and press F6 to test the base and custom enemy with
hand-authored placeholder art. Walk upward onto the sword pickup first. This lab
works without the ROM or imported resources.

`LootTable` contains a 0-to-256 chance threshold and a cyclic array of reward
resources. A null entry produces no drop. The cycle advances once when an enemy's
death effect completes. `RewardDefinition` separates the effect and amount from
the sprite name. Native fallback tables live under `content/enemies/`.
Original Octorok drop-table rows and probabilities are generated into the ignored
`imported/world.tres`; they are selected by the world's `loot_tables` mapping.
A world can override loot for an enemy ID without mutating its shared definition.

## Rules checked against the disassembly

- `Z_04.asm`, `UpdateOctorock`: directional frame selection, six-tick poses,
  mirrored vertical halves, and a flipped complete sprite when facing right.
- `Z_04.asm`, `InitMonsterShot`: rocks move three pixels per tick. Flying rocks
  check terrain as well as room bounds. Their half-width attribute selects one
  eight-pixel sprite column, drawn with a four-pixel horizontal offset.
- `Z_01.asm`, `CheckMonsterStabbingCollision` and
  `CheckMonsterSlenderWeaponCollision2`: damage only in the fully extended phase.
  Compare enemy center with sword position plus (6,8) for vertical attacks or
  (8,6) for horizontal attacks. Strict distance thresholds are (12,16) and (16,12).
- `Z_01.asm`, `BeginShove`; `Z_07.asm`, `DecrementInvincibilityTimer`: Link's
  timer is $18 and enemies' timers are $10, decremented every other frame. This
  implementation uses 48 and 32 simulation ticks respectively. Shove distances
  are 32 pixels for Link and 64 for enemies, at up to four pixels per tick.
- `Z_04.asm`, `DropItemRates`, `DropItemTable`, `SetUpDroppedItem`: Octorok drop
  groups use a global ten-kill cycle and a strict random threshold. Red uses
  group 0, blue group 2. These tables are read from the verified ROM.
- `Z_04.asm`, `UpdateItem`; `Z_01.asm`, `TryTakeItem`: drops live for about 510
  ticks and cannot be taken for their first 32. Pickup uses strict distances
  below nine pixels in X and in (taker Y + 3) versus item Y.
- `Z_07.asm`, `DrawItemBySlot`: hearts and single rupees alternate palette rows
  every eight ticks. Heart tile $F3 is an odd 8x16 sprite index, selecting the
  background pattern bank, rather than sprite tile $F3 directly.

## Known fidelity limits

This remains a native combat baseline, not an emulator-verified frame-perfect
port. Random wandering, target selection, shooting cadence, spawn positions,
spawn/death effects, contact and projectile collision boxes, and shield handling
still approximate parts of the NES routines. Spawn delays are staggered per slot,
but cloud visuals are procedural placeholders. Enemy grid turns preserve
fractional movement and check all intermediate terrain positions.

Only repeated Octorok types 7 through 10 are imported. Mixed object lists and all
other monsters remain unimplemented. Red and blue drop rows may reference bombs,
clocks, or fairies; those unsupported entries currently produce no drop. Help-drop
counters and the forced-fairy rule are not implemented. Currency applies instantly
rather than counting upward over multiple frames. Sword beams are implemented; sound remains unimplemented. See [beam rules](SWORD_BEAM.md).

Defeated enemies remain defeated for the entire session. The original six-room
history and respawn logic are not implemented. Loose drops disappear when leaving
the room. Save/load now preserves inventory, health, currency, collected items, and defeated
enemies. See [saving notes](SAVING.md). The original game-over flow remains a
future milestone. Overworld
scrolling now pauses combat and initializes enemies after arrival; see
[scrolling notes](SCROLLING.md).

## Verification

Run from the project root:

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd
```

The Python suite checks every Octorok pose and direction pixel by pixel against
the ROM, plus the half-width rock and background-bank heart composition. Tests
requiring local assets skip in a source-only copy.

The Godot suite covers all sword phases and reach boundaries, enemy damage and
invulnerability, wall-blocked player knockback, shield blocking, player damage,
retry, custom enemy health and speed, drop probability, delayed pickup, healing
and currency caps, reward expiry, and collecting with the sword.

Its original-room integration check obtains the sword through the cave sequence,
walks east into room 78, and defeats its four enemies using the real attack/death/
reward code. It fixes combat positions, movement, and rolls for reproducibility;
it does not claim to validate the original random AI. It collects the rewards,
returns west, and verifies session state and absence of duplicate drops on revisit.

For a deterministic visual review:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/visual_preview.gd --write-movie /tmp/combat.png --quit-after 3 -- combat
```

All rendered screenshots are review artifacts outside the source tree. All
ROM-derived sprites and tables remain under ignored `imported/`.
