# Godot reproduction

This directory contains the Godot reproduction and all supporting work. The
original disassembly outside this directory is reference material and should
remain unchanged.

## Goals

- Reproduce the original game's movement, combat, timing, and room behavior.
- Make rooms, enemies, items, secrets, and progression easy to extend or modify.
- Separate presentation from gameplay so graphics can be replaced later,
  including higher-resolution artwork.

## Project boundary

Keep the Godot project, import tools, documentation, and project-specific tests
inside this directory. Do not write generated files into the original source
directories.

Tools may read the disassembly or an explicitly supplied ROM, but the playable
project should use resources within this directory. Keep reference input paths
configurable rather than depending on this repository's parent layout. Do not
commit supplied ROMs.

This directory is intended to become a standalone Git repository later. For now,
it remains part of the existing repository; there is no nested Git repository.

## Initial milestone

Build the starting overworld screen, sword cave, player movement and collision,
sword combat, one enemy, and a screen transition. Also add a custom room and an
enemy variant through the editable content system to verify expansion support.

## Run the foundation

Open `project.godot` in Godot 4.6 and press F6 with `scenes/main.tscn` open,
or press F5 to run the project.

- Move: arrow keys or WASD.
- Use the sword after collecting it: Z or Space.
- Save: F5. Load: F9.
- Reset to the current room's spawn: R.
- Walk through open screen edges to visit neighboring rooms.

After a ROM import, the project starts in the original overworld with original
tiles and animated Link sprites. It contains all 128 static overworld terrain
layouts, fixed-tick cardinal movement, collision, and scrolling room transitions.
Without imported resources, it falls back to the two placeholder test rooms.
The starting sword cave now supports entry, dialogue, a persistent session
pickup, and sword thrusts. Octoroks, rocks, shield blocking, sword damage, knockback, health, heart drops,
and rupee drops now work. Sword beams are also implemented. Sound, other enemy types, other caves,
and secrets are not implemented yet.

At full health (or half a heart missing), swinging also fires a sword beam.
See [sword beam rules](docs/SWORD_BEAM.md) for timing and fidelity notes.

Get the sword, walk east to fight the four Octoroks, and collect rewards. At zero
health, press Enter to retry. See [combat and rewards](docs/COMBAT.md) for content
editing, the custom-enemy lab, source references, checks, and fidelity limits.

See [cave and sword behavior](docs/CAVE_AND_SWORD.md) for controls, editable
content definitions, fidelity notes, and verification.

See [ROM import and content editing](docs/IMPORTING.md) for the importer command,
asset replacement, and how to expand the world.

See [implementation notes](docs/IMPLEMENTATION.md) for editing instructions,
source references, fidelity limitations, next steps, and the verification command.

## Source-only sharing

Locally supplied ROMs live under the ignored `reference-inputs/` folder. All
ROM-derived assets and resources live under the ignored `imported/` folder.
The project runs placeholder rooms without them. See [asset boundary and source
packaging](docs/ASSET_BOUNDARY.md) before publishing or extracting this folder.

Overworld room edges now scroll with source-based timing. See [scrolling notes](docs/SCROLLING.md) for behavior and fidelity limits.

Save/load now persists inventory, health, currency, collected items, defeated enemies, progression flags, and location. See [save controls and storage](docs/SAVING.md).

Imported overworld enemies now respawn using the original six-entry room history and kill counts. See [room persistence and custom policies](docs/ROOM_PERSISTENCE.md).

Sound effects and room music are implemented; press **M** to mute. Local ROM imports
include audio; clean source projects use original placeholder tones. See
[audio setup and fidelity notes](docs/AUDIO.md).
