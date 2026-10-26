# Magical rod and book

The rod is a selectable B item. It uses the source weapon's five states
(5, 8, 1, 1, 1 ticks), offsets, and held poses. The preparation and final states
hide the rod; the final state retains its previous collision position. Unlike
the sword, the rod checks melee collision throughout its active states.
A thrust deals two damage using the sword vulnerability mask, so Wizzrobes can
be hit in melee even though they resist the wave. Ganon retains his separate
sword-only collision path and cannot be hurt with the rod.

At state 3 the rod launches a magic wave sixteen pixels ahead. It works at any
health, costs no rupees, deals two magic-type damage, and moves at 2.5 pixels per
tick. It passes through terrain and stops on enemy contact (including a parry)
or the room's projectile bounds. The rod/arrow share their active slot; another
arrow cannot fly while the rod is being swung, and an arrow blocks starting a
rod swing. The magic wave shares the sword-beam slot. A new rod wave may replace
a sword beam, including its burst, but never another magic wave. Further rod
swings remain possible while a wave flies. Sword beams wait until the slot is
free. Magic waves do not collect loose items.

With the book, impact creates a standing fire at the wave's position, if a
bomb/fire slot is free. It lasts 79 ticks, harms Link and susceptible enemies,
lights a dark room, and burns a tree secret when dying out. It does not need a
candle, spend the blue candle's room allowance, or interrupt Link with a new item
pose. Two occupied bomb/fire slots prevent a new fire. Without the book the wave
simply disappears. Fire limits and damage keep their normal candle behavior.

The source is Z_05 WieldRod, Z_07 UpdateSwordOrRod, HandleShotBlocked, and
Z_01 CheckMonsterArrowOrRodCollision / CheckMonsterSwordShotOrMagicShotCollision.
Rod sprites use item slot $08 with palette 1; magic uses slot $23's directional
frames and flashes through all four sprite palettes. Magic waves also correct
Wizzrobe projectile art. The magic sound uses Tune0Request bit $04, the same
sound request as candle fire. All decoded graphics/audio stay under ignored
imported/; shared resources contain behavior and authored fixtures.

## Authored content

Run `scenes/rod_lab.tscn` without a ROM. Pick up the rod at the starting position,
then the book to the right. Face right at Y 77 and cast: the book fire at the
right edge burns the marked obstacle after its lifetime.

The rod uses a WeaponDefinition with unique slot rod, damage for melee,
use_damage for the wave, use_speed_subpixels for fixed-point flight speed,
phase_ticks and offsets_x/y for poses. Set fires_beam false: the rod's wave is
launched by its own state path. Book use_duration_ticks controls standing-fire
lifetime. Give both items through normal pickups, caves, or dungeon room items.
The book is passive, not selectable. Native saves retain ownership and selection;
room entry/load discard swings, waves, and fire.

Tests cover action timing, low-health use, fractional speed, shared slots,
melee/magic masks, Ganon immunity, terrain flight, tree burning, dark-room light,
fire capacity, editable book timing, audio, and save/load. Import checks compare
all directional sprite pixels and audio requests against the local ROM.
Visual previews: rod_lab without imports, rod with a local import.

No emulator frame-by-frame comparison has been performed. Native per-pixel
projectile collision, initial emission timing, and the lack of a unified object
slot allocator remain fidelity limits. The source's full-slot moving-fire
reuse quirk is not modeled. Sword beam behavior keeps its existing native bounds.
