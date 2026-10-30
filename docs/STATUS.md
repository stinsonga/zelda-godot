# Status and remaining work

Both quests are playable from the title screen to the ending, as far as the
importer and tests can show. `tests/reachability.gd` finds every treasure, all
eight Triforce pieces, Zelda, and every dungeon room reachable in each quest.
This page records the work that remains. Details
live in the topic documents linked below.

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
- **Movement.** A headless Nestopia/Godot harness compares 16,622 frames across
  twenty-seven scenarios, and all of them match, including sword fights, drops,
  and pickups. They cover `MoveObject`'s grid-point
  stop, the stateful grid offset, diagonal input, and overworld room changes in
  every direction, with the original's frames around the scroll. Mountain-stairs speed ($30 on tiles
  $74/$75) is translated from `InitLinkSpeed` but not yet checked against the
  emulator, since no scenario reaches stairs. Next:
  - monster comparisons. Octoroks (edge and spawn-list, with their rocks),
    Tektites, Zoras, Moblins, Lynels, Red Leevers, and level 1's Keese and
    Stalfos match the NES on every frame, including Link being knocked back and
    the sword, its shot, hits, kills, rupee and heart drops, and pickups. Blue
    Leevers, Ghini, Peahats once they land, the rarer drops, and the other
    dungeon monsters each need the same tracing;
  - dungeon room changes match the NES in all four directions, including the
    walk-in past the doorway (so shutters close behind Link) and opening a
    locked door with a key;
    and routes to stairs and room $1F's false wall, all past monsters. See
  [MOVEMENT_COMPARISON.md](MOVEMENT_COMPARISON.md) for setup, safeguards and findings.

### 3. Expansion tools

The extension model is documented in [EXTENDING.md](EXTENDING.md).
[Dungeon Workshop](../editor/README.md) now provides a separate GUI project for
ROM-free room painting, spawns, editable enemy variants, pickups, reciprocal
doors, undo/redo, validation, saving JSON packs and game playtests. Its Dungeon
tab adds a draggable room map, guided adjacent-room creation, door visualization
and non-blocking layout/connectivity warnings. Import ROM… now wraps the existing
decoder with background progress, validation, staging/backups and a searchable
local thumbnail browser. Grouped 16×16 sprite sets and room atlas tiles can now
be assigned through a separate local Art layer, saved in ignored
reference-inputs/editor-overrides/ and resolved in game previews. Behavior and
collision remain authored pack data. See [LOCAL_APPEARANCE.md](../editor/LOCAL_APPEARANCE.md). The sample
Lantern vault exercises keys, combat, shutters and a reward. Dungeon tools now
provide authored template capture, stable seeded generation and a bounded
inventory/room-geometry solver with witness routes. Version-2 packs support
starting equipment, required-item gates and collectible objectives, enforced in
playtests. See [DUNGEON_GENERATION.md](../editor/DUNGEON_GENERATION.md) for assumptions
and unsupported mechanics. Structural validation alone is not a proof.
Individual enemies, pickups and player spawns can now be selected, moved and
edited with undo. Shared enemy definitions are copied when individual stats change;
objective references survive movement and are restored by undo after deletion.
See [PLACEMENTS.md](../editor/PLACEMENTS.md). Directional push blocks now control
shutters and secret-gated pickups, with editor undo, template capture/generation,
solver state and native witness replay. Blocks reset on room re-entry; original
unrestricted blocks retain their behavior. A ROM-free Block vault example is in
`content/packs/block_vault.json`. See [PUSH_BLOCKS.md](../editor/PUSH_BLOCKS.md).

Hidden/visible stairs and editable cellars now use native portal destinations, with
one-step linked-cellar creation, incoming-link cleanup, undo, map links and solver
witness replay. Arrival suppression and forced stair transitions are modeled.
Try `content/packs/stair_vault.json`; see [STAIRS.md](../editor/STAIRS.md). Cellars use
authored dungeon geometry; original cellar animation remains future work.
Primary-room/cellar templates now capture and instantiate up to three linked
annexes, with per-instance target IDs and configurable progression reward rooms.
Seeded generation verifies key-return and goal-cellar routes. Resident-free
format-1/format-2 libraries retain generator versions 1/2. Try
`content/templates/cellar_templates.json`; see
[MULTI_ROOM_TEMPLATES.md](../editor/MULTI_ROOM_TEMPLATES.md).

Hint, gift and shop residents can now be authored in linked cave interiors, using
the native cave-session system. Gifts persist, shops charge rupees and reopen on
re-entry, and return stairs avoid the native resident barrier. Progression now
tracks gifts, wallets, purchases, return visits and the resident barrier, with
native witness replay. Offer-routing, repeatable-income and mixed-bomb limits are
explicit. Resident-bearing generation uses version 3 with a new world ID prefix;
resident-free recipes retain their identities. See
[RESIDENT_PROGRESSION.md](../editor/RESIDENT_PROGRESSION.md) and
`content/packs/shop_route.json`. Try
`content/packs/resident_village.json`; see [RESIDENTS.md](../editor/RESIDENTS.md).

Bombable/burnable room secrets now use native bomb/candle actions, persistent
reveals, hidden stairs/rewards, editor undo and solver/native witness checks.
Version-4 generation keeps their new identities separate. Try
`content/packs/bomb_route.json`, `content/packs/fire_route.json` and
`content/templates/destructible_templates.json`; see
[DESTRUCTIBLE_SECRETS.md](../editor/DESTRUCTIBLE_SECRETS.md).

Authored graphics libraries now import distributable PNG sheets under `content/art/`,
with 16/32/64-pixel tile cells, rectangular sprite frames, independent draw sizes
and offsets, directional animation, tile painting and
secret/stair/resident bindings. Shared appearance survives save/undo/copy and
uses the same resolver in editor and game. Template capture and seeded generation
preserve shared art for primary rooms, linked cellars and scoped enemy variants.
Idle/walk/attack clips now have independent frame sequences and timing, with
behavior-driven playback, named previews, and existing walker shooting exposed
as an optional variant setting. The asset settings form edits existing libraries
without rebinding packs or replacing PNGs, refreshes previews and rejects stale
forms. Library edits are separate from pack undo. ROM overlays remain private. See
[AUTHORED_ART.md](../editor/AUTHORED_ART.md).

Missing:

- richer sprite layouts and importing/editable copies of existing resources; the optional ROM asset-library plan is in
  [ASSET_LIBRARY_PLAN.md](../editor/ASSET_LIBRARY_PLAN.md);
- additional resident modes, cave entrance/original cellar transitions, recorder/Armos and other secret types, plus broader
  generation layouts, general room-group templates and solver support for water, advanced dependencies and
  capacity-sensitive pickup routing;
- automatic ID remapping when content is renamed, so older saves keep loading
  ([SAVING.md](SAVING.md)).

### 4. Reachability solver limits

The original-ROM checker (`tests/reachability.gd`) is separate from the new
authored-pack solver above. It remains a test tool with these approximations:
- count keys;
- limit the ladder to one square;
- loop the mazes;
- charge in shops.

Tightening those would let it catch subtler content bugs ([SECOND_QUEST.md](SECOND_QUEST.md)).
