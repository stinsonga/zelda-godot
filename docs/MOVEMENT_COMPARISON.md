# Movement comparison against the NES

The first harness runs four controller sequences in first-quest room `ow_77`:
walking and stopping, reversing, turning between grid boundaries, and approaching
an obstacle and backing away. There are 200 compared frames. This measures the
current implementation; differences are reported, not accepted as expected failures.

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

The next fidelity task is to trace grid-boundary movement and fractional carry,
then rerun this harness. Obstacle results must be reassessed after the earlier
movement discrepancy is resolved. No movement behavior was changed to create
these reports.

This adapter covers one enemy-free starting room and cardinal movement only.
It does not yet compare diagonals/input priority, combat, scrolling, enemy RNG,
images, audio, or arbitrary save states. It establishes repeatable measurements,
not full-game fidelity.

ROM-free comparator checks:

```sh
python3 -m unittest discover -s tests -p 'test_movement_trace.py'
```
