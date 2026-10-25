# Implementation TODO

## Deferred: original opening and file screens

- Title layout, waterfall animation, Start transition, and music.
- Opening story scroll, item displays, sprite choreography, and timing.
- Three-file selection, name entry, and profile-specific saves.
- Original death, Continue / Save / Retry flow and restart semantics.
- Attract-mode gameplay replay after sufficient game fidelity exists.
- Decide how original menus expose native checkpoints versus NES restart rules.

## Current sequence

- Octorok fidelity follow-up: emulator replay comparison and full object-slot scheduling.
  Source-based movement, targeting, shooting, spawning, and collision are implemented;
  see docs/OCTOROK_FIDELITY.md.
- Audio fidelity follow-up: fuller APU synthesis and reference listening comparisons.
  Effects, room music, fanfares, and swappable audio banks are implemented; see docs/AUDIO.md.
- Common overworld enemies implemented: Moblins, Lynels, Tektites, Leevers,
  Peahats, and editable variants; see docs/MORE_ENEMIES.md. Follow up with
  replay fidelity, Zora, Armos, Ghini, boulders, and special overworld actors.
- Overworld caves, shop items, equipment, and bomb/fire/push secrets are implemented;
  see docs/CAVES_AND_SECRETS.md. The bow, boomerang, recorder (pond and whirlwind),
  and paused potion refill now work. Follow up with the item submenu, Armos
  secrets, raft and ladder, bait, the magical rod, and traced item-use timing.
- Dungeon foundations implemented: all nine first-quest levels, doors, keys,
  cellars, push blocks, items, and the level map; see docs/DUNGEONS.md.
  First dungeon monsters implemented: Stalfos, Goriyas, Gels, Zols, Keese, and
  Ropes, Darknuts, Gibdos, Bubbles, Like Likes, Vires, Pols Voices, Wallmasters,
  traps, Wizzrobes, Aquamentus, and Dodongo; see docs/DUNGEON_MONSTERS.md. Next:
  Manhandla, Gleeok, Digdogger, Gohma, Moldorm, Lanmola, Patra, and Ganon (several
  need arrows, the recorder, or bombs), then dark rooms, old men, and the
  recorder entrance to level 7.
- Improve visual content editing and asset-pack workflows alongside implementation.

See docs/ for completed save/load, room persistence, combat, beam, and scrolling work.
