# Overworld room scrolling

Walk through an open edge to scroll into its connected room. The HUD stays fixed;
terrain and Link move within the 256-by-176 play area. All four directions use
the existing room IDs and editable `exits` mapping.

The outgoing room remains current until the scroll completes. Movement, attacks,
reset input, combat, damage timers, pickups, and enemy spawning pause during the
transition. Incoming enemies initialize on completion, preserving their full
spawn delays. Rocks, beams, and loose drops clear at the start of a valid scroll.
A blocked destination prevents the transition and leaves ongoing combat intact.

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

This implements the visible scroll phase, not the NES's preceding nametable
transfers, palette transition steps, or every original room-entry walk. Relative
vertical timing starts with a waiting tick instead of inheriting the global NES
frame parity. Cave portals still use their existing immediate room change and
automatic entry walk. Dungeon transitions and maze rules remain future work.

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
