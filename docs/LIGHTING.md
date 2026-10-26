# Dark rooms and candle light

The first quest's 35 dark dungeon rooms now import their attribute-E bit $80.
Their normal atlas plus three faded atlases reproduce `AnimateWorldFading`'s
cycle $40 from each level's `LevelInfo_PaletteCycles`. Only the eight entries at
PPU $3F08–$3F0F change: background palette rows 2 and 3. Background palette rows 0/1, Link,
enemies, pickups, and the HUD retain their colors. Opened doors, revealed stairs,
and moving push blocks use the same selected atlas as the rest of the room.

A candle's fire travels sixteen pixels before standing. The first standing update
begins the reverse cycle $C0. Four palette writes occur ten ticks apart, including
the first unchanged dark palette, completing in 31 held simulation ticks. Link
and combat pause while brightening; the item timers continue counting down. Light
lasts for the current visit and remains after the fire expires. Blue-candle usage
limits are unchanged. Leaving or loading the room resets temporary candle light.

For ordinary scrolling, a lit-to-dark transition darkens before scrolling; dark
to dark retains its palette. Moving from an unlit dark room to a light room
brightens after arrival. All tiles share the current palette while scrolling.
Direct native room placement runs the corresponding entry fade. Loading a native
checkpoint reconstructs dark rooms immediately at the dark palette, without
restoring an in-progress fade or the previous candle's light. Saving is held off
while a fade is running.

Ganon retains his existing $40 dark wait, four-step reverse fade, and $C0 lit hold.
His `GanonFight.darkness` now selects real level-palette atlas variants instead of
a black overlay. No separate room-entry fade delays or competes with that intro.

## Editable content

Set `RoomDefinition.dark_room` to enable darkness and `light_step_ticks` to change
the cadence. A themed room can supply three `dark_tile_atlases`, ordered dim to
dark, with exactly the same dimensions and tile ordering as `tile_atlas`.
Validation rejects incomplete or mismatched sets. Without atlases, native rooms
progressively darken their authored floor colors/textures and background objects;
wall colors and actor graphics remain unchanged. That fallback requires no ROM.

ROM-derived faded atlases are generated only under ignored `imported/levels/`;
all source-only tests use authored fixture data. Re-run the ordinary importer to
regenerate them. The importer adds no source dialogue, palettes, or copied game
tables to shared content.

## Verification and limits

`tests/lighting.gd` works without a ROM: entry/exit and candle timing, movement
pause, fire timing, blue-candle behavior, reentry/checkpoint reset, scroll ordering,
and asset validation. With imports it checks all dark room resources and Ganon's
palette selection. `tests/test_lighting.py` checks every dungeon room's source
flag and every rendered tile pixel in representative dark rooms from levels 4/9
across all three dark atlases, including unchanged wall palettes.

Existing Ganon, dungeon, item, room-history, and checkpoint tests remain part of
regression verification. Preview options are `dark_room`, `lit_room`, and
`ganon_dark`/`ganon_fade` for visual checks.

This translates the source palette logic and cadence. Emulator replay comparison
is still pending. The NES decrements its full object-timer table during holds;
this native fade advances item timers but freezes actor AI timers with movement.
Special cellar/death palette cycles and front-end fades are separate systems.
