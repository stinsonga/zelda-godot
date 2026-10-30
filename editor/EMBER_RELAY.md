# Ember Relay: editor usability playtest

A small original dungeon authored through Dungeon Workshop's GUI, saved as
`content/packs/ember_relay.json`. It contains no imported graphics, maps or text
and uses the game's ROM-free placeholder theme. It is intended as a short
end-to-end authoring example, not a finished game or combat balance benchmark.

## Open and play

Launch `godot --path editor`, choose **Open**, and select the pack. Use
**Play dungeon** to start at Key Landing. Movement is arrows/WASD, sword is
Z/Space, and the item menu is Enter. Closing the preview returns to the editor.

From the repository root, a direct preview is also available:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tools/play_authored_pack.gd -- --pack content/packs/ember_relay.json --no-local-art
```

## Route

| Room | Purpose |
| --- | --- |
| Key Landing | Collect the key. Stairs in the lower-right lead to the store. |
| Lower Store | Follow the left corridor down and take the bow, then return upstairs. |
| Watchpost | Use the key to enter from the south. Defeat both guards. Its east shutter also requires owning the bow. |
| Relay Chamber | Approach the central block from the left and push it right. Collect the revealed rupee objective. |

The bow is an inventory requirement on the east door; shooting an arrow is not
required. The rupee stands in for the final objective. Pickups and stable IDs are
ordinary editable pack data, and the four rooms can be modified or reused.

## What was exercised

The dungeon was created from **New**, using pack naming/ID fields, painting,
adjacent-room creation, reciprocal door editing, enemy placement, one-click
linked-cellar creation, item selection, room naming, a push secret, individual
pickup settings and an objective. It was saved, reopened, and launched from
**Play dungeon**. **Dungeon → Check progression** returned SOLVED.

The native replay then followed the witness through actual game movement,
stairs, pickups, doors and block interactions to the completion flag. As in the
solver model, sword-vulnerable encounters are assumed winnable: the replay applies
sword hits and protects the player. It does not establish combat difficulty or
prove recovery after arbitrary player mistakes. GUI launch/display were checked;
continuous movement was verified by the native simulation replay rather than a
complete manually played fight.

## Usability fixes from this pass

- Full secret, stair and resident forms previously buried basic room and brush
  controls. They now live behind **Secret / Stairs / Resident** toggles in the
  sidebar, with one optional form open at a time.
- The Secret and Stairs brushes reveal their settings automatically. Clicking a
  secret, stair or resident in Select mode reveals its corresponding inspector.
- Switching tools no longer leaves the sidebar at an unrelated scroll position.
  Enemy/Pickup bring their selectors into view; basic terrain tools return to
  the compact inspector's top. These are view changes, separate from pack undo.
- The editor README's old statements about missing authored graphics were
  corrected to match the implemented libraries and animation controls.

## Remaining friction and limits

- Stable room and placement IDs are automatically assigned; safe renaming and
  save/reference migration are still future work.
- The long connection/objective and detailed feature forms still require some
  scrolling. The compact inspector removes the unused forms, not every scroll.
- Painting a pickup over a block can temporarily invalidate the document. Select
  that pickup in the placement list, enable **Appears after room secret**, and
  Apply. The example exercises that workflow.
- The native placeholder preview retains its lab-style HUD and restart behavior.
  Standalone authored-game packaging/menu and content-specific presentation are
  separate remaining work.

## Verification

```sh
godot --headless --path editor --script res://tests/workshop_usability.gd
godot --headless --path . --script res://tests/ember_relay.gd
```

The first checks inspector visibility, tool scrolling and document isolation.
The second loads the shipped GUI-authored pack, solves it, and replays the route
through the native engine. Neither check requires a ROM.
