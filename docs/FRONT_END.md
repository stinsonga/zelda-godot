# Front end

The game now starts at the original's title (`scenes/front_end.tscn`), or at
the file menu when the title isn't imported. The world-only scene
(`scenes/main.tscn`) remains for the labs and tests.

Keys in the menus: arrows; **Enter** is Start, **Tab** is Select, **Z** is A,
**X** is B. During play, **Escape** calls up Continue/Save/Retry (the
original's controller 2 Up+A).

## Title and story (Z_02 mode 0)

The original builds these screens directly in the PPU, so they are replayed
that way. `NesScreen` (`scripts/nes_screen.gd`) holds:
- two vertically stacked nametables;
- 32 palette entries;
- 64 OAM sprites in 8x16 mode.

It draws them through a palette-lookup shader. `TitleDemo`
(`scripts/title_demo.gd`) runs the original's per-frame rules on that data, which
`tools/import_title.py` imports into `imported/title/`.

Each phase starts with three initialization frames with video off.

The title (`AnimateDemoPhase0Subphase0`) shows for 512 frames:
- `InitialTitleSprites` are rewritten every frame.
- Three waterfall waves fall two lines a frame and widen past $B9 and $C2.
- The crest switches tiles every eight frames.
- The Triforce glows through eight colors, six frames each, then rests $10 frames.

Then the title fades through 14 palettes on the `DemoPhase0Subphase1Delays`
timings.

The story (`AnimateDemoPhase1*`) runs in stages:
- The prologue scrolls up a line every other frame until NT0 sits 8 lines up.
- It holds for 256 frames.
- The item list scrolls five and a half screens. Every eighth line writes a new
  row with its text (`DemoLineAttrs` $80), clears attributes ($40), and adds items
  ($20) from `DemoLeftItemIds` and `DemoRightItemIds`.
- Items rise with the text. The fairy switches frames every four frames, and
  flashing items switch palettes every eight.
- The closing picture of Link with the sheet holds for 256 and then $39 frames,
  and the title starts over with its song.

Start is read once a phase is running and leaves for the file menu. The attract
mode has no gameplay demo: the story is the whole of it.

## The curtain (Z_07 mode 3)

With the front end, the play area opens from the middle (`UpdateWorldCurtainEffect`).
It reveals one tile column on each side every five frames, 16 times, over 76
frames in all. Meanwhile:
- the status bar shows;
- sprites are hidden;
- Link waits;
- the level's song starts once it is open.

It runs when:
- a file starts;
- the player chooses CONTINUE;
- a Wallmaster carries Link back;
- Link moves between the overworld and a dungeon.

Caves and the whirlwind's scroll don't use it.

## Save files

`SaveFiles` keeps the original's three files under `user://files`. Each file holds:
- a name in tile codes;
- a death count;
- the quest;
- the hearts and ring shown in the menu;
- once saved, the game state, written through the checked `SaveStore`.

A file stores no position: loading one always starts at the overworld's start.
The native checkpoints are separate: **F5**/**F9** still save and resume at the
exact spot (SAVING.md), outside these menus.

## File menu (Z_02 UpdateMode1Menu)

The screen follows `Mode1TileTransferBuf`:
- "- S E L E C T -", the box, and the NAME and LIFE headings;
- REGISTER YOUR NAME and ELIMINATION MODE.

Each file in use shows, in its row (`Mode1SlotLineTransferBuf`):
- its name;
- its hearts, 1-8 above 9-16;
- its death count beneath;
- Link in the file's ring color.

The heart cursor starts on the first file in use, or on REGISTER. Select steps
through the files in use and the two options. Start opens the choice.

## Registration and elimination (Z_02 UpdateModeERegister, UpdateModeFElimination)

Both screens show the title row (`ModeFTitleTransferBuf`), the three names, the
END option, and the 11 x 4 character board (`ModeFCharsTransferBuf`,
`ModeE_CharMap`).

- Registration starts at the first free file. Select moves among free files and
  END.
- On the board, arrows move the cursor, again after $10 frames and then every 8.
  A writes the highlighted character and moves the name cursor on, wrapping after
  eight. B moves on without writing.
- Start on END creates each newly named file with three hearts. A name beginning
  ZELDA is a second-quest file; the second quest itself is not built yet.
- Elimination's Select steps through all three files and END. Start erases the
  file under the cursor (with its saved game), or on END moves on to registration.

## Death (Z_05 UpdateMode11Death)

With the front end, running out of hearts plays the death sequence. Monsters are
hidden throughout.
- Link flashes for $21 frames.
- He turns four full circles, a quarter every five frames: down, right, up, left.
- The world fades over four steps, ten frames apart.
- Link greys for $17 frames, then his spark shows for $0F (small, then large).
- The heart sound plays, $2D frames pass, and "GAME OVER" shows for $5F frames.
- The file's death count rises, and Continue/Save/Retry follows.

The death palettes are approximated with overlays.

## Continue/Save/Retry (Z_05 UpdateMode8ContinueQuestion)

CONTINUE, SAVE, and RETRY sit at column 10, rows 10, 13, and 16, with the heart
cursor at X $40. Select steps through them. Start flashes the choice for $40
frames, and every choice leaves Link with three full hearts:
- **Continue** clears the room history and resumes at the level's entrance, or at
  the overworld's start.
- **Save** writes the file and returns to the file menu.
- **Retry** returns to the file menu without saving.

## Ending (Z_02 mode $13)

Zelda's rescue plays her song ($06). $80 frames later, mode $13 begins
(`EndingSequence`, `scripts/ending.gd`):
1. **Furl.** Once her song has ended (289 frames from the rescue), the room is
   erased from both edges, a column a side every five frames. Link and Zelda stay
   on screen.
2. **Thanks.** "THANKS LINK,YOU'RE / THE HERO OF HYRULE." types out, a character
   every six frames, with the text sound. $50 frames later, the music stops.
3. **Flash.** Link and Zelda hold up Triforces for $C0 frames. From frame $40,
   the backdrop cycles `EndingFlashColors` each frame.
4. **Peace.** The ending song starts. $40 frames later, "FINALLY, PEACE RETURNS
   TO HYRULE. THIS ENDS THE STORY." types out, a character every eight frames.
   Link and Zelda leave when the long timer reaches 4.
5. **Credits.** The ending palette is set. The credits scroll half a line a frame
   between brick walls, a nametable row every eight lines.
   - In the first quest, they end on "ANOTHER QUEST WILL START FROM HERE".
   - In the second, they end on "YOU ARE GREAT", the player's name and deaths, and
     "END OF THE LEGEND OF ZELDA 1". That scroll runs a screen further.
6. **Final screen.** The Triforce of Power sits over Ganon's ashes. After $40
   frames, Start moves the file on to the second quest:
   - items and world flags are cleared, with three full hearts;
   - the file is saved;
   - play returns to the file menu.

The play area and credits are nametable data on a `NesScreen` behind the world.
The world draws:
- the status bar, scrolling with NT0, without its sprites, until the credits
  overwrite its rows;
- Link, Zelda, and the Triforces, from its own sprite sheets.

Those sprites keep their in-game palettes rather than the ending palette.

## Verification

`tests/front_end.gd` drives the menus with temporary files and needs no ROM. It
covers:
- registration, key repeat, B, and ZELDA;
- starting a file;
- the death sequence's length and death count;
- SAVE with three hearts, and loading kept items;
- RETRY dropping progress, and CONTINUE;
- elimination, and persistence.

`tests/title_demo.gd` times each title and story stage, the glow, the song,
and Start. `tests/ending.gd` follows both quests' endings, from the rescue to the
second quest. `tests/test_title.py` checks the importer's table locations. These
three need a local import and skip without one.

`tests/visual_preview.gd` renders the screens:
- `front_files`, `front_register`, `front_eliminate`, `front_continue`, and
  `front_curtain`;
- `title_<frames>` and `ending_<frames>` (`ending_<frames>_2` for the second quest).

## Not yet

- The second quest's places: second-quest files get their own world and monster
  rules, but its overworld and dungeons are still the first quest's (see SECOND_QUEST.md).
- Menu sounds beyond the shared cues.
