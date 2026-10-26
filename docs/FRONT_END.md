# Front end

The game now starts at the original's file menu (`scenes/front_end.tscn`). The
world-only scene (`scenes/main.tscn`) remains for the labs and tests.

Keys in the menus: arrows; **Enter** is Start, **Tab** is Select, **Z** is A,
**X** is B. During play, **Escape** calls up Continue/Save/Retry (the
original's controller 2 Up+A).

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

## Verification

`tests/front_end.gd` drives the menus with temporary files and needs no ROM. It
covers:
- registration, key repeat, B, and ZELDA;
- starting a file;
- the death sequence's length and death count;
- SAVE with three hearts, and loading kept items;
- RETRY dropping progress, and CONTINUE;
- elimination, and persistence.

`tests/visual_preview.gd -- front_files`, `front_register`, `front_eliminate`,
or `front_continue` renders the screens.

## Not yet

- The title screen, story scroll, and attract demo (mode 0).
- The curtain that opens a game (mode 3 unfurl).
- The ending after Zelda's rescue (mode $13).
- The second quest.
- Menu sounds beyond the shared cues.
