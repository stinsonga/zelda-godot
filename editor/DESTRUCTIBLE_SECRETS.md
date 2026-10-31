# Bombable and burnable room secrets

Authored rooms support bomb and fire secrets alongside existing push blocks.
The native bomb fuse, candle flight/burnout, reveal flags and collision are used;
no second item simulation or ROM assets are introduced.

## Try the examples

- Open `content/packs/bomb_route.json`: reveal the object with one bomb, visit the
  bow room and return, then use the remaining three bombs on the route's doors.
  Re-entry must keep the secret open; only four bombs are supplied.
- Open `content/packs/fire_route.json`: obtain the candle from the cave resident,
  return and burn the object to expose the objective.
- Generate from `content/templates/destructible_templates.json`, seed 42 and six
  primary rooms. A supplied bomb reveals the key room's generated reward.

Use **Dungeon → Check progression** and **Play dungeon**. The route report includes
an explicit bomb/fire reveal event and its configured item-use position.

## Author a secret

The Room tab's **Secret** brush replaces the old Block button label. Under
**ROOM SECRET**, choose **block**, **bomb** or **fire**, choose a cell, direction
and reveal mode, then Apply or paint with the brush. Select-click an object to
inspect it; overlap selection remains available through entity/stair lists.

One secret is supported per room:

- **block** retains its existing behavior: clear enemies, push one tile, reset
  on room entry. Old data without a trigger still means block.
- **bomb** places a solid object that disappears on a native detonation. The
  certified use point is one tile behind the chosen direction and costs one bomb.
- **fire** places a solid object that disappears when a standing candle fire is
  about to burn out. Stand two tiles behind the chosen direction: fire starts
  one tile ahead, then travels another tile. A blue candle is required.

B marks a push block, X a bomb object and F a burnable object. For push blocks the
outlined square is the landing; for bomb/fire secrets it is Link's item-use stance.
Direction selects a verified approach/facing, not a restriction on the native
explosion/fire collision: other player positions may also reveal an object.

Choose **item** to expose floor and secret-gated rewards or stairs. Mark a pickup
**Appears after room secret** or a stair **Hidden until room secret**. Either can
sit on the object's square or elsewhere in the room. **shutters** also switches
the room to trigger 4, opening shutters on reveal. Bomb/fire reveal itself does
not require enemies to be defeated; a separate room-clear pickup requirement still
applies when selected.

Painting a bomb/fire secret on an interior Wall cell changes the base cell to
floor beneath its solid secret overlay. This makes the obstacle disappear cleanly.
Undo restores the previous wall and secret data together. Floor placement also
works. Water is not converted. Cells and the configured stance must lie inside
the standard wall frame and have usable base floor. Use existing bombable **doors**
for wall-frame exits; this feature authors interior destructible objects.

Removing a secret exposes its underlying floor, clears dependent secret requirements
and restores clear-enemies shutters. Paint Wall afterward if a permanent wall is
wanted. Undo restores the full previous setup. Resident interiors still forbid
secrets: put a hidden cave entrance in the parent room instead.

## Persistence and visuals

Bomb/fire reveals persist across room visits and normal saves using the existing
`secret/<room-id>` flag. Revealed objects stay walkable, and hidden entrances,
rewards and secret shutters remain available. Push blocks retain their existing
reset behavior. The native blue candle remains once per room; a miss can be retried
after leaving and returning. The solver reserves that use for the secret.

Reveal identity follows the room ID. Editing a secret in an already-revealed room
does not reset an existing saved flag; fresh playtests start from fresh state.
Shared data contains no art paths. Objects currently use placeholder graphics;
custom object/tree/wall sprite selection is future graphics-library work. Imported
original secrets retain their atlas art and existing behavior.

## Data and generation

An optional trigger on the existing version-2 room secret:

```json
{
  "secret": {
    "trigger": "bomb",
    "cell": [6, 5],
    "direction": "right",
    "reveal": "item"
  }
}
```

Accepted triggers are block/bomb/fire; omission preserves block compatibility.
Templates and linked-cellar capture retain the trigger. Libraries containing
bomb/fire secrets use generator recipe **version 4** and `generated_v4_...` IDs,
including libraries that also contain residents. Other libraries retain their
existing versions 1/2/3 and world identities.

The solver tracks persistent reveals independently for every room occurrence,
removes destroyed collision, spends one bomb or requires candle ownership, and
restores remembered collision on stair/door re-entry. A key/item hidden behind its
own required trigger cannot certify a route. The configured approach must be
reachable. This is a conservative proof through that stance, not an exhaustive
search of every possible blast position.

Other existing limits remain: combat/survival are not frame-level proofs, other
secret types remain unsupported, and bomb shops cannot be mixed with finite bomb supplies in a certified pack.
Shop-only bomb supply and a resident-gifted candle are supported and replayed.
See [RESIDENT_PROGRESSION.md](RESIDENT_PROGRESSION.md) for the economy assumptions.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/destructible.gd --log-file /tmp/secret-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/destructible_secrets.gd --log-file /tmp/secret-native.log
```

Checks cover every direction/reveal mode, real B-button bombs and candles, hidden
stairs, exact bomb use, blue-candle limits, persistent returns through cleared
collision, unavailable/self-locked resources, gift/shop integration, wall painting
and undo, JSON round trips, malformed input, templates and generated routes. Fresh
source-only copies require the normal Godot editor import before native tests.
