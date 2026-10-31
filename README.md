# NES Zelda reproduction in Godot

A faithful reimplementation of the original NES *The Legend of Zelda* (1986) in
Godot 4.6, translated routine by routine from a community disassembly and checked
frame by frame against an emulator. Both quests are playable from the title screen
to the ending. Rooms, enemies, items and dungeons are ordinary Godot resources, so
the game can also be extended or modded.

> **No game content is included.** This repository contains no ROM, graphics,
> audio, maps or text from the original game. To play the original game you must
> supply your own legally obtained ROM; an importer turns it into local resources
> that stay out of version control. Without it, the project runs small
> hand-authored test rooms. This project is not affiliated with or endorsed by
> Nintendo. *The Legend of Zelda* is a trademark of Nintendo.

## Requirements

- [Godot 4.6](https://godotengine.org/download) (the standard build, not .NET).
- Python 3.9 or later, for the importer and tests (standard library only).
- Optionally, your own **US PRG0** ROM (the importer checks it; other revisions
  are rejected).

The commands below assume a `godot` command. On macOS, Godot lives at
`/Applications/Godot.app/Contents/MacOS/Godot`; add an alias or use that path.

## Setup

```sh
git clone https://github.com/stinsonga/zelda-godot.git
cd zelda-godot

# Optional: import your ROM. Keep it anywhere; the ignored reference-inputs/
# folder is convenient. It is read, never copied or modified.
python3 tools/import_assets.py "/path/to/your.nes" --godot /path/to/godot
```

The import writes everything to the ignored `imported/` folder and takes a minute
or two (most of it is rendering audio). `--godot` also prepares Godot's texture
cache; without it, open the project in the Godot editor once before playing.
`--validate-only` checks a ROM without importing it. See
[docs/IMPORTING.md](docs/IMPORTING.md) for details, and
[docs/ASSET_BOUNDARY.md](docs/ASSET_BOUNDARY.md) for what stays local.

## Running

```sh
godot --path .
```

Or open `project.godot` in the Godot editor and press F5. With an import, the game
starts at the title screen; without one, in the test rooms.

| Action | Keys |
| --- | --- |
| Move | Arrow keys or WASD |
| Sword (A) | Z or Space |
| B item | X or Shift |
| Start (submenu) | Enter |
| Select | Tab |
| Native save / load | F5 / F9 |
| Mute | M |

## Building for desktop

Godot exports need its export templates and an export preset per platform.

1. Open the project in the Godot editor (`godot --path . --editor`).
2. **Editor → Manage Export Templates → Download and Install** (once per Godot
   version).
3. **Project → Export → Add…** and choose **macOS**, **Windows Desktop** or
   **Linux**. On the **Resources** tab, keep *Export all resources in the
   project*, and add
   `editor/ui/*, editor/tests/*, tests/*, tools/*, docs/*, reference-inputs/*`
   to *Filters to exclude files/folders* (the game uses `editor/shared/`).
4. **Export Project**, into the ignored `exports/` folder, for example
   `exports/macos/Zelda.zip`, `exports/windows/Zelda.exe` or
   `exports/linux/Zelda.x86_64`.

Once a preset exists (it is saved to `export_presets.cfg`), you can rebuild from
the command line:

```sh
godot --headless --path . --export-release "macOS" exports/macos/Zelda.zip
godot --headless --path . --export-release "Windows Desktop" exports/windows/Zelda.exe
godot --headless --path . --export-release "Linux" exports/linux/Zelda.x86_64
```

The preset name must match the one shown in the Export dialog. Unsigned macOS
builds need right-click **Open** the first time.

A build includes whatever is in `imported/`, so a build made after importing
contains material derived from your ROM. Keep such builds for your own use and
don't distribute them.

## Distributing an authored game

A build made **without** importing a ROM contains no original material, so it
can carry dungeons made in the Dungeon Workshop:

1. In the workshop, **Export game…** into a folder; it writes a bundle named
   after the pack, holding `pack.json` and the shared art it uses.
2. Put bundles in a `packs/` folder beside the exported executable (beside the
   `.app` on macOS), or in the game's `user://packs` folder.
3. At start-up the game lists the installed bundles; with one bundle and no
   imported game, it starts that bundle directly. Each bundle keeps its own save
   files.

`godot --path . -- --pack <bundle folder or pack.json>` plays one bundle
directly, which also works from the source project.

## Tests

```sh
# Python: importer, comparison harness and content checks.
python3 -m unittest discover -s tests -p 'test_*.py'

# Godot: one suite, or all of them.
godot --headless --path . --script res://tests/run.gd
for t in tests/*.gd; do godot --headless --path . --script "res://$t"; done
```

Some checks only run when `imported/` exists. The optional emulator comparison
(`tools/movement_trace.py`) needs a locally built reference emulator; see
[docs/MOVEMENT_COMPARISON.md](docs/MOVEMENT_COMPARISON.md).

## Dungeon Workshop

`editor/` is a separate Godot project for authoring ROM-free rooms, enemies,
pickups and doors, with undo/redo and playtesting in the game. Run it with
`godot --path editor`. It now includes reusable room templates, stable seeded
generation and inventory/geometry progression checks with witness routes. See
[editor/README.md](editor/README.md) and the
[generation guide](editor/DUNGEON_GENERATION.md).

## Documentation

- [docs/STATUS.md](docs/STATUS.md): what is done and what remains.
- [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md): structure and editing rooms.
- [docs/EXTENDING.md](docs/EXTENDING.md): adding rooms, enemies, items and dungeons.
- [docs/MOVEMENT_COMPARISON.md](docs/MOVEMENT_COMPARISON.md): how behaviour is
  checked against the original, and what that found.
- Topic notes in [docs/](docs/): combat, dungeons, caves, scrolling, audio,
  saving, the front end, the second quest and more.
