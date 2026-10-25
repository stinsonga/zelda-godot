# Extending the game

New rooms, dungeons, caves, items, and monster variants are Godot resources
(`.tres`) under `content/`, played by the same engine as the imported original.
Nothing here needs a ROM. This guide covers each kind of content, the rules
that keep the project shareable, and how to test what you add.

## The content boundary

- `content/` holds only hand-authored material: your own rooms, definitions,
  placeholder art, and text. Never copy anything out of `imported/` (graphics,
  palettes, maps, original dialogue, or generated `.tres` files) into `content/`.
  See [ASSET_BOUNDARY.md](ASSET_BOUNDARY.md).
- Authored content must run with no import. Rooms draw from theme colors and
  placeholder shapes when a sprite or atlas is missing, so leave `tile_atlas`
  empty unless you made the atlas yourself.
- Use your own IDs. Lab content uses a `lab_` prefix (`lab_skeleton`,
  `lab_dungeon_entry`) so it never collides with imported names like `stalfos`
  or `l1_73`. Sprite names are looked up in the theme, and dungeon sprites with
  an `l<N>_` prefix, so an authored monster named like an original one would
  borrow imported art when it exists.
- `tools/prepare_public_project.py` builds a source-only copy. Review anything
  new under `content/` before sharing.

## Worlds and scenes

A scene runs `scripts/world.gd` with either a `WorldDefinition`
(`world_definition`) or a plain `room_resources` list. Set
`use_imported_world = false` so the scene ignores `imported/world.tres`. The
first room listed is the start unless the world names `start_room`. At startup
every room is validated, and every exit and portal target must exist.
`scenes/dungeon_lab.tscn` and `scenes/item_lab.tscn` are small worked examples.

## Rooms (`RoomDefinition`)

A room is 16 x 11 squares of 16 pixels. `tiles` is eleven rows of sixteen
characters: `#` is solid, `.` is open. Positions are play-area pixels with Link's
top-left corner. Link walks on an 8-pixel grid offset by `grid_origin`. Use
`Vector2i(0, 5)` for dungeon-style rooms, so rows sit at Y 13, 29, 45, ... 125.

| Field | Use |
| --- | --- |
| `id`, `title` | Stable ID; the title shows in placeholder rooms' HUD. |
| `exits` | `{"up": "room_id", ...}`: walking off that edge enters the neighbour. |
| `movement_bounds` | Link's limits; dungeon rooms use `Rect2i(0, -3, 241, 161)` so doorways reach the edge. |
| `monster_bounds` | Where monsters roam. Leave empty for the original overworld or underworld bounds. |
| `enemies` | `EnemySpawn`s: unique `id`, `enemy` definition, `position`, optional `facing`. |
| `enemy_persistence` | `permanent` remembers each defeated spawn, `overworld` keeps original kill counts, `reset` restores everyone. |
| `pickups` | `PickupDefinition`: `item`, `position`, `tolerance` (use `(8, 8)` in dungeons), `lift_ticks` (0 to take without lifting), `requires_clear`. |
| `portals` | Stairs, caves, ladders: an `area`, a `target_room` and `target_position`, plus optional `required_direction`, `entry_walk_pixels`, `exit_rise_pixels`, `requires_secret`. |
| `secret` | One `SecretDefinition`: bombable wall, burnable bush, push rock, dungeon push `block`, or recorder pond. |
| `doors`, `shutter_trigger`, `dungeon_level`, `map_room_id` | Dungeon features, below. |
| `cave` | A `CaveDefinition` resident, below. |
| `dialogue` | Text typed out on entry. Write your own; never paste original dialogue. |

## Dungeons

Give every room of a level the same unused `dungeon_level`; the lab uses 10.
That number scopes the map, compass, and triforce (`map/10` and so on), and
labels the HUD. Each room's `map_room_id` places it on the map (row * 16 + column).
At least one room needs a portal to an overworld room (`dungeon_level = 0`).
Leaving the level and a Wallmaster's restart both use that portal.

A dungeon room is a wall frame two squares thick:

```
################
################
##............##   x 7 rows
################
################
```

**Doors** need only `direction` and `kind`. Leave `cells`, `open_tiles`, and
`open_collision` empty. The standard doorway, two squares deep with a 16-pixel lane,
is cut into the wall while the door is passable (`DoorDefinition.STANDARD_CELLS`).
Imported rooms list their cells only because their atlas draws the frame.

| Kind | Behavior |
| --- | --- |
| `open` | Always passable. |
| `false` | Drawn as wall; Link walks through. Use it on both sides. |
| `key` | Opens when Link presses into it with a key (the magical key is never spent). Opening marks both sides. |
| `bombable` | Hidden in the wall until a bomb detonates near it; marks both sides. |
| `shutter` | Closes behind Link; reopens on the room's `shutter_trigger`: 1 when the monsters are gone, 4 when the block is pushed. The default 0 never reopens: a one-way door. |
| `wall` | No doorway. |

Pair each door with the matching `exits` entry. Rooms without an atlas mark closed
key doors and shutters; bombable and false walls stay hidden.

**Push blocks**: a `SecretDefinition` with `trigger = "block"`, the block's
`cell`, and `reveal_kind = "stairs"` with a `reveal_cell`, or `"shutters"`
with `shutter_trigger = 4`. The block is solid until pushed. Link must line up
and push away from himself for 16 ticks with every monster gone. A stairs
portal on the revealed square needs `requires_secret = true`.

**Residents**: give a dungeon room a `cave` (a `CaveDefinition`), set
`lifts_wares = false` for the dungeon style, add the two fire decorations, and
list `provoked_statues` for the fires to shoot when he is struck. `triforce_gate`
makes him leave once Link holds the triforce of levels 1-8. **Statues**: list
fireball origins in `statues`.

**Cellars** are ordinary rooms: a ladder column of `.` squares, a portal at the
top (`required_direction` up), and an item with `lift_ticks = 128`. Set
`history_id` to the room above if they should share room history.

`content/rooms/lab_dungeon_*.tres` shows every piece. `tests/dungeon_lab.gd`
walks through it.

## Monsters (`EnemyDefinition`)

Pick a `behavior`, then tune its settings. Every setting is an exported field
with comments in `scripts/enemy_definition.gd`, and `validation_errors()` checks
them at startup. Starting points:

| Want | Copy | Notes |
| --- | --- | --- |
| Walker (Stalfos, Moblin) | `content/enemies/lab_skeleton.tres`, `moblin.tres` | `speed_subpixels` (256 = 1 pixel a frame), `turn_chance`, `projectile_kind`. |
| Flyer (Keese, Peahat) | `lab_bat.tres`, `peahat.tres` | `flight_*` speeds, turns, rests. |
| Hopping blob (Gel) | `lab_slime.tres` | `hop_delays`. |
| Rope | (field defaults) | `speed_subpixels`, `rope_rush_speed`, `rope_line_up`, `rope_turn_mask`. |
| Bosses | `aquamentus`-style imported definitions, or `manhandla.tres`, `gleeok.tres`, `moldorm.tres`, `lanmola.tres`, `patra.tres`, `ganon.tres` | Part counts, speeds, timers, and orbits are fields. |

Common fields: `health`, `contact_damage` (in half-hearts),
`invincible_to` (`sword`, `beam`, `boomerang`, `arrow`, `bomb`, `fire`, `magic`),
`counts_for_clear`, `drops_rewards`, `loot_table`, `spawn_cloud`, `sprite`, and
`fallback_color` for placeholder drawing.

## Items (`ItemDefinition`)

`effect` decides what taking the item does: `unique` sets its `slot`, `grade`
replaces a lower grade, `count` adds up to `limit`, `level` sets a dungeon-level
flag, `heart_container`, `rupees`, or `health`. Items sharing a slot are grades of
one thing (`boomerang` 1 and `magical_boomerang` 2).

B-button items read their use settings from the item at Link's current grade:
`use_damage` and `use_speed` (arrows), `use_range` and `use_speed` (boomerang),
`use_fuse_ticks` (bomb stages), and `use_once_per_room` (candle). A faster bomb or
a longer boomerang is a new grade, or a variant that replaces the base item in a
world.

## Caves (`CaveDefinition`)

A cave room sets `cave`. The resident says `text`, which must be your own words,
and offers up to three `CaveWare`s (`item`, `price`, `hint`). Flags choose the
mode: `choose` for a gift, `pay` with `show_prices` for a shop, `hint`,
`money_game`, `door_charge`, `gift_money`, `heart_requirement`, `requires_letter`,
and `remember` for one-time offers. `content/caves/lab_*.tres` cover each kind.

## Testing new content

- Startup validation catches malformed rooms, doors, spawns, and definitions.
  Load your scene once.
- Write a headless Godot test like `tests/dungeon_lab.gd`: instantiate your
  scene, drive `simulate_tick(direction)`, and check outcomes. Run it with
  `godot --headless --path . --script res://tests/your_test.gd`.
- `tests/visual_preview.gd -- dungeon_lab entry` (or `hall`, `block`, `cellar`,
  `treasure`) renders a screenshot with `--write-movie`. Use the same approach
  for your own scenes.
- Run the whole suite before committing: every Godot test under `tests/` and
  `python3 -m unittest discover -s tests -p 'test_*.py'`.

## Not editable yet

Some systems still use fixed values from the original: Link's speed and sword
timings, cave text speed, the dungeon map's size, and how many projectiles can
be on screen (per world, `projectile_limit`). Wizzrobe, Like Like, and Wallmaster
timings also remain constants in `scripts/overworld_enemy.gd`. Dark rooms,
dungeon old men, and dialogue rooms inside dungeons are not built.
