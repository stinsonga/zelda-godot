# Door-connected room templates

A reusable unit may contain one primary room and up to three companion rooms.
Internal reciprocal doors, their locks and item requirements, stairs, enemies,
pickups, secrets and shared graphics remain editable ordinary pack data. Only
the primary room offers external ports to the generator.

## Try it

Open **Dungeon → Generate…**, browse to
`content/templates/door_templates.json`, choose seed **42**, **6 primary rooms**,
and **blue_candle**, then **Generate and verify**. The result has eight rooms:
the generated key and goal each occupy a companion room. The goal companion has
an internal key door and its primary provides an additional key. Use the result
and playtest it normally. For branches and a loop, use **8 primary rooms** with
**Custom layout**, **2 branch rooms**, **1 extra loop**, and the same seed.

The example includes manually authored versions facing each of the four
cardinal directions. Generation chooses a version that fits; it does not rotate
room contents.

## Capture a group

1. Select the intended primary room and open **Dungeon → Save template…**.
2. Select companions in **Door companions**. Ctrl/Cmd-click selects multiple
   rooms. The primary is always included; selecting a companion does not follow
   all of its doors into the rest of the dungeon.
3. Enable **Include linked cellar rooms** if the selection has outgoing stairs
   into cellars. These automatically included rooms count toward the same
   four-room limit. Stair destinations must be selected or included in that
   cellar closure; dangling stair links are refused.
4. Choose the role and external door ports. An internal primary-room door
   reserves its direction, so the corresponding external-port checkbox is
   disabled. Other external doors from the source selection are removed.
5. Optionally choose the generated reward room and pixel position. This may be
   any room in the captured unit. Without an override the primary's `(120,77)`
   remains the reward location.
6. Review the live footprint below the capture controls, then save the derived
   library, choose it for generation and verify a recipe.

The preview marks the primary room with **P**, the generated reward with **\***,
and available external ports in green. Internal key doors are orange, bombable
doors red, and directed stair links dashed purple. Hover over a room for its full
ID and connection kinds. It follows companion, reward and port changes. A failed
cellar closure clears the preview and leaves the capture error visible. For the
older cellar-only workflow, the preview shows the normalized row of local map
cells that capture actually saves.

Every selected room must be reachable from the primary through internal links.
Door-connected map cells must be adjacent in the door direction, and no local
map cells may overlap. Invalid connections or rewards fail capture rather than
being silently repaired. Capture checks structure; progression verification
checks whether locks, terrain and supplies permit completion under the solver's
existing assumptions. See [DUNGEON_GENERATION.md](DUNGEON_GENERATION.md).

The source document is unchanged. Existing pickups are copied; remove example
pickups that would grant progression items early. Enemy definitions are scoped
to the template. Shared art follows all captured rooms and enemy variants;
private ROM appearance never enters the library.

## Placement, identity and compatibility

Library format **3** retains the format-2 `room`, `annexes`, `reward` and
`appearance` fields. `annexes` may now contain dungeon companions with internal
`connections`, as well as cellars. Targets and reward references use local IDs.
An external port must not overlap an internal primary-room connection.

On expansion, the generator assigns unique IDs such as `room_1_part_1` for a
dungeon companion and `room_1_cellar_2` for a cellar. All door/stair targets,
reward references and room-art bindings follow the instance. Mutable copies are
independent of the template and other occurrences.

Format-3 units retain their relative map shape. All primary cells are reserved
first; template selection rejects out-of-bounds or overlapping footprints. A
candidate can fail if no eligible orientation fits. Generation retries up to
12 bounded candidates and reports failure without dropping rooms or moving
rewards. The requested 6–16 primary rooms and 32-total-room limit remain.

These libraries produce recipe version **6**, with a separate world identity.
Custom graph recipes include branch/loop settings in that identity. Extra loops
still join only eligible primary ports and preserve crossed progression gates;
internal door networks remain intact. Ordinary and cellar-only entries may
coexist in a format-3 library; all companion map offsets in that library are
preserved, so review older cellar offsets when upgrading a library.

Formats 1 and 2 and their prior recipe identities/seed results remain unchanged.
Room-ID alias history is a separate manual-edit feature; regenerating content
does not replay manual edits or their migration history.

Current limits: four rooms per unit, external ports on the primary only, one
automatic reward location per unit, no automatic rotation or multiple floors.
Advanced dependencies remain outside solver support; water is solved with the
ladder (see [DUNGEON_GENERATION.md](DUNGEON_GENERATION.md)).

## Checks

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/door_groups.gd --log-file /tmp/door-groups.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/generated_door_groups.gd --log-file /tmp/door-groups-native.log
```

Checks cover explicit membership and outside-door removal, repeated instances,
shared art, invalid/cyclic/disconnected units, footprint bounds and overlap,
JSON determinism, unavailable internal dependencies, GUI capture, and native
replays through internal key doors, generated loops and mixed cellar stairs.
Combat uses the existing documented sword-vulnerable encounter assumption.
