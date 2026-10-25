# Sound and music

Attacks, accepted player/enemy damage, enemy deaths, shield blocks, heart/rupee
pickups, item collection, and item-lift fanfares now emit audio events. Rejected
hits and collected rewards do not repeat their sounds. Music continues through
adjacent rooms with the same music ID; changing IDs changes tracks. Item fanfares
pause background music and resume it on completion. Death stops music; retry and
load select the destination room's track. Losing focus pauses playback. Press M
to toggle mute for this session.

## Import and asset boundary

Run the ordinary importer to include audio:

```sh
python3 tools/import_rom.py 'reference-inputs/Legend of Zelda_ The (U) (PRG 0).nes'
```

For audio alone, run `tools/render_audio.py` with the same ROM argument.
The tool accepts the existing SHA-verified US PRG0 ROM. Its bounded 6502 subset
runs the ROM's `DriveAudio` routine in bank 0, captures APU register writes, then
renders mono 22050 Hz PCM WAV files. An unsupported instruction fails the import.
The renderer is an offline extraction tool, not the game's runtime or a general
NES emulator. It needs only the Python standard library.

All recordings, cue mappings, and loop markers go into ignored `imported/audio/`.
The source-only packaging tool excludes this directory and the ROM. No copied
music sequences, note tables, or sound scripts are embedded in tracked code.
Without imports, Godot generates simple original placeholder tones and melodies.

The source references are `Z_00.asm`, `DriveAudio`, `DriveEffect`, `DriveTune0`,
`DriveTune1`, `DriveSong`, and `PlayNextPhrase`; `Z_01.asm`, `DealDamage`,
`TakeItem`, `TakeOneRupee`, `PlaySecretTune`; and `Z_07.asm`, `UpdateDeadDummy`.
The overworld recording includes its introduction, then loops at the original
repeating phrase boundary. The cave recording uses the underworld song and its
phrase loop. Using dungeon music in the sword cave is an intentional content
choice for this request; set that room's music to empty for a silent cave.

## Custom content

`RoomDefinition.music` selects a cue (`overworld`, `cave`, or a custom name).
An empty name selects silence. `WorldDefinition.audio_bank` accepts a
`GameAudioBank` resource whose `streams` dictionary overrides individual cues
with your own `AudioStream` resources. Set music loops on those streams in Godot.
No gameplay changes are needed to swap recordings or add room music.

Future secret systems call `world.reveal_secret(stable_flag)` after their world
change succeeds. It persists the flag through the existing save system and emits
`secret` only on first discovery. Terrain secrets themselves remain future work;
collecting the sword does not also play the secret tune.

## Fidelity limits

Note sequences and driver tick timing come from the original ROM. Waveform
synthesis is approximate: APU writes are applied once per video frame, pulse
sweeps and the triangle linear counter are not fully modeled, and this does not
reproduce analog filtering, nonlinear mixing, DMC, or cycle-accurate timing.
Godot mixes effects through eight reusable voices instead of stealing the NES's
music channels. This preserves music during combat but differs from the original
channel arbitration. Runtime audio uses the device clock rather than the manual
simulation-tick test clock. Exact sound matching needs a fuller APU renderer and
listening comparisons against reference captures.

## Verification

Run `python3 -m unittest discover -s tests -p 'test_*.py'` for CPU addressing,
carry/subroutine, channel disable, WAV format, audible signal, and loop checks.
Run Godot headless with `--script res://tests/audio.gd` for room selection,
continuity, fanfare pause/resume, focus suspension, attack/damage deduplication,
reward collection, one-time secrets, death, and imported music selection.
The gameplay, save/load, room persistence, and Octorok suites also remain valid.

On this machine, headless Godot 4.6.2 reports WAV playback references at shutdown;
the same audio checks pass without that warning using the normal graphical/audio
backend. The assertions and source-only tests pass in both modes.
