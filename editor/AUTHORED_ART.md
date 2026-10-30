# Authored graphics libraries

Dungeon Workshop can import your own PNGs without a ROM. Graphics live in shared
`content/art/`; packs refer to `art/<library-id>/<asset-id>`. Both the separate
editor and game use the same resolver. Share the PNGs and manifests alongside the
pack. Import copies/re-encodes the selected PNG; it does not move the source.

## Import and assign

1. Open **Assets → Import authored PNG…**. Choose a PNG, a library ID and a new
   asset ID (lowercase letters, digits, underscores or hyphens; at most 64).
2. Choose **tiles** or **sprite**. Tile sheets use square source cells of
   **16, 32 or 64** pixels and dimensions divisible by that cell size. Sprites
   use independent **Frame W/H** values (1–256 source pixels per side), frame
   columns and direction rows in the order you enter. Frames may be rectangular.
3. For a sprite, enter `all` for one row, or comma-separated rows such as
   `down,up,right,left`. Choose 1–16 frame columns and 1–120 game ticks per frame.
   The image dimensions must match those settings exactly. For example, four
   directions × two 32×48-pixel frames needs a **64 × 192** PNG.
   Set **Draw W/H** in logical game pixels, and **Offset X/Y** relative to the
   object’s unchanged top-left. For that taller sheet, draw at **16×24** with
   offset **0,-8** to keep its feet aligned to the existing 16×16 object.
   Match the source aspect ratio in Draw W/H to avoid stretching.
   Optionally enable **idle**, **walk** and/or **attack** clips. Enter their
   zero-based frame-column indices (for example `1,2`) and ticks per frame.
   Direction rows and drawing geometry are shared across the clips. Leave all
   clips off for the previous whole-sheet animation.
4. Click **Import into shared library**. The Assets browser refreshes. Existing
   asset IDs are never overwritten; use another ID for a new import. To replace
   art without rebinding rooms, edit its existing PNG while keeping the dimensions
   and layout, then **Refresh library**. Restart an open game preview to reload.
5. Select a sprite and **Use sprite set for selected enemy variant**. Its preview
   animates, with direction and clip selectors plus **Replay clip**. Every placement of that variant shares
   the choice; duplicate the variant for a separate skin.
6. Or select a tile sheet, click a cell, then **Paint selected atlas tile in Room**.
   Left-drag paints; right-click erases. One sheet per room is supported. Clear
   room art before switching sheets. Floor/Wall/Water still control collision.
7. For a room with a secret, stairs or a resident, select an authored sprite,
   choose the feature in Assets, and **Use authored sprite for room feature**.
   All stairs in that room share its choice. **Clear selected room feature art**
   resets that slot. **Clear room art** clears tiles and feature art together.

## Editing existing assets

Select an authored tile sheet or sprite in **Assets**, then click
**Edit authored asset settings…**. The form restores its current display name,
tile grid or sprite layout, drawing size/offset, direction rows and clips. Edit
those values and click **Save asset settings**. No JSON editing is needed.

The asset ID, kind, PNG filename and image dimensions stay fixed; the PNG bytes
are never rewritten. Frame columns and direction rows must still fit the image
exactly. To use a differently sized PNG, import a new asset ID. Changing a tile
grid reinterprets existing painted indices, so inspect rooms that use it afterward.

A successful save refreshes thumbnails, selection, and room previews. The name
filter is cleared if the renamed asset no longer matches it. Restart an open game
preview to load revised settings; running previews retain their compiled snapshot.

Library edits affect every pack using that ID and save immediately to its
`library.json`. They are separate from pack Save and undo/redo. Invalid settings
leave the library unchanged. If another edit changed the selected asset since
the form opened, saving is rejected; reopen the settings to load the latest data.
Changes to other assets in that library are retained. The settings button is
unavailable for private ROM assets.

Assignments, clearing, copying rooms/variants, and deleting features support
undo/redo. Save writes portable bindings in the version-2 pack. A version-1 pack
upgrades when shared art is assigned. Library import creates reusable files, and asset-settings edits update them;
both are separate from document undo. Unsaved Play snapshots include the bindings.

Source image detail is retained. Tile cells draw into logical 16-pixel squares;
sprite frames draw at their configured logical size and offset. Missing sprite
geometry defaults to 16×16 with offset 0,0, preserving older libraries. Draw sizes
support 1–128 logical pixels per side and offsets -128..128. Negative X moves
art left; negative Y moves it upward. Geometry applies to every frame/direction
in the set, including secrets, stairs and residents. Art is clipped at room edges
in the editor and playfield edges in game; it cannot cover the HUD. Collision,
movement, health, weapon reach and interaction hotspots stay the same. Editor
animations follow elapsed time; game animations follow simulation ticks and pause
with the game. Missing directions fall back to `all` or the first supplied row.
Secret sprites follow the existing push/reveal logic; stairs obey secret gates;
residents obey their transaction/visibility state.

## Idle, walk and attack clips

Sprite sheets may have optional named `clips`. Each clip contains `frames` (1–64
column indices into the sheet, including repeated indices), `frame_ticks` (1–120),
and `loop`. Idle and walk must loop; attack must have `loop: false`. Frame indices
remain zero-based, with at most 16 columns in a sheet. Every clip has its own
uniform timing; per-frame durations are not supported in this pass.

A five-column example is idle `0`, walk `1,2`, attack `3,4`. Choose a clip in the
Assets browser to preview it; **Replay clip** restarts its clock. Attack previews
stop at their final frame. The room view previews the chosen clip for enemies;
it does not run enemy AI. Thumbnails use idle where available. Room-feature
sprites use idle, falling back to walk or the previous whole-sheet cycle.

In game, named clips follow each enemy's simulation updates:

- Voluntary movement, including subpixel movement, selects walk; standing or
  blocked movement selects idle. Knockback does not count as voluntary walking.
- Existing windup/shooting phases and projectile releases select attack. A clip
  starts on the action, plays once and holds its last frame while that action
  remains active. An instantaneous release displays its complete visual clip;
  a new attack restarts it. Neither clip length nor timing changes movement,
  projectile release, collision, damage or recovery timers.
- Clock effects and stun freeze clip playback; game pauses stop its updates too.
- Missing clips fall back to walk, then idle, then the original whole-sheet
  cycle. Libraries without named clips retain their existing game animation.

The **Walker shoots rocks** checkbox in variant and placement settings exposes
existing walker shooting. It defaults off, uses the engine's existing targeting
and timers, and saves as optional `shooting_enabled` in a version-2 enemy
variant. Other current authorable families remain contact enemies and naturally
use idle/walk. Selecting attack art does not give an enemy an attack.

This milestone covers authored enemy variants. Link, equipment, dedicated boss
poses, hurt/death clips, per-direction clip layouts and synchronization of a
specific artwork frame to a hit event remain future work.

## Shared and private layers

Authored art remains enabled when **Local ROM art** is off. When enabled, a
private ROM choice overrides a shared enemy/tile choice. Applying authored art
clears the corresponding private override so the new choice becomes visible.
Room feature slots currently accept authored sprites only. See
[LOCAL_APPEARANCE.md](LOCAL_APPEARANCE.md) for the private layer.

Only `art/library/asset` IDs are accepted in shared appearance data. ROM IDs,
script/resource paths and absolute paths are rejected. The PNG importer rejects
sources inside `imported/`, `reference-inputs/` or `.godot/`, including symlink
aliases. It cannot determine whether an arbitrary external PNG contains copied
art; choose graphics suitable for distribution. Library output cannot use
symlink folders or files. PNG limits: 2048 pixels per side, 16 MB; each library
supports at most 64 assets. Invalid metadata or missing files produces diagnostics
and playable placeholders. No library is required to open or play a pack.

## On-disk format

Example `content/art/my_art/library.json`:

```json
{
  "format_version": 1,
  "id": "my_art",
  "title": "My art",
  "assets": [
    {"id":"tiles","name":"Tiles","kind":"tiles","file":"tiles.png",
     "width":64,"height":32,"cell_size":32},
    {"id":"guard","name":"Guard","kind":"sprite","file":"guard.png",
     "width":160,"height":192,"frame_size":[32,48],
     "draw_size":[16,24],"draw_offset":[0,-8],
     "directions":["down","up","right","left"],"frames":5,"frame_ticks":6,
     "clips":{
       "idle":{"frames":[0],"frame_ticks":9,"loop":true},
       "walk":{"frames":[1,2],"frame_ticks":6,"loop":true},
       "attack":{"frames":[3,4],"frame_ticks":3,"loop":false}
     }}
  ]
}
```

The version-2 pack's optional `appearance` object has `format_version: 1`,
`enemy_sprites` keyed by variant ID, `room_tiles` keyed by room ID (each with
`atlas` and 176 row-major `indices`; `-1` means placeholder), and `room_sprites`
keyed by room ID with `secret`, `stairs` and/or `resident` slots. These bindings
contain no filesystem paths. The source-only packaging tool includes libraries;
copying a JSON pack alone does not copy its PNGs.

## Current limits and checks

Rectangular source frames, draw sizes, offsets and idle/walk/attack clips are
supported. Additional animation states, per-direction offsets, layered bodies, boss-specific layouts, item/hero
skins and per-placement stair skins remain future work. Template capture and
seeded generation preserve shared art for selected rooms and their linked cellars,
including scoped enemy skins. Private ROM overlays are omitted. Template libraries
store references, so share the matching `content/art/` folders too. Appearance IDs
do not migrate automatically on rename.

Focused ROM-free checks generate original color fixtures in temporary folders:

```sh
godot --headless --path editor --script res://tests/authored_art.gd
godot --headless --path . --script res://tests/authored_graphics.gd
godot --headless --path editor --script res://tests/template_art.gd
godot --headless --path editor --script res://tests/rectangular_art.gd
godot --headless --path . --script res://tests/rectangular_graphics.gd
godot --headless --path editor --script res://tests/animation_clips.gd
godot --headless --path . --script res://tests/authored_animation.gd
godot --headless --path editor --script res://tests/asset_settings.gd
```

They verify importing/validation, directional crops, source resolution, scaled
picking, public/private boundaries, save/undo/copy/pruning, native animation,
unchanged collision/stats and missing-image fallback.
