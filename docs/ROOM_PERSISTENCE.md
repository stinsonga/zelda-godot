# Room persistence and respawning

Imported overworld encounters now follow the count and history rules in the
original disassembly rather than preserving individual defeated enemies forever.

## Overworld rules

- Entering a room adds its history ID to a six-entry circular history only if
  that ID is absent. Revisiting an existing entry does not refresh its position.
- A fully cleared room stays empty while its ID remains in the history. After
  eviction, entering it restores its full population and resets its kill record.
- Partial kill counts survive even outside the history. Returning recreates the
  original encounter with its population reduced by that count.
- These are counts, not identities: the first N spawn definitions are recreated.
  The particular enemy killed previously may reappear while another slot is absent.
- An overworld kill counts when the death animation completes. Leaving sooner
  recreates that enemy on return. Surviving enemies regain their defined health
  and spawn position each time the room is rebuilt.
- The starting sword cave shares history ID `ow_77` with its parent screen. Cave
  visits do not consume another slot or refresh the parent's insertion position.

These rules follow `Z_05.asm`, `ModifyObjCountByHistoryOW` and `SaveKillCountOW`,
and `Z_07.asm`, `RunCrossRoomTasksAndBeginUpdateMode` and `UpdateMetaObjectEnd`.
Population selection occurs before the newly entered room is added to history.

## What survives leaving a room

| State | Behavior |
| --- | --- |
| Inventory, equipped sword, health, rupees | Retained and saved |
| Collected cave gift and disappearance of its old man | Permanent collected flag; retained and saved |
| Enabled progression flags | Retained and saved independently of enemy history |
| Overworld enemy kills | Count and clear state governed by six-entry history |
| Remaining enemy health, positions, and shooting state | Rebuilt on re-entry |
| Loose drops, rocks, and sword beams | Removed on departure |
| Uncollected cave dialogue | Restarts on re-entry |

Bombed walls, burned bushes, pushed blocks, dungeon doors, and dungeon-specific
respawning are not implemented yet. Their future persistence must follow their
own source rules; they are not implicitly handled by the enemy-history model.

## Editable content policies

`RoomDefinition.enemy_persistence` supports:

- `overworld`: the original count/history behavior, selected by imported rooms.
- `permanent`: preserve exact defeated spawn IDs, the default for native custom
  encounters and a useful option for unique enemies.
- `reset`: recreate all enemies on every entry.

`history_id` optionally shares an entry with another room, as caves do with their
parent. `tracks_history = false` excludes a custom room from history insertion.
The history is circular insertion order, not least-recently-used order.

Counts and a separate `cleared` boolean replace the NES three-bit all-cleared
sentinel. This preserves the imported rooms' behavior while allowing expanded
rooms with more than six enemies without treating seven partial kills as a clear.

Dungeon kill-count packing, non-recurring dungeon templates, level-change history
resets, and the original death/continue flow remain future work. Current runtime
history begins empty rather than reproducing the NES's zero-filled room-00 slots.

## Saves and compatibility

Save format version 2 stores room history, insertion cursor, and kill records.
An in-room save includes completed kills without committing them twice. Loading
restores that state before creating the room, and discards unsaved encounter state.
History persists across native save/load; this is the project's checkpoint behavior,
not a claim to reproduce the original NES save-file contents.

Version 1 saves load automatically. Known old per-enemy overworld flags convert
once to counts, while permanent custom defeats and collected items remain intact.
Older saves have no history to reconstruct: the current room establishes the first
entry, and other fully cleared rooms can therefore be eligible to respawn on their
next visit. A fully cleared current room remains cleared when its checkpoint loads.
Writing again produces version 2; the previous valid file remains the backup.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/room_persistence.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/save_load.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/run.gd
```

The focused suite checks insertion and eviction, no refresh on revisits, partial
counts, full clears, cave grouping, permanent progression, transient objects,
wounded enemies, unfinished deaths, all three policies, rooms with nine enemies,
full-ring and in-room checkpoint restoration, migration, and invalid save records.
It runs without a ROM; imported-room metadata is checked when available.
