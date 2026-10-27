# Overworld room scrolling

Walk through an open edge to scroll into its connected room. The HUD stays fixed;
terrain and Link move within the 256-by-176 play area. All four directions use
the existing room IDs and editable `exits` mapping.

The outgoing room remains current until the scroll completes. Movement, attacks,
reset input, combat, damage timers, pickups, and enemy spawning pause during the
transition. Incoming enemies initialize on completion, preserving their full
spawn delays. Rocks, beams, and loose drops clear at the start of a valid scroll.
As in `Z_07 CheckScreenEdge`, the room changes on the frame after Link reaches
the edge, and the next room is not checked.

`RoomTransition` owns source and target resources, source/destination positions,
direction, elapsed ticks, and scroll distance. The renderer clips terrain and
Link to the play area, including when a theme uses higher-resolution textures.
The native placeholder rooms use the same transition code without any ROM data.

## Source timing

`Z_05.asm`, `ScrollWorldH` selects four pixels per frame in the overworld. This
implementation traverses the room width in 64 simulation ticks.

`Z_05.asm`, `ScrollWorld` advances vertical scrolling eight pixels every other
overworld frame. Traversing 176 pixels takes 44 simulation ticks. Link's on-screen
position moves in the opposite direction and clamps to the destination edge,
matching the source's edge-limited position updates.

Around the visible scroll, the NES spends further frames in the overworld:
- mode 6 (leaving);
- `InitMode7`, which lays out the next room one row per frame;
- the other `UpdateMode7Scroll` submodes;
- mode 4 (entering).

Then, because mode 4 ends by setting mode 5, `InitMode5Play` spends one more
frame before Link can move. `RoomTransition` reproduces these as lead and tail
ticks, measured against the NES with the movement harness:

| Direction | Frames from leaving to free play |
|---|---|
| Left or right | 104 |
| Up | 85 |
| Down | 83 |

The emulator comparison matches these on every frame
([MOVEMENT_COMPARISON.md](MOVEMENT_COMPARISON.md)). The split between lead,
scroll, and tail is approximate in the vertical cases, whose visible scroll
takes 45 (up) or 43 (down) frames depending on frame parity; only the totals are
checked.

Dungeon room changes scroll at half speed: 128 frames across, a row every fourth
frame vertically. They have their own lead, tail and lag frames, and end with
Link walking in past the doorway (`RoomTransition.DUNGEON_*`,
`PlayerController.walk_in_frame`). The horizontal ones match the emulator; the
vertical ones are estimated. Cave portals still use their existing immediate room
change and automatic entry walk. Maze rules remain future work.

## Verification

The normal Godot suite covers all four directions, exact scroll durations,
matching-edge placement, input/combat pause, projectile cleanup, state retention,
blocked destinations, and resumed movement. With local imports it also checks
room 77's east/west and north/south round trips, original grid alignment, and
incoming Octorok spawn timers.

Existing isolated collision/combat fixtures explicitly disable animation through
`World.scroll_transitions`; the separate scrolling suite tests the default enabled
path. The exported option also allows custom projects to choose immediate changes.

Deterministic preview arguments `scroll_right`, `scroll_left`, `scroll_up`, and
`scroll_down` show the transition midpoint for visual review:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/visual_preview.gd --write-movie /tmp/scroll.png --quit-after 3 -- scroll_right
```

Horizontal and vertical previews were inspected for HUD clipping, tile alignment,
and Link placement. No new ROM-derived assets are required for scrolling.
