# Status and remaining work

Both quests are playable from the title screen to the ending, as far as the
importer and tests can show. `tests/reachability.gd` finds every treasure, all
eight Triforce pieces, Zelda, and every dungeon room reachable in each quest.
This page records the work that remains. Details
live in the topic documents linked below. The latest session handoff is
[HANDOFF_2026-10-26.md](HANDOFF_2026-10-26.md).

## Resolved: overworld room $0F

Room $0F, the north-east corner with a 100-rupee "IT'S A SECRET TO EVERYBODY"
cave, looked unreachable. Its waterfall leads down onto solid rock at the top of
room $1F, and no tile, ladder, raft, or warp gets past it.

The answer was a special case in `Z_07 GetCollidingTileMoving`. In room $1F,
when Link moves vertically at X $80 with Y below $56, every tile counts as
walkable: a false wall straight up into $0F's waterfall. Rooms now carry it as
`false_wall_x` / `false_wall_below_y`, and the importer sets it for $1F.
`tests/reachability.gd` reaches every room in both quests, and walks Link up the
passage while the rock beside it still blocks.

## Remaining work

### 1. Audio gaps (smaller)

See [AUDIO.md](AUDIO.md).
- **Completed:** door and menu-selection recordings, and the low-health warning
  at one heart or less. The warning repeats on the source driver cycle and yields
  to competing Tune0 effects. DMC sample decoding now supports the door sound.
- **Completed:** boss appearance/hit/death samples, ambient roars in both quests,
  Link's damage and sword-beam samples, continuous dungeon-track loops, and the
  song-code audit for Triforce, Ganon, and death. All ROM recordings remain in ignored imported/audio/.
- **Synthesis.** It is approximate: per-frame APU writes, incomplete sweep and
  linear counter, incomplete analog filtering. Godot also mixes effects alongside the music
  rather than taking over its channels as the original does.

### 2. Fidelity pass

These are recorded approximations, each small:
- **Death sequence.** Its palettes are overlays rather than palette swaps
  ([FRONT_END.md](FRONT_END.md)).
- **Ending sprites.** Link, Zelda, and the Triforces keep their in-game palettes
  instead of the ending palette.
- **Menu marker.** The file menu's second-quest sword uses the white sword image
  in place of menu palette 7.
- **Whirlwind.** Its flight is not animated: Link is set down after the tune
  ([CAVES_AND_SECRETS.md](CAVES_AND_SECRETS.md)).
- **Status-bar map.** The overworld map is a scaffold rectangle.
- **Sprite limits.** There is no eight-sprites-per-line limit or flicker, and no
  unified NES object-slot allocator. The ladder's free-slot check approximates it
  ([LADDER.md](LADDER.md)).
- **Pols Voice.** Its eight-way jump table is not translated yet
  (`overworld_enemy.gd`).
- **Untraced timings.** Item-use pose length, push speed, and some message
  timing are untraced. The native end-level exit still uses its existing timer;
  the full fanfare now continues across the overworld transition. Boss sample
  update order and foreground/background timing need reference comparison.
- **Visual details.**
  - Held white and magical swords reuse the wooden sword's tiles.
  - Link's sprite ignores the magical shield.
  - A drained pond keeps its water colour.
- **Unverified rocks.** The shortcut-room rocks in $1D and $49 haven't been
  checked against an emulator.
- **Movement.** A headless Nestopia/Godot harness compares 1,509 frames across
  seventeen scenarios, and all of them match. They cover `MoveObject`'s grid-point
  stop, the stateful grid offset, diagonal input, and overworld room changes in
  every direction, with the original's frames around the scroll. Mountain-stairs speed ($30 on tiles
  $74/$75) is translated from `InitLinkSpeed` but not yet checked against the
  emulator, since no scenario reaches stairs. Next:
  - monster comparisons. Room $78's Octoroks now match the NES on every frame:
    edge spawns, walker turns, shared fractions, and the wrapped spawn distance.
    Other families (Moblins, Lynels, Leevers, Tektites, Peahats, then the
    dungeons) each need the same tracing. The remaining movement checks depend
    on these;
  - then dungeon transitions and doorways (unmeasured; they keep the bare scroll),
    and routes to stairs and room $1F's false wall, all past monsters. See
  [MOVEMENT_COMPARISON.md](MOVEMENT_COMPARISON.md) for setup, safeguards and findings.

### 3. Expansion tools

The extension model is documented in [EXTENDING.md](EXTENDING.md). Missing:
- an in-editor tile-painting tool for rooms (rooms are edited as Inspector
  data today; [IMPORTING.md](IMPORTING.md));
- authoring helpers for dungeons, doors, and cellars, which are built by hand
  from the lab fixtures today;
- automatic ID remapping when content is renamed, so older saves keep loading
  ([SAVING.md](SAVING.md)).

### 4. Reachability solver limits

The solver is a test tool, not part of the game. It does not:
- count keys;
- limit the ladder to one square;
- loop the mazes;
- charge in shops.

Tightening those would let it catch subtler content bugs ([SECOND_QUEST.md](SECOND_QUEST.md)).
