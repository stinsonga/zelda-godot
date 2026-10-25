# Cave, pickup, and sword foundation

With locally imported content, walk into the opening in the starting room's
upper-left cliff. Link enters the cave, walks 48 pixels inward, and waits for
the old man's message. Touch the gift to collect the wooden sword. Leave through
the bottom opening. Press **Z** or **Space** to use the sword.

Sword ownership and collected gifts persist across rooms. Use F5 to save and F9
to restore them after restarting. R resets position only, without clearing items.
See [save/load behavior](SAVING.md).

## Content model

All following resources can be edited in Godot's Inspector:

- `PortalDefinition`: trigger rectangle in room-local coordinates, required
  direction, destination ID and position, arrival facing, and automatic entry
  walking distance. A destination must exist in the world's room list.
- `PickupDefinition`: stable pickup ID within the room, item resource, position,
  collection tolerance, and lifting duration. Collected state uses `room_id/id`
  and is stored separately from the resource.
- `WeaponDefinition`: stable item ID, name, damage, phase durations, and sword
  positioning offsets. The native wooden-sword definition lives in `content/`;
  its visual assets remain in the local `imported/` theme.
- `DecorationDefinition`: named sprite, optional animation frames, blocking
  rectangle, and optional pickup ID that causes it to disappear.
- `RoomDefinition`: portal, pickup, and decoration arrays, plus dialogue and an
  optional pickup ID that suppresses the message after collection.

`GameState` owns inventory and collected flags. `SwordAction` owns attack phase,
locked facing, visibility, and a prospective hitbox. `World` connects those to
input, movement, rendering, and room transitions.

To create a custom cave, privately copy an imported room or start with a new
hand-authored room, then configure these resources. Add it to a copied world
resource and link a portal to its stable ID. For public content, use your own
art and text; keep copies of imported material inside the local asset boundary.
See [asset boundary](ASSET_BOUNDARY.md).

## Source references and fidelity

- `Z_01.asm`, `InitModeB_EnterCave_Bank5`: original entry X `$70`, Y `$DD`,
  and a 48-pixel automatic walk upward. Coordinates here subtract the 64-pixel HUD.
- `Z_01.asm`, `UpdatePersonState_Textbox`: six ticks between characters.
  Text is decoded from the ROM into an ignored resource, not embedded in scripts.
- `Z_01.asm`, `DrawCaveItems` and `UpdateCavePersonState_TalkOrShopOrDoorCharge`:
  gift at X `$78`, Y `$98`; pickup requires matching X and Y distance below six.
- `Z_04.asm`, `UpdateStandingFire`: the complete fire sprite alternates
  horizontal flipping every six ticks; it does not advance to the next frame tile.
- `Z_01.asm`, `TakeItem`; `Z_07.asm`, `CheckLiftItem`: 128-frame lifting pose.
- `Z_05.asm`, `WieldSword`; `Z_07.asm`, `UpdateSwordOrRod`: phase durations
  5, 8, 1, 1, 1; weapon visible in phases 2 through 4.
- `Z_07.asm`, `PlayerToWeaponOffsetsX/Y`: original sword positioning tables.
- `Z_01.asm`, `CheckMonsterSwordCollision`: only the fully extended second
  phase is damaging. `SwordAction` exposes this interval for future enemies.
- `Z_02.asm`, `TransferCommonPatterns`; `Z_01.asm`, `TransferDemoPatterns`:
  the initial demo patterns supply persistent sprites such as the horizontal
  sword and lift pose before the overworld-specific pattern block replaces them.

This is a functional baseline, not a frame-perfect full-game port. Fades and the
slow outdoor cave exit walk remain immediate transitions. Special untimed text
spaces are rendered as ordinary spaces, so message duration is approximate.
Cave decoration collision uses explicit content rectangles. Sound, fire damage, shops, and other cave types are not implemented
yet. Sword damage now connects to Octorok encounters. HUD sword ownership, health,
and currency are live. See [combat and rewards](COMBAT.md).

## Verification

`tests/run.gd` walks into the cave from the starting screen, verifies automatic
entry and dialogue blocking, collects the sword, checks the lifting lock and all
attack phase durations, exits, and revisits to verify the gift cannot be claimed
again. Earlier movement and bush-collision checks remain in the same suite.

`tests/visual_preview.gd` can render deterministic `cave`, `lift`, and `sword`
views using Godot's movie capture mode, for example:

```sh
godot --path . --script res://tests/visual_preview.gd --write-movie /tmp/cave.png --quit-after 3 -- cave
```
