# Implementation notes

## Boundary and content

`project.godot` is the standalone project root. There are no runtime dependencies
on the disassembly or a ROM. The fallback two-room fixture uses placeholder geometry. After ROM import, the
project loads the original overworld and sprites from local resources. See
[import and editing instructions](IMPORTING.md) for the current import pipeline.

`RoomDefinition` resources hold stable IDs, display names, 16-by-11 tile layouts,
spawn positions in room-local pixels, and destination IDs for edge exits. `#`
is solid and `.` is walkable. Each tile is 16 logical pixels. The HUD occupies
64 pixels above the 256-by-176 room area.

To add a room:

1. Duplicate a `.tres` file under `content/rooms/` in the Godot FileSystem panel.
2. Set its unique `id`, title, tiles, spawn, and exits in the Inspector.
3. Select World in `scenes/main.tscn` and add the resource to `room_resources`.
4. Add an exit to the new ID in an existing room. For a return trip, add the
   reverse exit. Open matching passages at both edges.

Exits preserve the coordinate along the edge. As in `Z_07 CheckScreenEdge`, the
next room is not checked: Link can arrive on an unwalkable square. Overworld edge transitions now scroll; see [timing and behavior](SCROLLING.md).
Resources are validated at startup in debug builds. The first room in the list
is the initial room. Editing tile text is the initial authoring interface; a
paintable editor can replace it once the original room format has been imported.

`VisualTheme` holds colors and optional floor, wall, and player textures. Assign
it on World. A texture of any resolution draws into the same logical tile or
player rectangle; changing it does not alter collision. Directional sprite
animations, atlases, and room-specific tile sets are future work. `canvas_items`
stretch allows rendering higher-resolution artwork while retaining logical
coordinates. See Godot's resolution documentation:
https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html

## Fidelity ledger

Confirmed from the disassembly:

- `src/Z_05.asm`, `InitLinkSpeed`: normal quarter-speed is `$60`, with a comment
  specifying 1.5 pixels per frame. Mountain stairs use `$30`.
- `src/Z_07.asm`, `MoveObject`: quarter-speed is applied four times, and Link's
  grid limits are +8 and -8.
- `src/Z_07.asm`, `Link_EndMoveAndAnimate`: tracks eight-pixel grid boundaries.

Implemented baseline:

- 60 fixed simulation ticks per second. Free movement follows `Z_07 MoveObject`:
  four quarter-steps of $60 into one fraction byte shared by both axes. A carry
  moves Link a pixel unless his grid offset is already at +8 or -8
  (`AddQSpeedToPositionFraction`), so he stops on each grid point for the rest of
  that frame: eight pixels take six frames. On mountain stairs (overworld tiles
  $74/$75) `InitLinkSpeed` uses $30 instead.
- Cardinal movement and most recently pressed direction priority.
- Turns follow `Z_05 Link_HandleInput`, with the grid offset kept as state as
  in the original. At a grid point, Link takes the input. Between points,
  `Link_ModifyDirOnGridLine` keeps his direction at |offset| 4 or more, and
  otherwise keeps going or turns back toward the grid point he left. Link never
  snaps sideways, and the turn happens on the frame after he reaches the point.
- Direction-specific collision probes check the next eight-pixel segment at a
  grid boundary, then permit that segment to complete. Horizontal probes sample
  one leading column at Y + 11; vertical probes sample two columns at Y + 3 or
  Y + 19. This follows `GetCollidingTileMoving` / `GetCollidableTile`.
- Original overworld vertical edge coordinates are -3 and 157 relative to the
  play area, preserving the five-pixel Y grid phase through room transitions.

Still provisional: diagonal input handling, special-case collision at doors and
screen edges, room-entry walks (mode 4 still uses the older continuous step),
stairs, knockback, and animation. The [movement comparison](MOVEMENT_COMPARISON.md)
matches the original frame for frame in its eleven starting-room scenarios; wider
coverage is still to come.

## Next implementation stages

The current status, known problems, and remaining work are in [STATUS.md](STATUS.md).
The list below is the original plan, kept for history.

1. Trace and translate the original input, turning, and collision routines;
   compare captured movement sequences against the original game.
2. Extend the completed static overworld importer to caves, dungeons, and room
   effects. Original graphics, metatiles, level palettes, and overworld terrain
   now import into ignored, editable local resources.
3. Continue fidelity checks of the implemented Octorok encounter. Native enemy
   definitions, a custom variant, sword/contact damage, shield-blocked rocks,
   health, heart/rupee drops, and an end-to-end encounter test are now in place.
   See [combat notes](COMBAT.md) for remaining AI and respawn approximations.
4. Extend persistence to dungeon rules when dungeon content is implemented.
   Overworld history and respawn counts are now implemented; see
   [room persistence](ROOM_PERSISTENCE.md). Native save/load
   now persists stable IDs, inventory, health, currency, and progression; see
   [saving notes](SAVING.md). Screen scrolling and damage are also implemented.

## Verification

Run from this directory with Godot 4.6:

```sh
godot --headless --path . --script res://tests/run.gd
```

On this Mac, the executable is
`/Applications/Godot.app/Contents/MacOS/Godot`.

The checks cover normal speed, blocked movement, grid turning, solid room tiles,
paired room transitions, and preventing transitions away from screen edges.
They establish baseline invariants, not comparison against an emulated ROM.
