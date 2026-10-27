# Importing original ROM assets

The game and Dungeon Workshop share one import backend. Supply your own NES
ROM; no ROM or original assets are distributed with this repository. The
supported revision is **US PRG0**, with a 128 KiB PRG payload, CHR RAM and mapper 1.
The importer checks the iNES header, exact file size and full PRG SHA-1:
`a12d74c73a0481599a5d832361d168f4737bbcf6`. Modified payloads, other revisions,
trainers and trailing data are rejected before extraction.

## Import through Dungeon Workshop

Launch the separate editor project:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path editor
```

1. Choose **Import ROM…** in the top toolbar.
2. Browse to your `.nes` file. It can live outside the repository; it is never
   copied or modified. Keeping it in ignored `reference-inputs/` is convenient.
3. Set the Python executable if needed. The default is `python3`; an absolute
   executable path also works. Install Python 3.9 or later. Extraction uses only
   the standard library and needs neither the disassembly nor an emulator install.
4. **Validate ROM** checks compatibility without changing assets. **Import /
   replace generated library** also validates, then performs the full extraction.
5. Follow the progress message and log. Audio rendering can take a while;
   progress describes extraction stages and cues, not a time estimate. The editor
   stays responsive. Close hides the dialog while the worker continues. The
   editor's normal close action waits for the import to finish.
6. Successful import switches to **Assets** and refreshes the library. Search by
   name and filter sprites, tiles or interface images. Select an entry to enlarge
   it. This browser reads the PNGs directly, without loading game resource scripts.

The GUI also asks the game Godot executable to prepare imported textures, so the
main game can use the new resources. This is a source-project workflow: keep
`editor/` inside the game repository. A standalone exported editor is not yet
supported. Close running game previews before replacing their imported library.

The browser currently previews individual image files/directions/palettes. It
**does not yet apply a selected monster skin or atlas tile to an authored room**.
Those appearance controls are separate from importing; see the
[asset-library plan](../editor/ASSET_LIBRARY_PLAN.md).

## Command line

From the Godot repository, use the staged entry point:

```sh
python3 tools/import_assets.py "/path/to/your.nes"
```

Optional commands:

```sh
# Check the ROM without replacing assets.
python3 tools/import_assets.py "/path/to/your.nes" --validate-only

# Also prepare Godot's texture cache, as the GUI does.
python3 tools/import_assets.py "/path/to/your.nes" --godot /Applications/Godot.app/Contents/MacOS/Godot
```

`--project /path/to/game` overrides the destination game project; it must contain
`project.godot` and the game scripts. Do not point it at `editor/` or the original
disassembly. Output always goes to that game's `imported/`. If `--godot` is
omitted, open the game project in Godot once to process the PNGs before playing.
No separate emulator core is required for graphics or audio extraction.

The lower-level `tools/import_rom.py ROM [--output ...]` remains available for
development. It writes directly and does not provide the new staging, backup,
job status or editor-catalog workflow. Prefer `import_assets.py` for normal use.

## Replacement, backups and failures

Generated files live under ignored `imported/`. Each run builds a fresh library
in `reference-inputs/import-jobs/<job>/assets/` first. Only a completed extraction
with required world/audio files, a matching manifest and an image catalog is
activated. The previous library is moved to that job's `previous-import/`.
A failed activation restores the previous directory. A failed extraction leaves
the active library untouched; partial staging files remain ignored for diagnosis.

The job directory contains:

- `status.json`: current state, stage percentage, revision, message and results.
- `import.log`: extraction output or failure details.
- `godot.log`: texture-preparation output when requested.
- `previous-import/`: the old generated library after successful replacement.

The GUI links these paths in its result message. Jobs, logs, catalogs, backups
and imported images all stay outside the public content boundary. Old finished
jobs/backups can be removed manually when no longer needed. Do not store custom
work in generated `imported/`; a future import replaces that directory completely.

Only one staged import may run per game project. It owns
`reference-inputs/import-jobs/import.lock/owner.json`. Normal success/failure
releases the lock. After a force-kill or machine crash, inspect that owner/job
and confirm the process has stopped before removing a stale lock. If a crash
occurred during activation and `imported/` is absent, restore the job's
`previous-import/` to `imported/` first. Keep the backup until recovery is verified.

If extraction succeeds but Godot cache preparation fails, the assets remain
installed and the dialog reports a warning. Open the game project in Godot and
inspect `godot.log`; rerendering the ROM is not necessary just to repair its cache.
If Python cannot start, enter its absolute path. If a worker exits without a final
status, the GUI reports that condition and points to the job folder.

## Imported output and authored content

The import includes both quest worlds, overworld terrain, caves, all nine
levels and cellars, enemy definitions and sprites, items, HUD/submenu graphics,
title/story/ending data, palettes and rendered sound/music. Topic documents
record runtime fidelity and implementation limits: [STATUS.md](STATUS.md),
[DUNGEONS.md](DUNGEONS.md), [SECOND_QUEST.md](SECOND_QUEST.md), [AUDIO.md](AUDIO.md).
Import coverage does not imply cycle-accurate gameplay or audio.

`imported/manifest.json` records the revision and content coverage.
`imported/editor_catalog.json` indexes 978 images in the current importer build,
with symbolic IDs, relative PNG paths, dimensions, categories and source
fingerprint. This count may change as extraction grows. Catalogs contain local
metadata, not embedded image pixels. Game resources still use `res://imported/`.

Custom content belongs in the authored pack/resource workflow described in
[Dungeon Workshop](../editor/README.md) and [EXTENDING.md](EXTENDING.md).
Do not copy imported rooms, graphics or original dialogue into `content/`.
ROM-derived edits and future editable copies must stay in ignored local folders.
The current JSON room editor does not round-trip imported `.tres` rooms.

Artwork and collision remain separate: existing RoomDefinition resources have
`tile_atlas`, `atlas_cell_size`, `tile_indices`, eight-pixel collision masks and
water masks. Higher-resolution replacement atlases can keep the logical 16-pixel
room geometry. A future texture painter must preserve that distinction.

## Decoder references

Offsets exclude the iNES header and are tied to the verified payload.

| Data / behavior | Disassembly reference |
| --- | --- |
| Pattern ranges, room layouts and level attributes | `src/bins.xml` |
| Pattern memory destinations | `Z_02.asm`: `CommonPatternVramAddrs`; `Z_03.asm`: `PatternBlockPpuAddrs` |
| Column pointers and layout routines | `Z_06.asm`: `ColumnDirectoryOW`; `Z_05.asm`: `LayoutRoomOW`, `LayoutRoomOrCaveOW` |
| Metatiles and objects | `Z_05.asm`: `PrimarySquaresOW`, `SecondarySquaresOW`, `WriteSquareOW`, `CheckTileObject` |
| Collision probes | `Z_07.asm`: `GetCollidingTileMoving`, `GetCollidableTile` |
| Link frames | `Z_01.asm`: `ObjAnimFrameHeap`, `Anim_WriteHorizontallyFlippableSpritePair` |

The ROM does not store RGB colors; the importer uses an approximate NES RGB
palette. Matching a particular emulator's colors remains a presentation choice.

## Verification

```sh
python3 -m unittest discover -s tests -p 'test_*.py'
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/run.gd --log-file /tmp/editor-tests.log
```

The staged-import tests are ROM-free and cover invalid-ROM preservation,
extraction failure, activation rollback, locking, catalog validation, backup
retention and cache warnings. Editor checks cover missing libraries, filtering,
raw-PNG previews and catalog path rejection. The optional integration test runs
the real GUI controller and Python worker:

```sh
# Bad-input rejection and real-ROM validation only.
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/import_workflow.gd --log-file /tmp/import-test.log -- --rom "/path/to/your.nes"

# Also rebuild the ignored local library and verify automatic thumbnail refresh.
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/import_workflow.gd --log-file /tmp/import-test.log -- --rom "/path/to/your.nes" --import-local-art
```

The full workflow has been exercised on this Mac with the supplied local ROM,
including Godot texture preparation, backup retention and a monster-image preview.
