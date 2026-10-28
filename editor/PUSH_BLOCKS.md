# Push blocks and room secrets

One directional dungeon block per room is supported in authored packs, playtests,
templates and progression checking. It uses the existing game secret runtime.
No ROM or imported graphics are needed.

## Try the example

Open `content/packs/block_vault.json` in the editor, then **Play dungeon**.
Defeat the guard and push the block right. The block reveals a key and opens the
north shutter. The key opens the next room's east door; collect the reward to
complete the dungeon. **Dungeon → Check progression** reports a witness route.

## Author a puzzle

1. Choose a direction and reveal mode under **PUSH BLOCK / SECRET**.
2. Choose **Block** and click a room cell, or enter cell X/Y and press
   **Apply block secret**. B marks the starting square; its line and outlined
   square show the push direction and landing square. Base terrain stays floor.
3. For **shutters**, connect rooms with shutter doors. The room switches to
   trigger 4: defeating enemies alone cannot open its shutters. **item** leaves
   the ordinary room shutter setting available.
4. Select a pickup and enable **Appears after block push**, then Apply. Both
   reveal modes can expose pickups. A secret-gated pickup can sit under the
   starting block, or elsewhere in the room. Objective membership is independent.
5. Check progression, save, and playtest. Reachability of the push approach is a
   progression question; structural validation alone cannot prove it reachable.

Select-click B to focus its inspector. Alt-click allows selecting a pickup under
it through the placement list/hit cycling. The block has dedicated cell controls;
it is not part of the individual entity drag tool. Right-click with Block removes
the room's block. **Remove block secret** also removes pickup secret requirements
and resets block-controlled shutters to the clear-enemies setting. Undo restores
all of these changes together. One brush stroke is one undo step.

Block, landing and approach must be floor cells inside the two-tile wall frame.
The block cannot cover a player/enemy spawn or an ordinary visible pickup.
Secret-gated pickups may overlap its starting square. A pickup placed under the
landing square may be inaccessible; the solver checks the resulting collision.

## Runtime and persistence

All enemies that count for room clearing must be defeated before a push. Link
must stand against the chosen side and push for 16 ticks; the block then slides
one 16-pixel tile using the existing runtime timing. Other sides do not push it.
The block, reveal state and block shutters reset on every room entry. Collected
pickups and opened key/bomb doors retain their existing persistence rules.

Original game resources retain their existing any-direction block behavior.
The directional restriction is opt-in through `SecretDefinition.block_direction`.
Authored packs use placeholder block graphics over optional room art; choosing
separate custom block sprites/atlas cells is future graphics-library work.

## Data and templates

The additions are optional version-2 fields:

```json
{
  "secret": {"cell": [6, 5], "direction": "right", "reveal": "shutters"},
  "shutter_trigger": 4
}
```

Pickup `requires_secret: true` gates its visibility and collection. No persistent
reveal flags, arbitrary scripts or asset paths are stored in shared JSON. Existing
v1/v2 packs without block fields behave as before. Authoring a block upgrades v1.

Template capture preserves the block and secret-gated pickups. When generation
adds its progression pickups to an **item**-reveal template, those new pickups
also require the block push. Their default placement is still checked: a template
whose block covers a needed reward or cuts off an exit must fail verification.
The generator does not move rewards to conceal an impossible puzzle.

## Solver scope and checks

The search tracks each room visit's push state, moves solid collision to the
landing square, requires a clearable encounter and reachable push approach,
opens trigger-4 shutters, and gates secret pickups. It resets push state when
traveling to another room. Witness routes include explicit push events.
Combat remains an assumption; this is not a survival or timing proof. Other secret
types, hidden stairs, cellars, caves and persistent block arrangements are not
supported in authored pack data yet and cannot receive a solvability claim.

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/blocks.gd --log-file /tmp/block-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/authored_blocks.gd --log-file /tmp/block-native.log
```

The editor suite checks every direction/reveal pair, JSON validation, blocked
approaches, combat prerequisites, collision, templates/generation, undo, and
removal dependencies. The native suite replays solver routes using actual player
movement, pushes, pickups, key locks and transitions, including a generated puzzle
template. It also checks wrong-side pushing and reset on re-entry.
