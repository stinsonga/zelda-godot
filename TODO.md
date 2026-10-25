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
  see docs/CAVES_AND_SECRETS.md. Follow up with the item submenu, Armos and
  recorder secrets, raft and ladder, bait, bow and arrows, and traced item-use timing.
- Dungeon foundations and bosses, starting with connecting the level entrances.
- Improve visual content editing and asset-pack workflows alongside implementation.

See docs/ for completed save/load, room persistence, combat, beam, and scrolling work.
