# Authored graphics libraries

Dungeon Workshop can import your own PNGs without a ROM. Graphics live in shared
`content/art/`; packs refer to `art/<library-id>/<asset-id>`. Both the separate
editor and game use the same resolver. Share the PNGs and manifests alongside the
pack. Import copies/re-encodes the selected PNG; it does not move the source.

## Import and assign

1. Open **Assets → Import authored PNG…**. Choose a PNG, a library ID and a new
   asset ID (lowercase letters, digits, underscores or hyphens; at most 64).
2. Choose **tiles** or **sprite**, and a source cell size: **16, 32 or 64** pixels.
   Tile sheets must have dimensions divisible by the cell size. Sprite sheets
   use square cells, frame columns and direction rows in the order you enter.
3. For a sprite, enter `all` for one row, or comma-separated rows such as
   `down,up,right,left`. Choose 1–16 frame columns and 1–120 game ticks per frame.
   The image dimensions must match those settings exactly. For example, four
   directions × two 32-pixel frames needs a **64 × 128** PNG.
4. Click **Import into shared library**. The Assets browser refreshes. Existing
   asset IDs are never overwritten; use another ID for a new import. To replace
   art without rebinding rooms, edit its existing PNG while keeping the dimensions
   and layout, then **Refresh library**. Restart an open game preview to reload.
5. Select a sprite and **Use sprite set for selected enemy variant**. Its preview
   animates, with a direction selector. Every placement of that variant shares
   the choice; duplicate the variant for a separate skin.
6. Or select a tile sheet, click a cell, then **Paint selected atlas tile in Room**.
   Left-drag paints; right-click erases. One sheet per room is supported. Clear
   room art before switching sheets. Floor/Wall/Water still control collision.
7. For a room with a secret, stairs or a resident, select an authored sprite,
   choose the feature in Assets, and **Use authored sprite for room feature**.
   All stairs in that room share its choice. **Clear selected room feature art**
   resets that slot. **Clear room art** clears tiles and feature art together.

Assignments, clearing, copying rooms/variants, and deleting features support
undo/redo. Save writes portable bindings in the version-2 pack. A version-1 pack
upgrades when shared art is assigned. Library import itself creates reusable files
and is separate from document undo. Unsaved Play snapshots include the bindings.

Source image detail is retained: a 32/64-pixel cell draws into a logical 16-pixel
square. Collision, movement, enemy health and attacks stay the same. Editor
animations follow elapsed time; game animations follow simulation ticks and pause
with the game. Missing directions fall back to `all` or the first supplied row.
Secret sprites follow the existing push/reveal logic; stairs obey secret gates;
residents obey their transaction/visibility state.

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
     "width":64,"height":128,"frame_size":[32,32],
     "directions":["down","up","right","left"],"frames":2,"frame_ticks":6}
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

This first format uses square source frames and fixed logical sizes. Non-square
sprites, per-pose animations, offsets, layered bodies, oversized bosses, item/hero
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
```

They verify importing/validation, directional crops, source resolution, scaled
picking, public/private boundaries, save/undo/copy/pruning, native animation,
unchanged collision/stats and missing-image fallback.
