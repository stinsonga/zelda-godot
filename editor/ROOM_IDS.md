# Renaming room IDs

Select a room, edit **Room ID**, then click **Rename room ID** or press Enter.
Use 1–64 lowercase letters, digits, underscores or hyphens. Changing a room title
only changes its display name. Save the pack after renaming, then restart an
existing preview to use the saved content.

A rename updates the room itself, the start room, door and stair destinations,
objectives, shared room graphics, private ROM room bindings, and generation
metadata (template records and loop endpoints). It is one undoable action;
undo/redo also restores the selected room and placement. Version-1 packs upgrade
to version 2 when a room is renamed.

## Compatibility history

Version-2 packs may contain a `room_aliases` object:

```json
"room_aliases": {
  "entry": "landing",
  "old_hall": "hall",
  "removed_room": ""
}
```

Each old name points directly to a live room. Repeated renames update all earlier
aliases, so chains and cycles are not allowed. An empty target records a deleted
room. Deleting a room retires its ID and any earlier aliases to it. Historical
names cannot be reused, including by the new-room and duplicate-room actions;
otherwise an old save could attach progress to an unrelated room. The pack
allows at most 1,024 history entries. Keep this history with the shared pack in
version control and in distributed updates.

Private appearance files remain separate. Renaming moves the active room's local
binding; loading an older overlay resolves its aliases in memory. Current-name
bindings win if both exist, and bindings for retired rooms are discarded. Loading
alone does not rewrite an overlay or copy ROM references into shared content.

## Existing checkpoints

Pack identity and the checkpoint filename stay unchanged. Loading maps the saved
room, collected pickup and cave-transaction keys, defeated enemy keys, known
room-scoped flags (doors, secrets, shutters and visits), room history and kill
records to current room IDs. Placement IDs within a room do not change. Global
and unknown flag namespaces remain untouched.

If old and current references coexist, boolean progress is deduplicated. Kill
records retain the larger kill count and either cleared flag. Room history keeps
the most recent occurrence when aliases merge entries, preserving the history
ring's chronological order.

Migration validates the result, including field and file-size limits, before
replacing the live session. A checkpoint located in a deleted room fails safely;
it is not moved to an arbitrary room. Historical progress for deleted rooms can
remain in a checkpoint, but reserved names prevent it from applying to new rooms.
Existing saved-position checks still apply when terrain changes.

Loading does not rewrite files. The next explicit save writes current room IDs
and preserves the previous valid snapshot as its normal backup. Versions 1 and 2
of checkpoints also migrate through the current version-3 save loader. Backups
using earlier room names remain usable with the pack's alias history.

## Scope

This migration is forward-only: an older pack does not know names introduced by
a newer pack. Give independent worlds different pack IDs. Placement, enemy-variant
and pack-ID renames are covered below.

Generation metadata follows a rename, but regenerating a recipe rebuilds its
base content; it does not replay manual renames or preserve their migration
history. Preserve that history when updating the same world, or use a distinct
pack ID for independently regenerated content.

## Placements, enemy variants and the pack

**Placements.** Select a pickup or enemy, edit its ID in the placement panel and
click **Rename ID** (or press Enter). Objectives follow. Saves record collected
pickups and defeated enemies as `room/placement`, so the pack keeps a flat
history in `placement_aliases`:

```json
"placement_aliases": {
  "pickups": {"relay/item_1": "relay/ember"},
  "enemies": {"room_1/enemy_1": "room_1/sentry", "room_1/enemy_2": ""}
}
```

Targets stay in the same room; an empty target marks a deleted placement. As
with rooms, historical IDs are reserved in their room, including by new and
duplicated placements. Renaming a room carries its placement history along;
deleting a room drops it (the room ID itself stays reserved). Loading an old
checkpoint maps room IDs first, then exact placement keys; other keys are
untouched.

**Enemy variants.** Enter a new ID beside **Rename variant** in the enemy-variant
section. Placements, shared and private enemy art follow. Saves record
placements, not variants, so no history is kept.

**The pack.** Changing the pack ID and saving records the ID it was last opened
or saved under in `previous_ids`. The game then loads checkpoints and front-end
files written under an earlier ID when the current ID has none (the most recent
earlier ID first) and writes the next save under the current ID. A bundle's file
slots stay in the folder of its earlier ID until the new one has its own. A
private appearance file is keyed by pack ID; save once under the new ID to
write it there.

**Items** are the engine's fixed item names, not authored IDs, so there is
nothing to rename.

Checks: `editor/tests/content_ids.gd` (references, history, reservation, GUI
rename/undo/delete, identity on save) and `tests/content_id_saves.gd` (a real
checkpoint across placement, room and pack renames).

Checks: `editor/tests/room_renaming.gd` covers pack references, private overlays,
GUI undo/redo and reserved names. `tests/room_rename_saves.gd` exercises real
checkpoint files, repeated renames, old save versions, backups, persistent
progress, history collisions and safe migration failures without ROM data.
