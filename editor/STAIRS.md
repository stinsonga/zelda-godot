# Hidden stairs and authored cellars

Stairs are directed links between editable rooms. They can be visible immediately
or hidden until the room's block is pushed. They use the game's existing portal
runtime and need no ROM assets. Open `content/packs/stair_vault.json` to try a
three-room example: push the block, descend to the cellar, collect the bow, return,
and use the bow-gated north exit to reach the objective.

## Create a cellar

1. Under **STAIRS / CELLAR LINKS**, choose the source cell. Optionally enable
   **Hidden until block push** after adding a room block.
2. Click **Create linked cellar**. This creates an editable cellar room, a source
   stair and a return stair together as one undo step. A free map position is
   assigned; select the cellar in the room list to paint terrain or place items.
3. The initial cellar has two narrow shafts connected along the bottom. Arrival
   is at `(48, 61)`, below its return stair at cell `(3, 3)`. Return arrival uses
   the parent room's spawn position. Both links can be edited afterward.
4. Add an objective and run **Dungeon → Check progression**, then playtest.

These are authored cellar rooms using ordinary dungeon movement and collision.
They do not reproduce the original cellar transition animation or imported cellar
layouts. No forced entry walk or side-view physics is added. The room's optional
`kind: "cellar"` records its authoring purpose and labels it in the room list.

## Link existing rooms

Choose **New stair link**, set its cell, destination room and arrival pixel
position, then **Apply stair link**. Or use the **Stairs** brush with those settings.
A selected link is moved/edited in place, preserving its read-only ID. New links
receive a unique room-local ID. A brush stroke is one undo step. Right-click with
Stairs removes links at the clicked cell. **Delete selected stair** removes just
that link; a return link is independent and may remain intentionally one-way.

Select-click a visible stair to focus its inspector, or choose a link in the stair
list. The list also exposes stairs covered by a block. New/edited links are
validated before mutation. An unchanged Apply does not create undo history, even
for a pack read from JSON. The room toolbar wraps when space is limited.

Deleting a destination room removes incoming stairs together with existing door
and objective cleanup; Undo restores them. Copying a room drops its outgoing stair
links, just as it drops door links. Removing a block clears dependent stairs'
secret requirements, making those stairs visible; Undo restores the dependency.
Changing a block is checked against existing stair and arrival positions.

The dungeon overview draws cyan dashed stair connections. Connectivity review
includes these directed links, so a cellar reached only by stairs is not reported
as disconnected. Stair links need not connect adjacent map cells.

## Geometry and behavior

Each room supports at most four links. Source cells must be floor at X 3..12,
Y 3..7, away from forced door entry paths. The trigger is the exact standing
position `(cell.x * 16, cell.y * 16 - 3)`, including movement that crosses it during
a tick. The full square is a marker, not a full-square trigger. Walking alongside
a stair can bypass it if geometry permits.

Arrival must be walkable, inside the room, on the eight-pixel dungeon grid, and
outside the destination's reset block. The room's initial spawn cannot be a stair.
Hidden stairs require a block secret and may occupy the block's starting square;
no stair may occupy its landing square. Other floor cells can also hide stairs.
Stairs may be one-way, but cannot target their own room in this first format.

Arrival on a destination stair suppresses portals until Link moves away, avoiding
an immediate bounce. Moving off and returning activates it normally. Entering a
room resets its block/reveal state; collected items keep their normal persistence.
Visible authored stairs use a small ROM-free step marker in the game. Existing
imported portals retain their tile art and behavior.

## Data and progression

Optional version-2 room fields:

```json
{
  "kind": "cellar",
  "stairs": [{
    "id": "return",
    "cell": [3, 3],
    "target": "entry",
    "target_position": [120, 125],
    "requires_secret": false
  }]
}
```

The adapter builds native `PortalDefinition` resources. Shared JSON contains no
scripts, paths or imported graphics. Existing packs without stairs behave as
before; authoring stairs upgrades v1 to v2.

The solver stops at active stair triggers, checks hidden-stair gates and arrival
collision, resets destination blocks, and tracks arrival suppression. Leaving a
suppressed arrival is an explicit movement choice, so regions across an active
stair are not merged after it rearms. Collection witnesses in stair packs record
actual stand positions. Native tests replay those positions, departures and
transitions through real player movement. Combat remains the documented
sword-vulnerable encounter assumption, not a survival proof.

Single-room templates with linked stairs are rejected clearly, including capture.
They require multi-room templates and destination-ID remapping, which are future
work. Do not assume seeded generation can yet create cellar networks. Other
secret triggers, cave interiors and the original cellar animation remain separate
features.

## Checks

On a fresh source-only checkout, first let Godot register game classes:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --import --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path editor --script res://tests/stairs.gd --log-file /tmp/stair-editor.log
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/authored_stairs.gd --log-file /tmp/stair-native.log
```

Coverage includes hidden/visible links, cellar creation/return, malformed and
blocked arrivals, JSON round trips, ID preservation, no-op history, room deletion,
undo, arrival bounce suppression, unavoidable-stair traps and separated combat
regions. Original dungeon portal behavior is also covered by the dungeon lab.
