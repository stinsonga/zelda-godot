# Sword beam

Use Z or Space with the wooden sword. A beam fires during the third sword phase
when health meets the original threshold: full health, or half a heart missing
in this implementation's half-heart health units. At least one missing heart
prevents emission. No extra button is required.

Only one beam can exist at a time, including its burst animation. Link can swing
again while it flies, but another beam cannot be queued. A beam already in flight
continues if Link takes damage. Changing rooms clears it.

## Source rules

- `Z_07.asm`, `UpdateSwordOrRod`: state 3 attempts emission. This is the
  retraction phase following eight ticks of full sword extension.
- `Z_07.asm`, `MakeSwordShot`: the projectile slot must be empty; the full-heart
  count must match containers minus one and the partial heart must be at least
  `$80`. The half-heart model maps this to health >= maximum minus one.
- `Z_07.asm`, `SetUpWeaponWithState`: place the beam 16 pixels ahead. Horizontal
  launches require shot X >= `$14` and < `$EC`. Quarter-speed `$C0` gives three
  pixels per tick.
- `Z_01.asm`, `MoveShot`: movement checks room bounds. Unlike rocks, the sword
  beam does not use the terrain collision routine.
- `Z_01.asm`, `CheckMonsterSwordShotOrMagicShotCollision`: beam damage matches
  sword grade, with strict 12-pixel center-distance thresholds. A successful hit
  starts the burst; burst pieces do not cause further damage.
- `Z_07.asm`, `DrawSwordShotOrMagicShot`: cycle four palettes, use the beam item
  slot `$22`, flip left/down appropriately, and draw horizontal shots three
  pixels lower than their collision position.
- `Z_07.asm`, `SpreadShot`: four flipped corners spread from offset 2 toward 24.
  The implementation holds the projectile slot for a 22-tick burst.

`WeaponDefinition.fires_beam` controls whether a custom sword emits beams.
`SwordBeam` owns position, direction, damage, and burst lifetime. Combat routes
beam kills through the same defeated-state and reward pipeline as melee.

## Presentation and remaining differences

The importer generates directional beam sprites in four palettes and four burst
corner sprites for each palette. These remain in ignored `imported/`. No artwork
is embedded in the native projectile script. Without imports, a line and four
small circles provide a source-only fallback.

This is not a frame-perfect emulator comparison. Projectile limits currently use
the room resource's movement bounds, rather than every original weapon-specific
boundary exception. Health uses half-heart units rather than the NES's byte-level
partial-heart accumulator. Burst positions follow the source's offsets, while
update/render ordering may differ by one frame. There is no beam sound yet.

## Verification

The normal Godot suite checks delayed emission, exact launch position and speed,
health eligibility, configurable disabling, launch restrictions, single-slot
behavior, non-damaging burst and its lifetime, enemy damage, strict collision
thresholds, and cleanup on room changes. Existing encounter/reward tests still
pass with beams enabled. Python checks verify source pixels, all palettes,
directional flips, and burst-corner flips.

Visual preview arguments `beam` and `burst` are available through
`tests/visual_preview.gd`, alongside `combat`, `cave`, `sword`, and `lift`.
