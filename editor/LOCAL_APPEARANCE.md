# Local ROM appearance

Dungeon Workshop can apply imported sprite sets to enemy variants and paint
atlas tiles independently of terrain collision. The same appearance resolver
builds editor previews and native game resources. No game behavior is inferred
from artwork.

## Choosing an enemy skin

1. Import your ROM using **Import ROM…**.
2. Select the target enemy variant in the right-hand inspector (for example,
   `crawler`). The variant can be used by multiple placements/rooms.
3. Open **Assets**, filter sprites, and search for a sprite set such as
   `l1 stalfos` or `red octorok`.
4. Frames and directions for supported 16×16 sprites are grouped into one
   choice. The preview animates; the direction selector chooses a view. Per-level
   palettes remain separate choices.
5. Click **Use sprite set for selected enemy variant**. The room view returns;
   all placements of that variant now use the selected art. Their behavior,
   health, speed, damage, collision size and IDs stay unchanged.

Use **Clear variant art** to restore its placeholder. Appearance assignments
share the same undo/redo history as room edits. A sprite choice does not turn a
walker into the original monster whose picture you selected. Complex boss sheets,
large ROM images are not skin presets yet. Authored replacement libraries are
available separately; see [AUTHORED_ART.md](AUTHORED_ART.md).

## Painting room art

1. In **Assets**, filter tiles and select an atlas such as `level 1`.
2. Click an atlas cell in the preview. The outline and index show the selected
   tile; click **Paint selected atlas tile in Room** to choose the Art brush.
3. Paint with the left button. A drag is one undo action. Right-click removes
   the art on that cell and restores its placeholder.
4. **Show terrain collision** overlays the base `#`/`~` collision cells. Use
   Floor/Wall/Water to edit collision; Art never changes it.

One atlas is supported per room. Choosing a different atlas does not silently
reinterpret existing painted indices: clear the room's art first, or return to
its atlas. **Clear room art** removes all visual choices for that room and is
undoable. Unpainted cells keep generated placeholders. The native engine still
opens/closes doors; closed key/shutter markers are generated rather than copied
from the original's door artwork. The editor shows their design state, while a
running game updates door state normally. This is not a full imported-room painter.

The **Local ROM art** checkbox controls display and playtests, without deleting saved
choices. Disable it to inspect the shared authored-art/placeholder version. **Play room**
and **Play dungeon** receive snapshots of both unsaved gameplay data and local
appearance. Missing catalogs/images or incompatible metadata produce warnings
and retain playable placeholder content.

## Save and sharing boundary

There are two separate documents:

- The shared pack JSON contains authored rooms, collision, placements, items,
  connections and enemy settings. Version 2 may also contain symbolic authored-art bindings; it contains no ROM
  art IDs or image data.
- `reference-inputs/editor-overrides/<pack-id>.json` stores the optional local
  sprite-set IDs, room atlas IDs and painted indices, with source fingerprint.
  This entire directory is ignored and excluded from source-only packaging.

Save writes the authored pack and, when changed, its local appearance overlay.
An art-only change still marks the editor dirty. If saving the overlay fails,
the pack may already have saved; the error says so and the appearance stays
unsaved for retry. Ordinary saves leave an unreadable, unchanged overlay intact.
Use distinct pack IDs for distinct worlds; appearance follows the stable pack,
room and enemy-variant IDs. No automatic ID migration is provided.

The overlay is deliberately outside `imported/`: replacing a generated ROM
library must not erase your appearance choices. Import does not copy images into
packs. All pixels continue to resolve through ignored `imported/editor_catalog.json`
and its PNGs. Copying an authored JSON pack to a source-only project gives its
shared-art version (when its authored library is also copied); its private
skin does not accompany it.

The preview command loads that pack's saved local appearance automatically:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/play_authored_pack.gd -- --pack content/packs/lantern_vault.json
```

`--appearance /path/to/overlay.json` overrides the local metadata, and
`--no-local-art` disables the private layer while retaining authored art. The overlay still resolves images only
through this game's local library; it cannot specify arbitrary resource scripts.

## Implementation and checks

`shared/appearance.gd` validates/resolves local metadata and groups sprite frames.
Room painting composes a temporary in-memory atlas, including placeholder cells,
so existing RoomDefinition validation and collision logic remain unchanged.
The runtime adapter clones the default visual theme before adding sprite keys;
it never mutates shared resource assets. Nothing composed is written into content/.

ROM-free checks create simple original red/blue test images:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/appearance.gd --log-file /tmp/appearance-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/authored_appearance.gd --log-file /tmp/appearance-game.log
```

They check grouped direction/frame lookup, sprite and tile assignment, art-only
undo/redo, shared/private saving, copying/deleting rooms, reimport survival,
scaled atlas picking, missing-image fallback, collision preservation, unchanged
enemy mechanics and default-theme isolation.

`editor/tests/local_art.gd` additionally exercises the real browser's sprite and
tile actions with a local import. It writes diagnostic snapshots only under
ignored `reference-inputs/editor-previews/appearance-demo/`, not to the user's
saved overlay. It skips when the import is absent.
