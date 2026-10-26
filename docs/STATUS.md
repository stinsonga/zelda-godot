# Status and remaining work

Both quests are playable from the title screen to the ending, as far as the
importer and tests can show. `tests/reachability.gd` finds every treasure, all
eight Triforce pieces, Zelda, and every dungeon room reachable in each quest.
This page records the one problem left open and the work that remains. Details
live in the topic documents linked below.

## Unresolved: overworld room $0F

Room $0F is the north-east corner of the overworld. It holds a cave with a
100-rupee "IT'S A SECRET TO EVERYBODY" reward. In both quests, nothing in the
game reaches it.

**What is known:**
- Its only opening is a waterfall square ($0A, tiles $74/$75, walkable) at the
  bottom of the screen. The square below it, at the top of room $1F, is solid
  rock ($1B, tiles $D8-$DB).
- The layouts are not the problem. The original's own overworld layout routine
  (`LayoutRoomOW`), run on the CPU emulator for all 128 rooms, gives exactly the
  tiles the importer decodes.
- No other way in exists in the ROM's tables:
  - **From $0E:** its right edge is water, and so is $0F's left column.
  - **From $1F:** Link can't reach its top edge through the rock.
    `Z_07 CheckScreenEdge` only changes screens from the edge itself.
  - **Ladder:** it works only in `LadderRoomsOW` ($17, $18, $19, $27, $4F, $5F).
  - **Raft:** it sails only from the docks in rooms $3F and $55 (`UpdateDock`).
  - **Warps:** no cave stairs and no whirlwind stop lands in $0F.
- "WALK INTO THE WATERFALL!" (the level 4 old man) is about room $0E's
  waterfall. That waterfall leads up from $1E to the cave with the letter, and it
  works.

**Conclusion so far.** $0F appears unreachable in the original as well, but this
isn't confirmed.

**To settle it:** check a reference map, or try to walk into $0F in an emulator.
- If there is a way in, find the mechanism in the source, add it, and drop the
  room from the pinned list.
- If there is none, note it as original behaviour here and in SECOND_QUEST.md.

`tests/reachability.gd` currently fails if any room other than $0F and its cave
becomes unreachable.

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
- **Movement.** Input priority, turn timing, and fractional carry have not been
  compared frame by frame against the original
  ([IMPLEMENTATION.md](IMPLEMENTATION.md)).

The most valuable single step here is an emulator comparison harness. Capturing
reference input and position sequences would turn many of these from "believed
correct" into "checked".

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
