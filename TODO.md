# Implementation TODO

## Finish the dungeons

1. Candle-lit dark rooms and Ganon's palette fade are done; see docs/LIGHTING.md.
   Old men, bomb offers, the level 9 gate, statues, rupee stashes, carried room
   items, and help drops (including Dodongo's bomb) are also done.
2. Every first-quest item is in, including the magical key's edge cases.
3. The submenu replaces C/Tab cycling (docs/SUBMENU.md). Still missing: its
   selection tune and the compass's Triforce marker on the sheet map.

## Expansion groundwork

Done: the ROM-free dungeon lab (`scenes/dungeon_lab.tscn`, `tests/dungeon_lab.gd`),
doors from direction and kind, push blocks without atlases, editable B-item, Rope,
and monster-bound settings, and [docs/EXTENDING.md](docs/EXTENDING.md). Still to
make editable: Wizzrobe, Like Like, and Wallmaster timings; Link's speed and sword
timings. A visual room editor would help authors most.

## Overworld and fidelity

- The overworld is complete: Armos (with their caves and the power bracelet), Zora,
  Ghini, boulders, pond fairies, and the Lost Woods/Hills; see docs/OVERWORLD_ACTORS.md.
- Trace item-use timing against the original.
- Emulator replay comparisons, starting with Octoroks and bosses. Resolve provisional
  push/item poses, Pols Voice jumps, Wizzrobe/pond graphics, and whirlwind flight.
- Full object-slot scheduling, fuller APU synthesis/reference listening, door sound.
- Improve visual content editing and asset-pack workflows.

## Front end (after remaining items; before fidelity comparisons)

- Second-quest layouts, secrets, and enemies.
- Done: three files, registration, elimination, death, and Continue/Save/Retry
  (docs/FRONT_END.md). The files follow the original's restart rules; F5/F9 stay
  as separate native checkpoints.
- Next: title/waterfall, story scroll, and attract demo; the mode 3 curtain; the
  ending (after `combat.ending`). Boss roars and the Triforce, Ganon, and Zelda tunes.

## Completed milestones

Movement, source-based Octoroks, room scrolling/history, native checkpoints,
sound/music, common overworld families and editable variants, 59 overworld caves,
equipment and secrets, all nine dungeon foundations and 255 rooms, regular dungeon
families and Wizzrobes, Aquamentus, Dodongo, Gohma, Digdogger, Manhandla, Gleeok, Moldorm, Lanmola, Patra, Ganon, and Zelda's rescue.
Bow/arrows, boomerang, recorder/whirlwind, and gradual paused potion refill work.
Expansion groundwork: dungeon lab, authored doors, editable settings, guide.
Dungeon dark palettes, standing-fire candle brightening, and Ganon intro palettes.
See docs/ for behavior, validation, and remaining fidelity limits.

Bait and the hungry Goriya are implemented; all 216 first-quest dungeon monster
rooms are populated. See docs/BAIT.md and scenes/bait_lab.tscn.

Stepladder crossings are implemented; see docs/LADDER.md and scenes/ladder_lab.tscn.

Clock pickups, flying/healing fairies, and original clock/fairy drops are implemented;
see docs/CLOCK_AND_FAIRIES.md and scenes/reward_lab.tscn. Stationary pond fairies
and their refill sequence remain an overworld follow-up.

Magical rod melee/waves and the book of magic are implemented; see docs/ROD_AND_BOOK.md
and scenes/rod_lab.tscn.

Raft travel, both original island routes, and an editable ROM-free island lab
are implemented; see docs/RAFT.md and scenes/raft_lab.tscn.
