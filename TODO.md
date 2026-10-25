# Implementation TODO

## Finish the dungeons

1. Dungeon old men's hint rooms, money-or-life rooms, candle-lit dark rooms,
   monster-carried keys and drops (including Dodongo bombs),
   and the gate to Ganon. Real dark rooms replace the overlay in Ganon's room.
2. Remaining items: magical rod/book, bait, raft, ladder, magical-key edge cases,
   clock, and fairies.

## Expansion groundwork

Done: the ROM-free dungeon lab (`scenes/dungeon_lab.tscn`, `tests/dungeon_lab.gd`),
doors from direction and kind, push blocks without atlases, editable B-item, Rope,
and monster-bound settings, and [docs/EXTENDING.md](docs/EXTENDING.md). Still to
make editable: Wizzrobe, Like Like, and Wallmaster timings; Link's speed and sword
timings. A visual room editor would help authors most.

## Overworld and fidelity

- Armos, their caves and the power bracelet; Zora, Ghini, boulders, special actors.
- Item submenu replacing C/Tab; trace item-use timing against the original.
- Emulator replay comparisons, starting with Octoroks and bosses. Resolve provisional
  push/item poses, Pols Voice jumps, Wizzrobe/pond graphics, and whirlwind flight.
- Full object-slot scheduling, fuller APU synthesis/reference listening, door sound.
- Improve visual content editing and asset-pack workflows.

## Front end (later)

- Second-quest layouts, secrets, and enemies.
- Title/waterfall, story scroll, three files, name entry, Continue/Save/Retry,
  ending (after `combat.ending`), and attract demo. Boss roars and the Triforce,
  Ganon, and Zelda tunes. Decide how menus expose native checkpoints versus
  original restart rules.

## Completed milestones

Movement, source-based Octoroks, room scrolling/history, native checkpoints,
sound/music, common overworld families and editable variants, 59 overworld caves,
equipment and secrets, all nine dungeon foundations and 255 rooms, regular dungeon
families and Wizzrobes, Aquamentus, Dodongo, Gohma, Digdogger, Manhandla, Gleeok, Moldorm, Lanmola, Patra, Ganon, and Zelda's rescue.
Bow/arrows, boomerang, recorder/whirlwind, and gradual paused potion refill work.
Expansion groundwork: dungeon lab, authored doors, editable settings, guide.
See docs/ for behavior, validation, and remaining fidelity limits.
