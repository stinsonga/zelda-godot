# Individual placements

The Room tab opens with **Select** active. Click an enemy, pickup or player spawn,
or choose it in the PLACEMENTS list. Alt-click cycles through overlapping objects.
Selection does not modify the document.

Drag to preview a move, then release to commit it. Movement uses 8-pixel steps
relative to the original position. Red previews indicate blocked or out-of-room
positions; releasing there leaves the original untouched. Each drag is one undo
step. With the canvas focused, arrows move 8 pixels, Shift-arrows move 1 pixel,
Escape clears selection, Delete/Backspace deletes, and Command/Ctrl-D duplicates.
Keyboard commands do not capture typing in inspector fields.

The inspector accepts exact pixel coordinates. **Snap position** aligns X to a
multiple of 8 and Y to 5 modulo 8 (the standing-foot offset). Positions must have
walkable ground under both foot probes. Exact off-grid positions remain legal,
but the progression solver may decline geometry outside its supported grid.

Enemy controls choose an existing variant or edit title, behavior, health, speed
(in 1/256-pixel units) and contact damage (half hearts). Apply affects the selected
placement. If its chosen definition is shared, changed stats create a new variant
and copy its local sprite selection. An unshared definition is updated in place.
The older enemy brush settings still edit a definition for all of its users.

Pickup controls choose an item, room-clear requirement and objective membership.
Secret visibility after a block push is also available; see [PUSH_BLOCKS.md](PUSH_BLOCKS.md).
Enabling these features upgrades a v1 pack to v2. Moving or changing an item
preserves its stable placement ID and objective reference. Deleting removes its
objective reference; Undo restores both. A duplicate gets a fresh ID and nearby
free position, and does not become an objective automatically. Room placement
limits still apply. Player spawn cannot be deleted or duplicated.

Properties apply together as one undo step. Reset fields reloads saved document
values without undoing other edits. Selection is cleared on room, document or tool
changes. Placement IDs remain read-only; save-ID migration is future work.

All controls work without ROM assets. Optional local art continues to resolve
through the separate appearance overlay; shared pack JSON contains no graphics.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/placements.gd --log-file /tmp/placements.log
```

The suite exercises real editor and canvas methods: selection without dirtying,
unchanged JSON-loaded properties, drag previews, one-step undo, invalid/stale
movement, keyboard nudges, isolated stats, duplication, pickup objectives and
restoration after deletion.
