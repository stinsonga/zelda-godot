# Original ROM import

The importer supports the US PRG0 revision used by the disassembly. It verifies
both the iNES header and the complete PRG SHA-1 before writing output. Different
headers, revisions, modified payloads, trainers, and trailing data are rejected.

From the repository root:

```sh
python3 godot/tools/import_rom.py 'godot/reference-inputs/Legend of Zelda_ The (U) (PRG 0).nes'
```

The tool uses Python's standard library only. Paths are explicit; it does not
need the disassembly checkout to run. After extracting `godot/` to its own repo,
run `python3 tools/import_rom.py path/to/your.nes` from that project directory.

Output goes to `godot/imported/`, which is ignored by Git. Re-running the importer
**overwrites generated resources**. Keep custom edits in copies under `content/`.
The ROM itself stays where supplied and is never modified or copied to output.

Open the project in Godot after import so it processes PNG textures. The main
scene automatically uses `imported/world.tres` when available, otherwise it uses
the original two-room test fixture. In the World Inspector, turn off
`use_imported_world` to run that fixture deliberately. A `world_definition`
resource assigned explicitly takes precedence over auto-detection.

## Imported content

- All 128 first-quest overworld static terrain layouts and the starting sword cave.
- A 256-by-256 atlas: 16-pixel cells, 16 columns, 64 slots per palette. Each
  palette uses the first 56 slots; the remaining eight are reserved.
- Per-room visual indices (16 by 11 cells, row-major).
- Per-room eight-pixel collision masks (32 by 22 cells, row-major).
- Eight Link walking frames, in right/left/down/up order, two poses each.
- HUD glyphs and a HUD scaffold. Sword ownership, health, and rupees are functional; other counters
  and the map rectangle still use placeholder state.
- `manifest.json` records revision, payload hash, start room, and limitations.

The initial room and position are read from original level info: room `ow_77`,
position `(120, 77)` relative to the play area. The player retains the original
Y grid phase of five pixels. Rendering adds the original two-pixel overworld
sprite offset independently of collision.

## Editing and expansion

Open an imported room `.tres` in the Godot Inspector to inspect its layout,
collision, spawn, and exits. For persistent changes:

1. Copy the room resource into `content/rooms/`. Edit `tile_indices` to change
   visible tiles and `collision_tiles` independently to change walkability.
   Imported rooms use these fine collision masks instead of the coarse `tiles`
   text. Both must be edited deliberately when a terrain change affects movement.
2. Copy `imported/world.tres` into `content/` and replace the room entry with
   your edited copy. Keep its ID to replace an existing room, or give it a new
   ID and add exits to create a new one. IDs are not restricted to hexadecimal
   overworld coordinates.
3. Assign the copied world resource to World's `world_definition` in the main
   scene. Keep the world start ID and destination IDs valid.

Worlds use a resource array, not a hardcoded 128-room engine limit. Imported
exits connect cardinal neighbors; collision prevents traversal through solid
boundaries. Overworld edges now scroll. Cave entry has its automatic walk; general forced
entry walks remain unimplemented. See [scrolling notes](SCROLLING.md).

To replace artwork, assign a new atlas to a copied room. For 32-pixel artwork in
the same slot arrangement, set `atlas_cell_size` to `(32, 32)`. The displayed
logical cell stays 16 pixels. The player's sheet can likewise contain larger
frames; it is divided into eight equal-width poses and drawn at logical 16 by 16.
Collision masks remain unchanged by graphical replacements.

This is an Inspector-editable intermediate format, not yet a tile-painting UI.

## Decoder source references

Offsets in the tool exclude the iNES header and are tied to the verified payload:

| Data / behavior | Disassembly reference |
| --- | --- |
| Pattern ranges, room layouts, level attributes and info | `src/bins.xml` |
| Pattern memory destinations | `Z_02.asm`: `CommonPatternVramAddrs`; `Z_03.asm`: `PatternBlockPpuAddrs` |
| Column heap pointers | `Z_06.asm`: `ColumnDirectoryOW` |
| Column start bits and two-square repeats | `Z_05.asm`: `LayoutRoomOW`, `LayoutRoomOrCaveOW` |
| Metatile construction and tile objects | `Z_05.asm`: `PrimarySquaresOW`, `SecondarySquaresOW`, `WriteSquareOW`, `CheckTileObject` |
| Interior versus exterior palette regions | `Z_05.asm`: `FillPlayAreaAttrs` |
| Terrain walkability threshold and exceptions | `Z_05.asm`: `ObjectRoomBoundsOW`; `Z_07.asm`: `WalkableTiles`, `GetCollidableTile` |
| Link frame tiles, pair arrangement and flipping | `Z_01.asm`: `ObjAnimFrameHeap`, `Anim_WriteHorizontallyFlippableSpritePair` |
| Walking poses, small shield, and sprite offset | `Z_07.asm`: `SetUpWalkingSprites`, `Link_EndMoveAndAnimate` |

NES colors are palette indices rather than RGB. The importer uses an approximate
RGB palette; matching a specific emulator's colors is a separate presentation
choice.

## Scope limits

The import covers the first-quest overworld, its reachable caves, and all nine
levels. See [caves and secrets](CAVES_AND_SECRETS.md), [dungeons](DUNGEONS.md), and
[dungeon monsters](DUNGEON_MONSTERS.md) for what each part covers. Armos, the
maze rules, some room effects, the second quest, and special overworld
monsters remain unfinished. Recorder, stepladder, raft, and first-quest bosses are
implemented; see [stepladder](LADDER.md) for water masks and crossing rules. Collision now follows the original direction-dependent hotspot probes at grid
boundaries. Full frame-by-frame fidelity, multi-button input priorities, and
special collision rules for doorways and room effects still need implementation.

## Verification

```sh
python3 -m unittest discover -s godot/tests -p 'test_*.py'
/Applications/Godot.app/Contents/MacOS/Godot --headless --path godot --script res://tests/run.gd
```

The Python checks include invalid input rejection, bitplane order, the known
starting-room landmarks, and decoding every overworld room. The local-ROM check
skips when no ROM is present. Godot checks the two-room fixture and, when imported
resources are present, validates all 128 rooms, the original spawn and cliffs,
walking east into the adjacent room and back west, the north exit, and a
synthetic bush passage that checks on-grid wall stops, turning away from walls,
solid side bushes, and reversing through the gap.

All ROM-derived output, including room resources and decoded dialogue, belongs
inside the ignored local asset boundary. See [source-only sharing](ASSET_BOUNDARY.md).

The importer now also exports repeated Octorok encounters, directional enemy
sprites, half-width rocks, heart/rupee graphics, and original Octorok drop rows.
See [combat support and limitations](COMBAT.md). ROM-derived reward tables remain
in `imported/world.tres`, while native item effects live under `content/items/`.

The importer also generates all sword-beam palette variants and burst pieces.
See [sword beam notes](SWORD_BEAM.md).

The title, story, and ending go into `imported/title/` (`tools/import_title.py`):
an index atlas of the demo's pattern tables, the prebuilt nametables, palettes,
and the tables the original reads each frame. See [the front end](FRONT_END.md).

Audio is also rendered from the verified ROM into ignored `imported/audio/`.
See [audio extraction and fidelity](AUDIO.md).
