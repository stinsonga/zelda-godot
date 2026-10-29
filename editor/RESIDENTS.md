# Authored cave residents

The editor supports hint residents, one-time item gifts and shops using the
existing game cave-session system. Rooms and dialogue are authored data; no ROM
or original dialogue is required.

## Try the example

Open `content/packs/resident_village.json`, then **Play dungeon**. Collect the
entrance coins and visit the three stair links: a hint, a bow gift and a key shop.
The key costs 20 rupees; the entrance provides enough coins. Wait for each greeting
and walk into a displayed item to take or buy it. This is a free-exploration
example with no completion objective.

## Create or edit a cave

Use **STAIRS / CELLAR LINKS → Create linked cave** from the entrance room. It
creates a floor room with a default hint resident, an entrance stair and a return
stair as one undo step. Hidden entrance stairs can use the entrance room's block
secret. Select the new cave room, then edit **CAVE / RESIDENT**.

You can also apply a resident to an existing compatible room. Select its mode,
enter dialogue, choose up to three ware slots and prices, then **Apply resident**.
Changing mode seeds appropriate default wares; those changes stay in the inspector
until Apply. **Reset resident fields** reloads document values. Choose **none** and
Apply to remove a resident. Changes participate in undo/redo, and unchanged Apply
is a no-op after JSON loading. Select-click the orange N on the canvas to inspect.

- **hint:** greeting only, no wares; remains on future visits.
- **gift:** exactly one free item. Taking it starts the native overhead lift and
  fanfare. The taken state survives room visits and normal game saves; the resident
  stays gone afterward.
- **shop:** one to three wares, each priced 0..255 rupees. Insufficient funds do
  nothing. A successful purchase grants the item and drains exactly its price
  through the native rupee counter. Only one purchase is allowed per visit; leaving
  and returning reopens the shop. A zero price is a free, repeatable shop offer.

Gifts and shops use the same supported item list as room pickups. Ware locations
are fixed at X 88/120/152, Y 88, matching the native cave system. Dialogue supports
three lines of 24 printable ASCII characters. `_` is a space with no typing delay;
ordinary spaces retain native typing timing. Presets and sample dialogue are new.

## Geometry, identity and visuals

Resident rooms cannot contain regular enemies or block secrets in this pass.
Place a secret on the parent entrance room instead. Ware approaches need floor.
The native resident barrier stops upward movement above Link Y 77 while the
resident is present, so return stairs must be at row 5 or below. Created cave
returns use cell `(3,7)`; arrival in the cave is `(120,125)`. Upper/north routes may
be inaccessible while a resident remains. The editor validates stair placement
against this barrier. The original game behavior is unchanged.

Resident transactions reserve the room-local collection ID `taken`; a floor pickup
in that room cannot use that ID. Gift identity follows the room ID, so changing a
gift inside an already-taken room does not reset existing saves. General content-ID
migration remains future work.

The resident currently uses an orange placeholder character and the game's item
rendering. Local enemy art does not silently assign a resident sprite. Authored
cave entrances use stair/portal links; original overworld cave doorway walks and
rising animations are not added here. `kind: "cave"` labels the authored room.

## Shared data and progression limits

An optional version-2 room field:

```json
{
  "resident": {
    "mode": "shop",
    "text": "SUPPLIES FOR YOUR ROAD.",
    "wares": [null, {"item": "key", "price": 20}, null]
  }
}
```

Exactly three slots are required; `null` means empty. The adapter constructs
`CaveDefinition` and `CaveWare` resources. No scripts, resource paths or ROM art
are accepted in this data. Existing packs without residents behave as before.

**Progression certification is not available for resident packs yet.** The solver
explicitly reports unsupported rather than assuming gifts or purchases are free
progression pickups. Price timing, wallets, repeat purchases, gift choices and
resident collection flags need their own search model. Ordinary validation and
game playtests remain available. Ware transactions cannot be named as pickup
objectives in this pass. Cave networks are also outside the current cellar-only
multi-room template capture scope.

Future resident features include paid hints, money games, charges, heart
requirements, letter/bait interactions, alternative portraits and cave entrance
animations. The original game runtime supports several of these; editor authoring
and progression rules are separate remaining work.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/residents.gd --log-file /tmp/resident-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/authored_residents.gd --log-file /tmp/resident-game.log
```

Fresh source-only copies need the normal Godot editor import before native tests
so game classes are registered. Checks cover malformed data, JSON round trips,
undo, linked cave creation, barrier-safe return stairs, literal hint text, one-time
gifts with native lifts, affordability, exact shop charges and repeat visits.
