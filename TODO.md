# Implementation TODO

## Finish the dungeons

1. Remaining bosses: Moldorm, Lanmola, Patra, then Ganon,
   silver-arrow finish, and rescuing Zelda. Manhandla and Gleeok are now implemented and tested.
2. Immediately after bosses: expansion groundwork below.
3. Dungeon old men's hint rooms, money-or-life rooms, candle-lit dark rooms,
   monster-carried keys and drops (including Dodongo bombs), Triforce of Power,
   and the gate to Ganon.
4. Remaining items: magical rod/book, bait, raft, ladder, magical-key edge cases,
   clock, and fairies.

## Expansion groundwork (after bosses)

- A ROM-free dungeon lab with doors, push block, cellar, editable monster presets,
  and meaningful tests that do not require imported content.
- Doors described by direction and type without atlas indices.
- Editable behavior settings for remaining hard-coded systems (Rope, B-items, bounds).
- A guide to adding rooms, caves, items, variants, and dungeons while respecting
  the content boundary. Keep ROM-derived assets and tables under ignored imported/.

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
  ending, and attract demo. Decide how menus expose native checkpoints versus
  original restart rules.

## Completed milestones

Movement, source-based Octoroks, room scrolling/history, native checkpoints,
sound/music, common overworld families and editable variants, 59 overworld caves,
equipment and secrets, all nine dungeon foundations and 255 rooms, regular dungeon
families and Wizzrobes, Aquamentus, Dodongo, Gohma, Digdogger, Manhandla, and Gleeok.
Bow/arrows, boomerang, recorder/whirlwind, and gradual paused potion refill work.
See docs/ for behavior, validation, and remaining fidelity limits.
