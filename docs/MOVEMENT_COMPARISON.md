# Movement comparison against the NES

The harness runs seventeen controller sequences starting in first-quest room
`ow_77`, 1,509 compared frames:
- walking and stopping, reversing, and turning between grid boundaries;
- approaching obstacles on three sides and backing away;
- turns before and after halfway in each direction;
- reversals mid-segment;
- one-frame taps;
- a 178-frame mix of short presses;
- walking out of the room to the east, west, and north, and back south;
- diagonals held from a grid point, partway along a segment, and into a wall.

Each frame records a phase: free play (NES mode 5), or a transition between
rooms (modes 6, 7, and 4). The phase is compared on every frame; room, position,
and facing only in free play. A case lists the rooms it may enter. The NES has
lag frames while it lays out the next room, so during a transition the frame
counter may hold still and the controller check is skipped; free play keeps the
strict checks.

It measures the current implementation; differences are reported, not accepted
as expected failures.

## Local setup and running

Requires Python 3, Godot, a C++ build toolchain, Git, and your locally supplied
US PRG0 ROM and imported content. No emulator, ROM, save state, or reference
capture is distributed with this project.

From the project folder, build the reference emulator once:

```sh
python3 tools/build_reference_core.py --fetch
```

This builds unmodified [Nestopia's libretro core](https://github.com/libretro/nestopia)
at commit `2110d21b7174455ec98948bb474147dea0e3cad0`. An existing checkout at that
commit can instead be supplied with `--source /path/to/nestopia`.
The library, license, and checksum/build metadata go in ignored
`reference-inputs/emulator/`. The build and capture have been exercised on this
Apple Silicon Mac; the build helper also supports Linux but that path is untested.

```sh
python3 tools/movement_trace.py run
```

The default Godot executable is `/Applications/Godot.app/Contents/MacOS/Godot`.
Use `--godot`, `--core`, or `--rom` to override paths. Linux needs `--core` pointing
to the built `.so`. ROM discovery requires exactly one `.nes` in `reference-inputs/`.

Outputs live in ignored `reference-inputs/comparisons/link_movement/`:

- `reference.json`: inputs and post-frame NES RAM observations, with provenance.
- `native.json`: the same inputs replayed through Godot's actual World simulation.
- `report.txt` and `report.json`: first mismatch per scenario and differing-frame counts.
- `seed.state` and logs: local diagnostics.

Exit status **0** means all compared fields match, **1** means measured differences,
and **2** means setup or validation failed. `capture` runs only the NES capture;
`compare` regenerates reports from existing traces. `--out` chooses a different
ignored directory or an external temporary folder. Generated data inside the
project is restricted to `reference-inputs/` and `exports/`.

## Frame convention and safeguards

The headless frontend drives a full NES emulator, including its PPU and mapper;
it does not use the importer's CPU-only helper. A fresh process starts with empty
save RAM. A controller-only, 1,128-frame bootstrap registers a new file named A
and reaches the stationary starting pose: room `$77`, position `(120,77)`, facing
up. It never patches NES RAM. That state is serialized and restored before each
case. Every NES case is run twice and must reproduce exactly.

Each recorded frame supplies one controller input, runs one NTSC emulator frame,
then samples Link's position and facing. RAM controller bits must match the input
and the frame counter must advance exactly once. Leaving the room or entering a
menu aborts capture. NES screen Y has the 64-pixel HUD removed.

Godot starts at the same pose with the entry curtain completed and runs one
`World.simulate_tick` per recorded input. Expected post-frame positions are never
used to move or correct the player. The comparator requires matching initial
states, scenario fingerprints, imported ROM revision, input order and frame count.
It compares room, integer X/Y and facing without time shifts or tolerances.
NES fractional movement and Godot subpositions are retained as diagnostics;
their different representations are not equated.

Reference captures record core binary SHA256, build commit when available, core
options, ROM PRG hash and seed checksum. Native captures record Godot version and
a SHA256 of the simulation scripts and capture adapter. These identify a local
measurement; captures are deliberately not committed as shared golden fixtures.

## First measurements

The initial run found differences in every scenario:

| Scenario | First differing frame | Observation |
| --- | ---: | --- |
| Walk/stop | 6 | NES X=128; Godot X=129. |
| Reverse/stop | 11 | NES X=104; Godot X=103. |
| Turn between boundaries | 6 | NES remains at (128,77), facing right; Godot reaches (128,76), facing up. |
| Obstacle approach | 11 | The leftward approach already differs by one pixel before contact. |

No movement behavior was changed to create these reports.

## After the MoveObject correction

All four differences had one cause. `Z_07 MoveObject` applies four quarter-steps
of $60 to one fraction byte (`ObjPosFrac`). `AddQSpeedToPositionFraction` and
`SubQSpeedFromPositionFraction` suppress the pixel carry once `ObjGridOffset` is
at +8 or -8, while the fraction keeps accumulating. Link therefore stops on each
grid point for the rest of the frame, taking six frames per eight pixels. The
fraction is shared by both axes, and a turn starts on the next frame. The
controller carried leftover movement across grid points and turned within the
same frame.

`PlayerController.move_frame` now follows the routine. All four scenarios match
for every frame, including the obstacle contact: walk/stop 40 frames,
reverse/stop 36, turn 28, bush contact 96. `tests/movement_frames.gd` pins the
traced positions ROM-free. Two older tests assumed 1.5 pixels a frame and now
allow the original's timing.

## The grid offset

The seven cases added next found one more rule. In the taps case, Link reverses
at x 127.5, stops, and then down is pressed at x 126. The original keeps him
walking left; Godot sent him right, to the nearer grid point.

`ObjGridOffset` is state, not a function of position:
- the quarter-step carries move it (+1 right or down, -1 left or up);
- reversing leaves it alone;
- `Link_EndMoveAndAnimate` clears it at a multiple of 8.

`Link_HandleInput` uses it for turns:
- at offset 0 (`Link_ModifyDirAtGridPoint`), Link takes the input;
- between points, `Link_ModifyDirOnGridLine` keeps the direction at |offset| 4
  or more;
- below 4, Link keeps going if he's already heading back to the grid point he
  left, and otherwise turns back toward it, re-measuring the offset the other way
  (-1 becomes 7).

`PlayerController` now keeps the offset. All eleven cases match on every frame.

## Room changes

The three room-change cases first showed that Godot's transition was 40 frames
short horizontally: it had only the visible scroll, and it started a frame
early. It also missed the settle frame after arrival. The fixes are in
[SCROLLING.md](SCROLLING.md), and all three cases now match.

This adapter covers the starting room and its neighbours.

## Monsters

A case with `"objects": true` also compares monster slots 1-11 in free play:
type, position, and facing, for slots out of their spawn cloud (`ObjMetastate`
0). The native capture adopts the reference's monster starting state, as it does
Link's position:
- the random bytes ($18-$24);
- `CurEdgeSpawnCell` ($525), which is set once at reset and carries across rooms;
- `MonstersFromEdgesLongTimer` ($4B);
- the ten-frame long-timer counter's phase ($26);
- the chase target, its timer, and its other-target flag ($60-$62, $4A).

The first case, `octoroks_east`, walks into room $78. It found four differences,
now fixed:
- **Lag frames.** The NES has two lag frames in each room change (`RoomTransition.LAG_TICKS`). On
  them the NMI skips its random and timer updates; Godot advanced them.
- **Spawn frame.** On a monster's spawn frame, `InitObject` runs instead of its
  update, so it doesn't move.
- **Initial facing.** Edge spawns face by `ChaseTarget` (`InitWalker`), which can
  lag behind Link, not by Link's live position.
- **Starting state.** The state above was not shared.

Tracing further found three more differences, and the case now matches on all
312 frames, Link and monsters alike:
- **Input direction.** Walkers move along `ObjInputDir`, which takes the facing
  only at the end of each update and is 0 for a new monster. A new monster
  therefore starts with `Walker_GetNextAltDir`'s search, beginning with a random
  perpendicular. (`TryNextDir` stores each candidate as the moving direction, so
  the search's "opposite of the moving direction" is the rejected perpendicular.)
- **Shared fraction.** Monsters share one `ObjPosFrac` across both axes, like
  Link, with `MoveObject`'s grid limit of +-16. After a turn, the first step
  depends on the fraction left by the last axis.
- **Wrapped spawn distance.** `IsDistanceSafeToSpawn`, also reached from
  `IsSafeToSpawn` for spawn lists, subtracts in eight bits. A spot across the
  screen (Link at X 0, the spawn at X 240) counts as within $22, so the spawn is
  refused.

The random bytes line up frame for frame. Zelda's NMI scrambles them before
running the frame's logic, as Godot's tick does, and both skip the two lag
frames.

**Further routes are blocked on monsters.** Mountain stairs, room $1F's false
wall, and any dungeon are several screens from the start through rooms with
monsters. The bootstrap has no sword. Godot's monsters don't yet start from the
NES's random state, so contact and knockback would differ for reasons unrelated
to movement. Comparing monsters first (agreeing on their spawn order and RNG) is
the prerequisite. It is also the handoff's next step.
Known gaps the source shows but no case covers yet:
- **Mountain stairs.** On tiles $74/$75, `InitLinkSpeed` halves the quarter speed
  to $30 and resets the fraction. This is now implemented from the source: rooms
  carry `stairs_tiles`, and the speed is re-evaluated where the original does it
  (at a grid point, or when continuing straight). No scenario reaches stairs yet:
  the nearest stairs rooms are several screens away, past monsters.
- **Room $1F's false wall.** At X $80, vertical moves ignore the tiles. This is
  implemented, but likewise unchecked against the emulator.
- **Diagonal input (now matched).** At a grid point, `Link_ModifyDirAtGridPoint`
  keeps the last walkable direction it checks (right, left, down, up), so
  vertical wins. It sets `Link_GoStraight`, which keeps Link going straight to
  the next grid point. Off the grid, `GetOppositeDir` keeps the horizontal part.
  The world now reads the D-pad as up to one direction per axis. The dungeon-only
  door cases of the routine are not translated.
- **Doorways.** `Link_ModifyDirInDoorway` handles them in dungeons.

It does not yet compare combat, scrolling, enemy RNG,
images, audio, or arbitrary save states. It establishes repeatable measurements,
not full-game fidelity.

ROM-free comparator checks:

```sh
python3 -m unittest discover -s tests -p 'test_movement_trace.py'
```
