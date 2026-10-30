# Templates, seeded generation and progression checking

Dungeon Workshop now generates ROM-free dungeons from authored room templates,
then searches inventory and movement states before offering a result. The same
item requirements and starting equipment are enforced by the game adapter.
Generation and progression checking run in a worker thread.

## Generate and play

1. Open the **Dungeon** tab, then **Generate…**.
2. Choose a template-library JSON file. The default is
   `content/templates/dungeon_templates.json`: ten authored rooms/variants for
   start, key, item, combat, treasure and goal roles.
3. Enter an integer seed (0..2147483647), choose 6..16 primary rooms and a required item. Cellar annexes are additional
   rooms, with at most 32 rooms total.
4. Optionally enable **Custom layout** and choose **Branch rooms** and
   **Extra loops**. Off preserves classic recipes. See the layout details below.
5. Click **Generate and verify**. A candidate is offered only when the solver
   finds a route collecting every objective under its stated model. Failures,
   unsupported cases and search limits remain failures/inconclusive; they are
   never silently accepted.
6. Review the route, seed and template SHA256. **Use generated dungeon** loads
   the result as an ordinary editable pack. Unsaved document changes receive the
   usual discard confirmation. Editing recipe fields invalidates the old candidate.
7. Inspect the room map, change rooms or apply local graphics, save the authored
   JSON pack, and **Play dungeon**. A playtest uses unsaved pack data too.

The classic generated layout is a grid tree: a critical path and, for larger dungeons,
side branches. It places a key before the first key lock, the chosen tool before
its item gate, and another key before the final lock. Branches may use bombable
walls; a four-bomb pickup supplies them. Goal-room rewards require clearing that
room. Branch treasure pickups are also objectives, so the successful route must
reach them, rather than certifying only the main path. This is a first generator,
not yet a general procedural puzzle designer or multi-floor generator. Custom
layouts now add configurable branch rooms and gate-preserving loops.

The generated pack contains a recipe: `authored_tree`, algorithm version 1 for
format-1 libraries or version 2 for format-2 libraries; resident-bearing libraries
use version 3 and bomb/fire libraries version 4, each with a separate world ID prefix,
seed, requested size/item, selected template IDs and the library's canonical
SHA256. Its PRNG is an explicit 32-bit LCG, independent of Godot's random-number
implementation. The same algorithm, library contents and recipe reproduce the
same canonical base pack. Time-budget exhaustion stops generation instead of
publishing a later candidate, so CPU speed cannot silently change the seed result.
Changes that can select another candidate require an algorithm-version bump. The hash normalizes dictionary key order and integral JSON
numbers; template array order and weights are significant. Changed libraries
produce different fingerprints and world IDs. Manual edits are preserved in the
saved pack; rerunning the recipe recreates its base, not those later edits.

## Custom branches and loops

Enable **Custom layout** to use graph generation version 5 (`authored_graph`).
Choose **Branch rooms** from zero to `primary rooms - 6`. This counts rooms off
the main route, not the number of separate branches; several may form one branch.
At least six rooms remain on the main route for the existing progression recipe.
Branch rewards remain objectives, including any bombable branches and their
finite supplies. Key/item placement and encounter assumptions are unchanged.

**Extra loops** requests exactly 0–8 additional reciprocal door pairs between
adjacent primary rooms. Each adds one independent cycle. Both templates must
advertise the matching door ports. Cellar stair networks do not count toward this
setting, and general door-connected multi-room templates remain future work.

A loop inherits every permanent-item requirement along the original tree route
between its endpoints. If that route crosses one key or bombable lock, the new
connection receives the same kind of lock. It is a separate door pair: opening
one route does not unlock the other. Routes crossing two consumable locks are
rejected because one door cannot represent both costs. New connections therefore
cannot provide an unguarded crossing around those progression gates.

The solver still checks the entire resulting pack. An exact loop request that
cannot fit the grid, template ports or supported gate costs fails clearly; it is
never silently reduced. Try fewer loops, more rooms or another seed. Generation
keeps the existing 12-attempt and search budgets. SOLVED establishes a route,
not recovery after wasting keys/bombs on alternative locks or every combat choice.

Try the GUI-saved, ROM-free `content/packs/looped_dungeon.json`, or reproduce it:

- Default `content/templates/dungeon_templates.json` library.
- Seed **42**, **8** primary rooms, required item **blue_candle**.
- **Custom layout** on, **2** branch rooms, **1** extra loop.

The map contains a loop through Combat chamber, Item chamber, Treasure chamber
and Goal chamber. Its added shortcut preserves the key lock and candle requirement.
You can save, paint, skin, playtest and modify this pack normally.

For code callers, the optional layout dictionary follows the existing verification
budget argument, so previous calls retain their behavior:

```gdscript
Generator.new().generate(catalog, 42, 8, "blue_candle", 6000,
    {"branch_rooms": 2, "loop_count": 1})
```

With an omitted/empty dictionary, versions 1–4 and their exact seed results are
unchanged. Explicit graph recipes record `branch_rooms`, `loop_count` and
`loop_edges` alongside the existing seed/library/template data. Their distinct
`generated_v5_..._b..._l...` world IDs include the layout settings. A saved recipe
describes the generated base: later manual door edits do not invalidate its
historical loop records. Changing any recipe control invalidates the old candidate;
using a new result marks the document unsaved until it is written to disk.

ROM-free graph checks:

```sh
godot --headless --path editor --script res://tests/graph_generation.gd
godot --headless --path . --script res://tests/generated_graphs.gd
```

They cover deterministic settings/JSON round trips, cycle/branch counts,
independent gate-cut checks, restricted ports, impossible requests, search limits,
legacy compatibility, cellars, GUI controls/save state, and native playthroughs.
The native checks also traverse an actual added key-and-item shortcut. Combat is
assumed winnable as in the other progression replays.

## Author and reuse templates

Edit a room, then **Dungeon → Save template…**. Supply a unique template ID,
role, available door ports and any permanent items needed by incoming connections.
Save a derived library, or append a new entry to an existing library. A new file
starts from the currently selected library, including its existing templates.
Existing template IDs cannot be silently overwritten.

Capture copies authored terrain, spawn, placements and settings. It removes
connections and generation tags, normalizes map position, and namespaces enemy
variants so changing one template cannot alter older definitions. Local ROM
appearance overlays are omitted. Shared authored tile, enemy and room-feature
art is retained, including linked-cellar bindings. Enemy skins follow scoped
variant IDs; room bindings follow generated room IDs. PNGs stay in `content/art/`
and must accompany the template library when shared. The library is ordinary editable JSON under
`content/templates/`; no ROM or imported geometry is needed.

Each library has `format_version: 1` or `2`, an ID, an enemy-definition dictionary and
up to 128 weighted templates. All six roles must be represented. Each template
has an ID, role, positive weight, nonempty `ports`, permanent-item `requires`,
and a primary room document with no connections. Format 2 optionally includes
up to three stair-linked cellar annexes, a generated reward room/position and
per-template `appearance` data using the shared pack art format. Appearance
room IDs are local to that template unit; enemy IDs refer to the catalog’s scoped
definitions. Conflicting skins for one global variant are rejected. Art references
participate in the library fingerprint; recipes without art remain unchanged. See
[MULTI_ROOM_TEMPLATES.md](MULTI_ROOM_TEMPLATES.md). The generator selects templates whose
ports fit their assigned neighbours. Start templates may require only the starting
sword; other unmet dependencies cause candidate rejection. Arbitrary dependency
planning for every user-defined tool is not implemented: the recipe places its
selected tool, and the solver checks the resulting requirements.

## Check or edit progression

For any authored dungeon:

- Place pickups with the ordinary Pickup brush. The picker now includes bow,
  ladder, blue candle, recorder and magical key as well as the original items.
- In the right inspector, select an objective pickup and **Add selected pickup as
  objective**. Add multiple goals if all must be collected; remove them explicitly
  or delete their pickup/room. These controls upgrade a legacy pack to version 2.
- Set the checked **Starting equipment**. The key checkbox gives one key; bombs
  gives four. JSON may specify multiple bundles, subject to validation/model limits.
- Configure a connection's **Required items**, then **Connect both sides**.
  Requirements are reciprocal and apply to all door kinds. An open passage can
  still require possessing a bow, candle, ladder, recorder, sword or magical key.
  This is a generic item gate, not an automatic burnable-tree or water puzzle.
- Open **Dungeon → Check progression…** for the current document snapshot.
  Recheck after editing. Normal Validate still performs structural/layout checks;
  it does not run an expensive solver after every paint stroke.

The solver returns **SOLVED**, **BLOCKED**, **LIMIT**, **UNSUPPORTED** or **INVALID**.
SOLVED includes a witness route and structured events. BLOCKED means no route was
found in the supported model; it is not an emulator-level impossibility claim.
A limit or unsupported mechanic never counts as a proof. The witness is an
existence result: it does not promise recovery after every wrong choice or wasted
bomb. The model assumes the bundled one-key/four-bomb item effects.

## What the solver models

It searches choices of pickups, finite keys/bombs, permanent items and opened
door pairs. Each pickup can be collected only once. A normal key opens a pair
once and is spent; the return side stays open. The magical key bypasses small-key
consumption. Bombable pairs cost one bomb. No farming, shops or random enemy drops
are assumed. Picking up an item cannot substitute for reaching its actual region.

Within each room, the solver floods the eight-pixel player-anchor grid using the
standing-foot and directional probes for coarse authored terrain. It uses standard
door cells and their half-tile masks, checks door-approach hotspots, and verifies
the destination's forced doorway walk. It checks pickup tolerance and whether
required enemies share the reachable region. A mere path through the room graph
is insufficient: isolated keys, walled-off exits and blocked arrivals are detected.

Shutters with trigger 1 can open after a reachable sword-vulnerable encounter;
trigger 0 stays closed. Trigger 4 requires the room's authored block push.
Clear-room rewards likewise require a clearable room, and trigger-4 rooms must
also have their room secret revealed. See [PUSH_BLOCKS.md](PUSH_BLOCKS.md) and
[DESTRUCTIBLE_SECRETS.md](DESTRUCTIBLE_SECRETS.md).
**Combat is an explicit assumption:** reachable vulnerable enemies can be beaten
with a sword, without spending progression supplies. Health, reflexes, precise
combat timing and survival difficulty are not proved. Earlier automatic collection
of non-harmful reachable pickups can only help within the supported supply limits.

Current conservative limits:

- 32 rooms, 48 pickups, 48 paired connections; default 20,000 states and 8 seconds.
- Standard two-tile wall frames and dungeon-grid spawns. Edited boundary bypasses
  and off-grid spawns are reported unsupported.
- Authored stair links and cellar rooms are modeled as forced portal transitions
  with arrival suppression. See [STAIRS.md](STAIRS.md). Enable linked-cellar
  capture for bounded room/cellar units; general room groups and internal door
  networks remain outside template support.
- Residents support gifts, finite coin budgets, shop choices/return visits and
  native barriers under conservative offer routing. Repeatable money offers and
  mixed shop/finite bomb supplies remain unsupported. See
  [RESIDENT_PROGRESSION.md](RESIDENT_PROGRESSION.md).
- Bomb/fire secrets track persistent collision and bomb/candle requirements through
  configured use positions. Other secret types, water/ladder deployment, raft routes,
  advanced money rules, boss vulnerabilities and enemy-drop dependencies remain unsupported.
- Without a bomb shop: at most eight total finite bombs, including gifts and
  starting bundles. Bomb shops are supported only without other finite bomb sources. Larger supplies
  need capacity/timing-aware pickup routing and are explicitly unsupported, rather
  than pretending the eight-bomb cap cannot waste an early pickup.
- Supported pack enemy families are modeled as sword-vulnerable encounters.
  More complex encounters need explicit capability rules before certification.

Generation retries up to twelve candidates, with bounded solver work per attempt.
It reports the last failed/inconclusive analysis if none qualify. It does not hide
problems by moving rewards across barriers or removing locks.

## Versioned packs and game behavior

Version-1 packs remain readable and editable. They keep the previous preview
starting sword. Version 2 adds `starting_items`, `goals`, optional generation
provenance, optional room role/template IDs, directional block secrets and stair
links/cellar metadata, pickup
`requires_clear` / `requires_secret`, and connection
`requires`. Empty starting equipment really starts unarmed; preview code no longer
adds a sword behind the pack's back. Draft packs may have no objectives, but cannot
be certified until objectives are selected.

The adapter converts permanent requirements to DoorDefinition inventory-slot
requirements, and starting items/objectives to WorldDefinition resources. Native
movement, key opening, bomb opening and room transitions enforce those gates.
Collecting every objective sets `authored/complete` and displays
**DUNGEON COMPLETE**. This is an authored-dungeon result, separate from the original
Zelda ending. Imported worlds have empty starting-item/goal/requirement defaults.

Shared generated packs and template libraries are ROM-free. Local sprite/atlas
choices continue to save separately under ignored reference-inputs/. No imported
assets or original room layouts are copied into generation output.

## Validation

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/generation.gd --log-file /tmp/generation-tests.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/generated_dungeons.gd --log-file /tmp/generated-game-tests.log
```

The editor suite checks a 16-case seed/size matrix, every supported required-item
recipe, repeatability across JSON round trips, template capture isolation, threaded
GUI controls and deliberately impossible/unsupported examples. Counterexamples
include self-locked keys/items, isolated pickups, blocked interiors, finite key
reuse, missing bombs, closed shutters, missing objectives and search exhaustion.

The native suite replays structured witness events for three recipes through real
player movement, pickups, key locks, B-button bomb use and room changes. It verifies
all objectives and the completion flag. It also checks that an item gate blocks an
edge transition and that an empty version-2 loadout stays unarmed. Combat is won
using the engine's hit handling, matching the solver's stated combat abstraction.
