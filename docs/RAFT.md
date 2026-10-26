# Raft travel

The raft is passive equipment. With it, standing exactly on a mainland dock
starts an automatic trip; no B-item selection or direction press is needed.
Link faces the route direction, moves one pixel per simulation tick, and ignores
movement, sword, and item input. His raft is drawn six pixels below him. Enemies
and existing projectiles keep updating, but cannot collide with halted Link.
At the screen edge, normal overworld scrolling takes him to the island. Movement
on the island, including reaching its cave or level entrance, is normal walking.

Returning south admits Link onto the mainland's water at its north edge and
starts the automatic inbound ride. The raft lands two pixels past the starting
dock, preventing an immediate return trip. His resulting two-pixel grid offset
is preserved, so he can walk off the dock or turn back to board again.
The secret cue plays once for each outbound or inbound start.

The source is Z_05 SetupTileObjectOW and Z_04 UpdateDock:

| Mainland | Lane X | Island | Destination |
| --- | --- | --- | --- |
| $3F | 96 | $2F | Heart-container cave |
| $55 | 128 | $45 | Level 4 |

Both original mainland routes run from local Y 61 to -3, and return from -3 to
63. Inventory is neither consumed nor changed by traveling. Clock effects keep
their existing rule of ending when entering another room. Native saves retain
raft ownership; saving waits until Link lands, so loading cannot strand him on
a transient crossing. Entering or loading a different room clears the old ride.

## Authored routes

Run scenes/raft_lab.tscn without imported assets. Collect the raft at the start,
walk north to the dock, ride to the island, collect its treasure, then walk south
to return. The same room resources support normal scrolling or immediate exits.

Assign a RaftRoute to the mainland RoomDefinition. Set dock_position,
edge_position, landing_position, speed_pixels_per_tick, and sprite_offset.
All points use play-area coordinates. Dock and edge must share a straight axis;
landing must be behind the dock on that axis. The edge must meet the room's
movement boundary and have a matching exit. The neighboring island needs an
ordinary exit back into that exact lane. Other water cells remain blocked.
Cardinal horizontal routes are also supported for authored levels.

The native ~ water glyph and collision remain independent of raft travel. A ride
bypasses terrain only along its configured lane; it does not enable free sailing.
Deployed raft art is a separate named sprite, exported from item slot $09 with
palette attribute zero. The two original dock configurations and sprite stay in
ignored imported/; the native lab is authored without ROM data.

## Verification and limits

Godot checks cover absent equipment, alignment, automatic start, one-pixel timing,
input lock, exact landing, treasure access, return over blocked water, scrolling
in both directions, editable speed, invalid routes, native checkpoints, and both
original round trips. They also walk to the heart cave and level 4 entrances.
Python checks verify all 128 rooms' dock presence and the deployed sprite pixels.
Visual previews: raft_lab (ROM-free) and raft (local import).

No emulator frame-by-frame replay has been performed. Final-frame raft drawing
and the source's exact object-update order remain fidelity follow-ups. Authored
routes should have clear landing squares and a reachable neighboring shore.
