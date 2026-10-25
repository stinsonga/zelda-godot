# Save and load

- **F5** saves the current game.
- **F9** loads the saved game for the currently running world.

On Macs configured to use function keys for system features, hold Fn as needed.
The HUD confirms success or explains a failure. Loading replaces unsaved progress.
The game starts fresh until you explicitly load; there is no automatic load or
save-on-quit behavior.

## What persists

A snapshot contains the world and room IDs, position in 1/256-pixel units, facing,
heart containers, health, currency, kill-cycle counter, inventory item IDs,
equipped item ID, collected pickups, defeated enemies, and enabled progression
flags. Flags and pickups use stable string IDs rather than array positions.

The original world uses the explicit ID `original_quest_1`. Custom world resources
should set a permanent `WorldDefinition.id`. A world without one falls back to
`native/` plus its starting room ID. Each identity gets a separate save filename.

Item IDs resolve through `World.item_resources`, `WorldDefinition.items`, and the
items referenced by room pickups. Register new items there when adding content.
Saves contain no resource paths, executable objects, graphics, or ROM data.
Changing the order of rooms or item resources does not change their save identity.

## Storage and recovery

Saves live in Godot's user-data directory, under `saves/`, outside this repository.
On this Mac, the default application directory is:

```text
~/Library/Application Support/Godot/app_userdata/Zelda · Reproduction Lab/saves/
```

Filenames use a hash of the stable world ID. The JSON document records the actual
ID in readable form. The format has version 1. A normal save writes a temporary
file, flushes and closes it, preserves the previous valid snapshot as `.bak`, then
renames the temporary file over the main file. A failed write keeps the prior
save. The loader can recover a valid backup if the primary JSON is damaged or
unavailable, and tells the player when it does so.

The loader validates structure, version, world identity, integer values, limits,
item IDs, room IDs, and location before replacing the current game state. Files
larger than 1 MiB and snapshots that would exceed that size are rejected. A failed
load leaves the current session intact, apart from displaying its status message.
Unsupported format versions are rejected; version migrations are not implemented.

If edited terrain blocks a saved position, the loader tries that room's spawn and
reports `LOADED AT ROOM ENTRANCE`. If the room or item is unavailable, or neither
the saved position nor the room spawn is walkable, loading fails without changing
the session. Keep stable IDs when modifying content; automatic ID remapping is
not implemented.

## Resume behavior and scope

Saving is unavailable during room scrolling, automatic cave entry, item lifting,
or death. It is available during ordinary movement and combat. A loaded game
clears pending input, attacks, beams, rocks, loose drops, animation state, and
knockback. Remaining enemies restart from their room definitions; defeated enemies
stay defeated. Link receives 48 ticks of arrival invulnerability. Unfinished cave
dialogue restarts unless the saved pickup/progression state suppresses it.

This is a native game save, not an NES emulator save state. Partially damaged
enemies, projectile positions, random-generator state, and loose drops are not
saved. The existing session-wide defeated-enemy behavior is preserved across
save/load; reproducing the original six-room respawn history is the next persistence
milestone. Multiple player profiles, save-slot selection, autosaving, and the
original NES continue/save menu are not implemented yet.

## Verification

Run from the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/save_load.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd
python3 -m unittest discover -s tests -p 'test_*.py'
```

The dedicated save suite writes only to a unique temporary directory and cleans
it up. It checks fresh-instance round trips, fractional positions, item and flag
restoration, backup recovery, invalid JSON and values, incompatible versions,
unavailable content, edited terrain, failed temporary writes, blocked save states,
keyboard controls, custom items, and original-world progression. Tests do not
write to or replace the player's real save files.

The source-only copy runs the same native save tests; original-world checks run
only when the local ROM import is available. No save or imported assets need to
be distributed with the source.

Implementation references: [Godot JSON parsing](https://docs.godotengine.org/en/4.5/classes/class_json.html)
and [file rename/copy operations](https://docs.godotengine.org/en/4.6/classes/class_diraccess.html).
