# Status

Both quests are playable from the title screen to the ending. The importer and
tests show every treasure, all eight Triforce pieces, Zelda, and every dungeon
room reachable in each quest (`tests/reachability.gd`). All of the original
game's rooms, caves, items, monsters, bosses, the front end, and both quests are
implemented, translated from the disassembly. This page sorts what has been
verified against the original from what has only been translated, and lists
the known approximations. Details live in the topic documents linked below.

## 1. Verified against the original, frame by frame

A headless Nestopia/Godot harness replays the same controller input in both and
compares every frame ([MOVEMENT_COMPARISON.md](MOVEMENT_COMPARISON.md)): 27
scenarios, 16,622 frames, all matching. They cover:
- **Link:** walking, turning, reversing, diagonals, walls, the grid offset and
  movement fraction, knockback, invincibility, and heart damage arithmetic.
- **Room changes:** overworld in every direction; dungeons in every direction,
  with the walk-in past the doorway, shutters, and opening a locked door.
- **The sword:** swing timing, turning while swinging, the beam, hits, kills,
  and monster knockback.
- **Monsters:** Octoroks (with rocks), Tektites, Zoras, Moblins (with arrows),
  Lynels, Red Leevers, Peahats in flight, and level 1's Keese and Stalfos,
  including edge and spawn-list spawning and the random number generator.
- **Drops:** rupee and heart drops, their lifetime, pickup, and rupee counting.

## 2. Translated but not verified

Implemented from the disassembly, but not compared against an emulator:
- **Monsters:** Blue Leevers, Ghini, Peahats once they land, Armos, boulders,
  and the dungeon monsters other than Keese and Stalfos (Goriyas, Gels and
  Zols, Darknuts, Wallmasters, Like Likes, Bubbles, Gibdos, Vires, Ropes, Pols
  Voice, Wizzrobes, Lanmolas) and all bosses.
- **Drops:** bombs, five rupees, clocks, and the help drops (a bomb or five
  rupees after ten kills without damage, a fairy at sixteen).
- **Items** other than the sword: boomerang, bombs, arrows, candle, recorder,
  food, potions, rod and book, ladder and raft, with their timings.
- **Movement:** mountain stairs, room $1F's false wall (up to room $0F), cellar
  stairs, and leaving caves and dungeons.
- **Rocks** in the shortcut rooms $1D and $49.

Verifying more of these is possible with the existing tools
(`tools/route_autopilot.py`, `movement_trace.py run --case`, `inspect`), one
emulator case per room or family.

## 3. Known approximations

- **Audio** ([AUDIO.md](AUDIO.md)). Synthesis is approximate: per-frame APU
  writes, incomplete sweep and linear counter, and incomplete analog filtering.
  Effects mix alongside the music instead of taking over its channels. Boss
  sample order and foreground/background timing are untraced.
- **Sprite limits.** There is no eight-sprites-per-line limit or flicker, and no
  single object-slot allocator: shots, the Zora's slot, and the ladder's
  free-slot check each approximate it ([LADDER.md](LADDER.md)).
- **Pols Voice.** Its eight-way jump table is not translated (`overworld_enemy.gd`).
- **Whirlwind.** Its flight is not animated; Link is set down after the tune
  ([CAVES_AND_SECRETS.md](CAVES_AND_SECRETS.md)).
- **Palettes.** The death sequence uses overlays instead of palette swaps
  ([FRONT_END.md](FRONT_END.md)); the ending keeps in-game palettes for Link,
  Zelda, and the Triforces; the second-quest menu marker uses the white sword
  image instead of menu palette 7; a drained pond keeps its water colour.
- **Sprites.** The magical shield appears on Link's walking and attack frames,
  but not on the lifting pose. The status-bar map tiles are tinted one blue
  rather than drawn in the level's status-bar palette. The rupee, key and bomb
  icons keep overworld colours in dungeons and sit two pixels left of the
  original column, for a gap before the counts.
- **Timings.** Item-use pose length, push speed, some message timing, and the
  end-level exit are untraced.
- **Lag.** The original drops frames when a room is busy. Godot has no CPU
  budget, so it never lags; the comparison holds Godot on the original's lag
  frames instead.

## 4. Editing and expansion

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

The GUI-authored four-room `content/packs/ember_relay.json` now exercises the
end-to-end authoring loop and has a native completion replay. Usability checks
led to compact optional feature forms and automatic brush-settings scrolling.
Authored playtests now have a content-aware HUD and window title, with objective
progress, accurate health capacity, controls and persistent completion feedback.
Long titles are shortened to fit; the original game HUD is unchanged.
See [EMBER_RELAY.md](../editor/EMBER_RELAY.md) for the route, tested scope and
remaining friction.

Generation now optionally configures branch-room counts and exact loop counts.
Version-5 graph recipes preserve crossed key/bomb locks and item requirements,
respect template ports, and retain linked cellars and authored graphics. Classic
versions 1–4 keep their existing seed results. The GUI-saved
`content/packs/looped_dungeon.json` demonstrates eight rooms, two branch rooms and
one loop. Native graph replays reach completion and exercise an actual guarded
shortcut. Using generated work now marks it unsaved until saved. See
[DUNGEON_GENERATION.md](../editor/DUNGEON_GENERATION.md).

Door-connected templates now capture explicit groups of up to four rooms,
including internal locks and optional linked cellars. Format-3 libraries use
version-6 recipes with fixed, collision-checked footprints. Native replays cover
internal key doors, mixed stairs and extra generated loops. The capture dialog
now previews unit footprints, internal links, external ports and reward rooms,
with full room/link details on hover. See
[DOOR_GROUP_TEMPLATES.md](../editor/DOOR_GROUP_TEMPLATES.md).

Room IDs can now be renamed in the GUI with reference updates, undo/redo and
checkpoint migration. Old and deleted names stay reserved. Shared artwork and
private ROM appearance follow room renames without crossing the asset boundary.
See [ROOM_IDS.md](../editor/ROOM_IDS.md) for the compatibility rules.

Standalone play: **Export game…** writes a bundle (the pack and the shared art
it uses), and an exported game lists the bundles in its `packs/` folder or
`user://packs`, each with its own save files (README, *Distributing an authored
game*).

Remaining editor work, in recommended order:

1. **Broader progression solving.** Water with the ladder and bomb supplies
   beyond the bag are solved and replayed; still to model: more complex
   dependencies (enemy drops, other secret types, bomb shops mixed with finite
   bombs). Continue reporting unsupported mechanics rather than certifying them.
2. **More flexible generation.** External ports on companion rooms, template
   rotation and multiple floors. Bounded door-connected groups, internal locks,
   linked cellars, branches/loops and the live capture preview are implemented.
3. **Other content-ID migrations.** Placements, enemy variants, items and pack
   identity. Room-ID renaming and its checkpoint migration are implemented; see
   [ROOM_IDS.md](../editor/ROOM_IDS.md).
4. **More authoring coverage and usability.** Additional resident modes,
   cave entrance/original cellar transitions, recorder/Armos and other secrets,
   advanced doors, room filters and more item/enemy properties. See
   [RESIDENTS.md](../editor/RESIDENTS.md) and
   [PLACEMENTS.md](../editor/PLACEMENTS.md) for current support.
5. **Further graphics workflows.** Layered sprites, animation states beyond the
   implemented idle/walk/attack clips, and editable copies of imported rooms.
   Rectangular sprite layouts, directional clips and independent timing are
   already implemented. Shared authored art and private ROM overlays remain
   separate; see [AUTHORED_ART.md](../editor/AUTHORED_ART.md) and
   [ASSET_LIBRARY_PLAN.md](../editor/ASSET_LIBRARY_PLAN.md).

## 5. Reachability checker limits

The original-content checker (`tests/reachability.gd`) is separate from the
authored-pack solver above. It is a test tool and does not:
- count keys;
- limit the ladder to one square;
- loop the mazes;
- charge in shops.

Tightening those would let it catch subtler content bugs ([SECOND_QUEST.md](SECOND_QUEST.md)).
