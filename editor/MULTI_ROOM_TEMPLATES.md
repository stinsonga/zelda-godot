# Room-and-cellar templates

A reusable template can now contain a primary dungeon room and up to three cellar
annexes connected by stairs. Generation gives every occurrence its own room IDs,
rewrites all internal stair destinations, and can place its progression reward in
an annex. The result is ordinary editable room data; the game needs no separate
procedural-room runtime.

## Try generated cellars

In **Dungeon → Generate…**, browse to
`content/templates/cellar_templates.json`, choose seed **42**, **6 primary rooms**,
and **blue_candle**, then **Generate and verify**. This ROM-free library requires a
key cellar and a goal cellar. The key must be fetched and brought back before the
first lock; the final objective is inside another instance's cellar. The report
includes the actual stair/push/pickup route. Use the dungeon and playtest normally.

The original `dungeon_templates.json` library remains available for ordinary room
generation. Its version-1 seed-42 recipe is covered by a compatibility checksum.

## Capture your own unit

1. Select the primary room and open **Dungeon → Save template…**.
2. Enable **Include linked cellar rooms**. Capture follows outgoing stairs,
   including nested cellar stairs and return links, up to three annexes. The
   dialog lists the number of rooms and available reward-room IDs.
3. Choose a unique template ID, role, external door ports and incoming item
   requirements. Door ports belong to the primary room.
4. Enable **Choose generated reward location**, choose a room, and set its pixel
   coordinates. Selecting a cellar initializes the position from its walkable
   spawn. Without an override, generated rewards use `(120,77)` in the primary.
5. Save a derived library. Existing entries are retained; duplicate template IDs
   are rejected. You can choose that library for generation afterward.

Capture copies terrain, blocks, stairs, enemies, pickups and settings. It removes
primary-room door connections and generation tags, normalizes local map positions,
and namespaces enemy definitions throughout the unit. It copies no local ROM art
or pack objective list. Existing pickups remain; the generator adds its recipe's
key/item/goal rewards independently. Remove unwanted demonstration pickups before
capture if they would grant items early or duplicate generated rewards.

Every stair destination must stay inside the unit. Linked destinations must be
marked `kind: "cellar"` and have no door connections; capture rejects external
main rooms or cellar door links rather than copying part of another dungeon.
Select the primary room when capturing a cellar network. Unreachable annexes,
dangling targets, overlapping local map cells, invalid arrivals and malformed
reward positions are rejected. Capture validates structure; the generator's
progression search still decides whether a particular puzzle is completable.

## Generation and rewards

The requested **6..16 primary rooms** still form the critical path and branches.
Annexes are additional rooms, bounded by **32 total rooms**, the solver's limit.
An oversized expansion fails clearly; it is not truncated. Annex map positions
use the nearest available cells with a fixed tie order and consume no PRNG values.
Map coordinates are a display arrangement; stair links need not be adjacent.

IDs look like `room_1`, `room_1_cellar_1`, and `room_1_cellar_2`. A second occurrence
uses its own prefix. Room-local enemy/pickup/stair IDs remain intact; saved state
and objectives distinguish them through their newly assigned room ID. Mutable
room dictionaries are copied, so editing one occurrence does not edit another or
the source template.

The reward override applies to automatic pickups assigned to that primary role:
progression keys, required items, bomb supplies and objective rewards. Roles that
receive no automatic pickup do not invent one. Goal references name the actual
reward room, including an annex. The existing room-clear and item-reveal block
rules apply in the chosen reward room. Invalid or unreachable rewards fail
validation or verification; generation does not move them to hide a broken puzzle.

The solver already models blocks, item gates, finite keys/bombs, forced stairs and
arrival suppression. The same witness events are replayed through native game
movement in tests, including nested cellar traversal. Combat remains the documented
sword-vulnerable encounter assumption, not a survival proof.

## Library format and compatibility

Format 1 stays readable. Format 2 adds optional `annexes` (one to three ordinary
cellar room objects) and an optional reward reference:

```json
{
  "reward": {"room": "local_cellar_id", "position": [120, 125]}
}
```

`room` remains the primary room field. All stair targets and the
reward-room reference use template-local IDs before instantiation. All six roles,
weights, item requirements and primary door ports retain their existing meaning.
A format-2 library may mix ordinary templates and multi-room units.

Without residents, format-1 libraries retain generation algorithm version 1 and format-2 libraries use
version 2. Libraries containing residents use recipe version 3 and a separate
world ID prefix; bomb/fire libraries use version 4. See
[RESIDENT_PROGRESSION.md](RESIDENT_PROGRESSION.md) and
[DESTRUCTIBLE_SECRETS.md](DESTRUCTIBLE_SECRETS.md). Provenance `room_count` records primary rooms; the result report shows
primary and total counts. The library fingerprint includes annex geometry, links,
rewards, weights and order. Fingerprints normalize string-key types and integral
JSON numbers, so saving/reloading a library preserves the seed result and world
identity. Source pack IDs and local art overlays do not become generated assets.

Limits for this pass: up to three cellar annexes per template, stairs as internal
connections, and a single automatic reward location per unit. Arbitrary dungeon
room groups, internal door networks, multiple floors, loops between generated
units, rotated templates and dependency planning remain future work.

## Verification

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/multi_templates.gd --log-file /tmp/multi-room-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/generated_cellars.gd --log-file /tmp/multi-room-native.log
```

On a fresh checkout, first run Godot's headless editor import to register game
classes, as described in [STAIRS.md](STAIRS.md). Checks cover capture isolation,
all internal target remapping, nested units, reward placement, JSON determinism,
legacy recipe compatibility, room limits, impossible return routes, GUI capture,
library append without a filename extension, and minimum-size dialog layout.
