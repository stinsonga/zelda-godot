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

- 60 fixed simulation ticks per second; 384 units per tick in 1/256-pixel units.
- Cardinal movement and most recently pressed direction priority.
- Perpendicular turns return toward the nearer eight-pixel grid point without
  snapping sideways. Remaining movement distance carries across the grid point.
- Direction-specific collision probes check the next eight-pixel segment at a
  grid boundary, then permit that segment to complete. Horizontal probes sample
  one leading column at Y + 11; vertical probes sample two columns at Y + 3 or
  Y + 19. This follows `GetCollidingTileMoving` / `GetCollidableTile`.
- Original overworld vertical edge coordinates are -3 and 157 relative to the
  play area, preserving the five-pixel Y grid phase through room transitions.

Still provisional: exact diagonal input handling, turn timing, fractional carry,
special-case collision at doors and screen edges, original room-entry walks,
NTSC timing, stairs, knockback, and animation. The prototype must not
be treated as a frame-accurate reproduction yet. The controller preserves fractional movement through grid boundaries; exact NES
input priorities and frame-by-frame turn timing still need emulator comparison.

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
