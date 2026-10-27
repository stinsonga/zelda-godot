# Dungeon Workshop

A separate Godot 4.6 project for authoring ROM-free dungeons. Keep `editor/`
inside the game repository: Play launches the sibling game project with a
snapshot of the current pack. The editor has its own project settings, window,
cache and user-data directory.

Launch on this machine:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path editor
```

For development, import `editor/project.godot` in Godot. Running the game project's
`project.godot` still starts the game normally.

## Importing local graphics

**Import ROM…** runs the existing decoder in a background Python process, with
revision validation, progress, logs, staging and a previous-import backup. On
success, **Assets** refreshes its searchable sprite/tile/interface thumbnails.
This is optional; the editor works without a ROM. The browser previews art only
and does not yet assign it to authored rooms or monsters. Full instructions:
[IMPORTING.md](../docs/IMPORTING.md).

## First dungeon

The editor opens **Lantern vault**, a hand-authored three-room example. Its key,
guards, shutter and reward also exist as `content/packs/lantern_vault.json`.
Choose **New** for a blank room or **Open** to load an authored JSON pack.

1. Choose a room on the left. Add, copy or delete rooms there; stable room IDs are
   assigned automatically and are shown beside the title. Copying gives a fresh
   ID and map position and clears connections. Deletion removes incoming links.
2. Paint Floor, Wall or Water. These represent both placeholder appearance and
   collision. A drag fills crossed cells and forms one undo step.
3. Place a Spawn, Enemy or Pickup. The brush places actors on the dungeon grid.
   Right-click or Erase removes enemies and pickups. Paint Floor to remove terrain.
   Spawn cannot be erased; place it somewhere else.
4. Select an enemy brush variant on the right. Change its behavior, health,
   speed or contact damage, then Apply. Settings affect every placement using
   that variant. Duplicate a variant to customize it independently. Speed is in
   1/256 pixel per game tick; contact damage is in half hearts.
5. Pick a direction, destination room and door kind, then **Connect both sides**.
   The editor creates reciprocal doors and removes any displaced old connection.
   Door kinds are open, key, bombable, shutter, false wall and wall. Closed
   shutters open when all enemies are gone if the checkbox is enabled; otherwise
   they are one-way. The runtime supplies standard doorway geometry.
6. Set distinct dungeon-map positions (X 0..15, Y -15..0), and choose a starting
   room. Positions currently describe HUD map placement, not a generated layout.
   Connection directions are explicit. The Dungeon tab draws their graph and
   warns when connections disagree with the saved map positions.
7. **Validate**, then **Save as** under `content/packs/`. Title edits apply on
   Enter or when the field loses focus. Cmd/Ctrl+S saves; Cmd/Ctrl+Z undoes;
   Cmd/Ctrl+Shift+Z redoes. Undo history holds up to 100 operations.
8. **Play room** starts at the selected room's spawn; **Play dungeon** starts at
   the pack's starting room. Arrow keys/WASD move, Z/Space attacks, X/Shift uses
   the selected item, and Enter opens the item submenu. Close the preview window
   to return to editing. The preview starts with a wooden sword.

Saving and playing require a valid pack. Invalid painting can be undone or fixed;
validation lists errors in the bottom panel. Save uses a temporary file and
rename so a failed write preserves the old pack. Destructive document changes
and closing a dirty document ask before discarding edits. Opening rejects invalid
packs rather than partially loading them.

Play does not require saving the document. It writes a separate snapshot and log
in `user://previews` under the editor's `ZeldaDungeonWorkshop` user directory.
Preview files remain there for diagnosis. Playtest state is temporary: it does
not load or write game save files, and dying uses the lab-style restart rather
than the full front end.

## Dungeon map

Switch from **Room** to **Dungeon** above the canvas. Cards show room titles,
monster/item counts and the starting-room star. Connections show door kinds.

- Click a card to select it and update the shared room inspector. Double-click
  to open its room canvas. The room list and map share the same selection.
- Drag a card to an empty map cell. One drag is one undo step. Occupied cells and
  positions beyond X 0..15, Y -15..0 are rejected without changing the document.
- Choose a direction and door kind in the map toolbar, then **Add adjacent room**
  to create and connect a neighbour in one operation. If a room already occupies
  that cell, **Connect neighbour** connects the existing pair instead.
- Click an empty grid cell, then **Add at empty cell** to place an unconnected
  room there. Connect it using a neighbour or the right-side connection inspector.
- Wheel to zoom, middle-drag to pan, or **Fit map** to frame the occupied rooms.

Moving cards changes their saved map positions but preserves the explicit door
connections. A connection whose direction disagrees with the spatial layout is
shown dashed pink and listed as a layout warning. Those links still work as
configured in the game; moving a card does not silently change progression.

Validation also warns about rooms with no potential connection path from the
starting room. Wall doors are excluded; key, bombable, false and shutter doors
count as potential paths. These are non-blocking layout warnings: they do not
model keys, bombs, combat, one-way shutters or within-room walkability and do not
prove the dungeon solvable. Structurally invalid packs still cannot save/play.

Use **Import ROM…** to validate and extract your local ROM, then browse
its thumbnails in **Assets**. The room and map canvases still use authored
placeholders; applying skins and atlas tiles is the next step. See
[IMPORTING.md](../docs/IMPORTING.md) and [ASSET_LIBRARY_PLAN.md](ASSET_LIBRARY_PLAN.md).

## Shared format and runtime

`shared/room_pack.gd` is the one pack contract: both projects load that same file.
It parses, validates and saves version-1 JSON. The game adapter
`../scripts/authored_pack.gd` builds existing WorldDefinition, RoomDefinition,
DoorDefinition, EnemyDefinition and pickup resources in memory. These are not a
second implementation of combat or doors. Existing `.tres` content remains valid.

The pack is data only. IDs, dimensions, enum values, bounds, placement IDs,
walkable spawn/placement feet, room references, reverse door kinds and map
positions are checked. Script/resource/asset paths and unsupported fields are
rejected. Unsupported schema versions fail clearly. The format currently covers
plain dungeon rooms, connections, spawns, five enemy behavior families and five
pickup types; it does not import or round-trip arbitrary existing `.tres` rooms.
New packs begin with `custom_dungeon`; set a distinct Pack ID for each world.
Changing it creates a new world identity rather than migrating existing saves.
The GUI does not rename stable room or placement IDs yet.

No original graphics, maps or dialogue are present in this example. The editor
can import the local asset library but cannot yet convert imported rooms into
editable JSON packs. Keep ROM-derived material in
ignored `imported/` and `reference-inputs/`; Save refuses those local destinations.
See [ASSET_BOUNDARY.md](../docs/ASSET_BOUNDARY.md).

### Limits and next editor work

This is the first usable editing loop, not the complete editor. Next:

- Room-ID management and pack migration, with explicit handling rather than
  silently breaking saves. Unique IDs for independently authored packs matter.
- A visual inspector/selection tool for moving individual placements and their
  stable IDs; room filters, enemy variants' names, and more item/enemy properties.
- Atlas/palette and collision layers, with explicit provenance and an editable-copy
  workflow for any locally imported content. Asset swapping is not implemented here.
- Secrets, push blocks, cellars, caves, more item types and advanced doors.
- A proper standalone game export/pack-loading menu; preview currently launches
  the Godot executable and expects the sibling source project.
- Room-template tags and generation requirements, followed by a seeded generator
  and a progression validator. Structural validation does **not** prove key economy,
  combat accessibility, bomb availability or overall dungeon solvability.

Roguelike generation should produce this same concrete content model and let the
editor inspect the result. No generator or generation metadata was added yet.
Do not infer that a valid pack can always be completed.

## Checks

From the game repository:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/run.gd --log-file /tmp/editor-checks.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/authored_packs.gd --log-file /tmp/pack-checks.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/play_authored_pack.gd --log-file /tmp/pack-preview.log -- --pack content/packs/lantern_vault.json --check
```

The editor checks cover validation, file round trips, brush undo/redo, reciprocal
connection replacement, room deletion, enemy variants, map drag/undo, bounds and
occupancy rejection, adjacent-room creation, spatial warnings and connectivity. The game checks exercise
collecting the sample key, opening its door, clearing guards, opening the shutter,
collecting the reward, and applying edited variant settings. They need no ROM.
`tools/prepare_public_project.py` includes both projects and excludes nested caches.
