# Submenu

Enter (Start) opens the pause submenu while Link is free to act. Open, it
fills the top 176 lines, with the status bar below it. Enter closes it again.
The game waits meanwhile: monsters, Link, and their timers stop, and only the
rupee meter keeps counting. Arrow keys move the cursor. The old C/Tab cycling is gone.

## Behavior (Z_05 UpdateMenu)

- Opening runs the setup states (six frames outdoors, where `UpdateMenuStartOW`
  first prepares the Triforce rows; five in a level), then scrolls down 3 pixels a
  frame from 2 to 176: 64 or 65 frames in all. Closing takes the Start frame plus 59
  frames of scrolling up. Every sprite is hidden while it is up
  (`UpdateMenuCommon1`'s `HideAllSprites`).
- `UpdateSubmenuSelection` / `FindAndSelectOccupiedItemSlot`: there are nine item
  slots. Right steps forward and left back, once per new input. Up and down only
  keep an occupied slot. Slot 0 is either boomerang. Slot 3, the bow, is never
  selected. Arrows need the bow. Slot 7 shows the potion, else the letter. With
  nothing owned, slot 0 is selected. The cursor flashes between sprite rows 5 and
  6 every eight frames.
- `DrawSubmenuItems`: selectable items sit at `SubmenuItemXs` on Y $36 and $46.
  The bow and arrows are drawn side by side. Equipment (raft, book, ring, ladder,
  magical key, bracelet) sits on the top row at Y $1E, and the selected item shows
  in the B box at ($40, $36).
- Outdoors, the Triforce shows the pieces held (`UpdateMenuStartOW`). Each piece
  fills three of 24 tile slots. A slot that a neighbouring piece already half filled
  (tile $E5 or $E6) becomes full ($F5).
- In a level, the sheet map (`Submenu_WriteSheetMapRowTransferRecord`) shows
  each visited room as tile $E2 plus its walkable-doorway mask (up, down, left,
  right as bits 3-0). Open doorways count, walls and false walls do not, and other
  doors count once opened. Rows are 16 rooms, rotated right by the level's
  `LevelInfo_SubmenuMapRotation`. Cells outside `LevelInfo_SubmenuMapMask`, and
  unvisited rooms, stay blank. The map and compass, when held, sit at the left, and
  Link's room is marked. Entering a dungeon room sets `visited/<room>`, which saves
  with the other flags.

## Import

`tools/import_submenu.py` builds each backdrop as the original builds NT2: it
applies the static transfer buffers named by `SubmenuTransferBufSelectorsOW/UW` (via
`TransferBufAddrs`) to a blank nametable and crops NT2 rows 8-29. The result is
`submenu_ow.png` and `submenu_l1-9.png` in each context's background palettes.
Tile atlases (`submenu_*_tiles.png`), the cursor and room-marker sprites, and
`imported/submenu.tres` (a `SubmenuLayout`: Triforce slots, map rotations and
masks) carry what changes during play. `WorldDefinition.submenu` points to the layout.

Without an import, or in authored worlds, the submenu draws placeholder boxes and
labels. Items appear wherever they came from: the world registers every
`content/items` definition it does not already have.

## Limits

- The "selection changed" tune is cued as `menu_select`, but it is not synthesized yet.
- The compass's flashing Triforce marker on the sheet map is not drawn.
- Outside the menu, the project still switches the B item when the current one
  runs out. The original leaves the selection until the menu is opened.

## Verification

`tests/submenu.gd` covers timing, pausing, the meter, selection rules, the B item,
visited rooms and doorway masks, and with an import the Triforce tile rules.
`tests/test_submenu.py` checks the transfer buffers, Triforce slots, map data, and
backdrop pixels. `tests/visual_preview.gd -- submenu_ow` or `submenu_uw` renders
the submenu.
