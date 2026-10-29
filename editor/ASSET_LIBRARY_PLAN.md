# Editor asset library plan

The editor should use locally imported ROM art for monster selectors, tile
palettes, room painting and playtests. This is optional presentation layered over
the authored content model. The editor and its examples must still launch with
no ROM. The local catalog, import dialog and searchable PNG preview browser are now
implemented. Grouped sprite selection, atlas painting and matching game previews are now
implemented. See [LOCAL_APPEARANCE.md](LOCAL_APPEARANCE.md). The map remains schematic.

## What already exists locally

The existing importer produces these ignored resources:

- `imported/manifest.json`: source revision and PRG fingerprint.
- Named sprite PNGs such as `red_octorok_down_0.png` and
  `l1_stalfos_0.png`, with separate directions/animation frames where applicable.
- `imported/levels/level_1.png` through the per-level atlas collection, including
  progressively darker versions used for lighting.
- `imported/overworld_tiles.png`, `imported/cave_tiles.png`, items and HUD images.
- `imported/theme.tres`: the runtime's named-sprite lookup. Existing room
  resources already separate `tile_atlas`, `tile_indices`, and collision masks.

The standalone editor has a different `res://` root, so it cannot simply load
`res://imported/...` or the game's scripted `.tres` resources. A library adapter
should resolve the sibling game's imported directory and read PNGs plus a plain
catalog. It should reuse the importer output rather than import the ROM again.

## Implementation order

1. **Local catalog and visual browser — implemented.** The staged importer produces an
   ignored `imported/editor_catalog.json` containing symbolic asset IDs, display
   names, categories, PNG paths relative to imported/, dimensions and source
   fingerprint. The shared resolver derives frame/direction groups from these
   IDs; per-level palettes remain separate choices. Discover this optional catalog at editor
   startup and show a clear missing-import state when absent. Resolve only
   validated paths inside the selected library. No arbitrary `.tres` scripts
   need to run just to show a thumbnail.
2. **Monster selection thumbnails — implemented for 16×16 sets.** Group directions, frames and per-level
   palettes into one monster entry; show an enlarged/animated preview and a
   palette choice. Keep the behavior template and appearance explicit: choosing
   a skeleton picture must not silently convert a custom walker's behavior or
   overwrite its health and speed. A preview-only browser is useful first,
   followed by an explicit Apply appearance action.
3. **Tile palette and visual layer — implemented for one ROM atlas per room.** Show the 16-pixel logical atlas tiles at
   useful magnification, with level/palette selection and brush previews. Add a
   visual tile layer separate from collision. Wall corners, door frames and
   floor variants need actual tile selection, rather than applying one wall
   texture to every `#`. Collision painting remains explicit.
4. **Matching game previews — implemented.** Resolve the same asset IDs in the runtime adapter
   so Play room looks like the editor. Door state and lighting still belong to
   the game; art selection does not change those rules. Missing optional art
   must fall back to authored placeholders and retain a visible unresolved-art
   diagnostic.
5. **User-owned replacement libraries — implemented.** Apply the same catalog interface to
   authored art under `content/`. Higher-resolution images should draw into the
   existing logical rectangles, preserving collision and movement. A later
   graphics upgrade then changes an asset library rather than every room.

## Keep local appearance separate from public content

The first ROM-art integration should use a local appearance overlay, for example
`reference-inputs/editor-overrides/<pack-id>.json`, keyed by stable room/enemy IDs.
The shared pack retains its authored tiles and enemy settings; the overlay maps
those IDs to local sprite/palette/tile choices. The editor and game both resolve
that overlay. Preview/export must say whether local appearance is active.

Do not embed PNGs, ROM palettes, copied room layouts or original dialogue in the
shared pack or editor sources. Anything copied from imported rooms stays in an
ignored local pack and carries source provenance. If an editable-copy workflow
is added, it needs an explicit local/private destination and a source record;
it must never silently save those copies under `content/`.

Distributable libraries now use symbolic `art/library/asset` bindings in optional
version-2 appearance data, with strict validation. Version 1 continues to reject
asset paths and unknown fields. See [AUTHORED_ART.md](AUTHORED_ART.md). Room/enemy appearance and behavior remain
separate throughout.

## Acceptance checks for that milestone

- No import: editor, example, and playtest still work with placeholders.
- Local import: monster thumbnails, selected tiles and Play agree on appearance.
- Missing/stale catalog or PNG: useful diagnostics, no crash or accidental copy.
- Import directory is never modified by ordinary pack Save.
- Public snapshot contains no local catalog, overlays, caches or ROM images.
- Replacing a library changes presentation while room collision and enemy stats
  remain identical.

The import/catalog/browser, grouped sprite assignment, separate visual tile
layer and matching runtime overlays are implemented and verified. Authored replacement libraries now support 16/32/64-pixel tiles and directional
animated sprites, plus secret/stair/resident slots. Next: richer sprite layouts,
imported-room editable copies. Template capture and seeded generation now retain
shared art, including linked cellars and scoped enemy skins.
