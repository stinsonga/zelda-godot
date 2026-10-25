# Caves, items, equipment, and overworld secrets

After a ROM import, every first-quest overworld cave that can be reached
without the recorder or an Armos is playable: 59 caves, each with its own interior
room (`cave_XX`, named after the overworld room `ow_XX`). Residents, wares, prices,
hints, and texts come from the ROM. Bombs, the candle, and gravestone pushes
reveal hidden entrances. Shops sell working equipment.

## Controls

- B item: X or Shift. Choose the B item: C or Tab. This is a provisional
  selection key until the original submenu exists. The B box in the HUD shows
  the selection.
- Walk onto a ware to take or buy it. Hint caves charge when you touch a price;
  the money-making game takes your pick.
- Showing the letter to the old woman: select the letter, then press B in her cave.

## Cave behavior

`CaveDefinition` translates the original `CaveFlags` byte into Inspector fields:
`choose`, `pay`, `show_items`, `show_prices`, `negative_prices`, `hint`,
`money_game`, and a heart requirement. Additional fields cover behavior the
original selects by object type: `remember`, `door_charge`, `gift_money`, and
`requires_letter`. Wares are three `CaveWare` slots at the original X positions
$58, $78, and $98, each holding an item, a price, and an optional paid hint.

`CaveSession` follows `UpdateCavePerson` for one visit:

1. Prices appear with a 10-frame delay. Text then types one character every six
   frames. Link is held until the text ends. A non-breaking space is the ROM's
   untimed tile $25.
2. Talk-only residents stop. A door-repair resident then posts a 20-rupee charge.
3. Choosing residents watch for Link at a ware's exact X, within six pixels of Y $98.
   Nothing is taken while the rupee counter is still paying.
4. Shops post the price; gifts check the heart requirement (5 for the white
   sword, 12 for the magical sword). The item is lifted for 128 frames. The other
   wares and the resident flicker for 64 frames, then disappear.
5. Hint caves charge, hide prices, and type the paid hint. Money-making games
   wait until Link has 10 rupees, reveal the three amounts with signs, and credit
   20 or 50 or debit 10 or 40. The amounts use the original permutation table.
   Secret money gives the middle price.

Gifts, the letter, door charges, and secret money remember being taken (`room/taken`).
Shops, hints, and games reset on every visit. The potion shop stays closed until the letter is shown.
Rupees change one per two frames, with the heart sound, as in `World_ChangeRupees`.
Inside caves Link cannot walk above Y $8E (`CheckPersonBlocking`).

## Entrances and exits

Overworld attribute B selects each room's destination. Portals sit where
`CheckWarps` would trigger: X on a 16-pixel boundary, Y = 16n + 13, standing on a
black ($24), $88, or stairs ($70-$73) square. Because movement carries across grid
points, a portal also triggers when a straight step crosses it. Leaving through a
cave mouth starts Link 16 pixels below the doorway. He rises one pixel every four
frames, drawn only within the doorway square, as in `StepOutside`. An entrance does
not trigger again until Link has moved off his arrival square. Stairs exits place
Link at attribute A/F's exit position.

Shortcut caves ("TAKE ANY ROAD YOU WANT!") have three stairways. Stairway *n* leads
*n* rooms further around the overworld cellar list ($1D, $23, $49, $79).

## Secrets

`SecretDefinition` describes the room's single tile object (`CheckTileObject`):

| Trigger | Original object | Reveal |
| --- | --- | --- |
| `bomb` | Rock wall $63 | Cave mouth at the wall, when a detonating bomb's center is within 16 pixels. Remembered. |
| `fire` | Tree $64 | Stairs at the tree, when a standing fire is about to go out within 16 pixels. Remembered. |
| `push` | Gravestone $65 | Pushed vertically away from Link; stairs at the shortcut position. Not remembered. |
| `bracelet_push` | Rock $62 | As a gravestone, but needs the power bracelet. Remembered unless a gravestone covers the stairs (`CheckShortcut`). |

Remembered reveals set `secret/<room id>`. Revealed squares replace the room's
atlas index and collision at runtime. Portals with `requires_secret` open only
afterwards. A sliding object holds Link back within 16 pixels
(`CheckTileObjectsBlocking`). Second-quest-only secrets stay ordinary terrain.

## Items and equipment

`ItemDefinition` follows `TakeItem`: `unique`, `grade` (only upgrades), `count`
(bombs stop at `GameState.max_bombs`), `heart_container`, `rupees`, and `health`.
Items sharing a `slot` replace or add to each other. `WeaponDefinition` is a graded
`sword` item. A better sword equips automatically and deals 1, 2, or 4 damage.

- Bombs: set 16 pixels ahead. Fuse 48 frames, blast 24, smoke 12. They deal four
  damage within 24 pixels. A second bomb waits for the first to detonate, and a
  bomb may replace a fire.
- Candle fire: walks 16 pixels at half a pixel per frame, then stands 63 frames.
  It deals one damage and also hurts Link. The blue candle works once per room.
- Rings halve (blue) or quarter (red) damage. Health keeps 128 units per half heart.
- Potions pause the game and refill six units a frame (`World_FillHearts`). The
  magical shield also blocks Lynel sword shots, Wizzrobe magic, and fireballs.
- Arrows (`WieldArrow`) need the bow and cost a rupee each. One flies at a time, 3
  pixels a frame, starting 16 pixels ahead (3 right when vertical). Wooden arrows deal 2,
  silver arrows 4, and any arrow kills Pols Voice. Arrows spark out at the room edge or on a hit.
- The boomerang (`WieldBoomerang`) flies along the held direction, diagonals
  included. The wooden one turns back after $31 pixels; the magical one only at walls or the
  room edge. It stuns monsters for $A0 frames (never Darknuts), kills monsters with
  no spare health (Keese, Gels), carries drops back, and returns to Link.
- The recorder (`WieldFlute`) halts Link for $98 frames. In room $42 of the first quest
  it then drains the pond over twelve eight-frame color steps. That reveals the
  remembered stairs to level 7 and makes water below tile $99 walkable. Elsewhere outdoors it
  calls the whirlwind, which sets Link down at the next level whose triforce he holds
  (`WhirlwindPrevRoomIdList`, `TeleportYs`). In dungeons it marks the room for Digdogger.

Native definitions live in `content/items`. The ROM tables only choose which
item a cave offers.

## Editable content and the item lab

Open `scenes/item_lab.tscn` and run it (F6); no ROM is needed. It is built from
editable resources: floor pickups (bombs, a blue candle, and a custom `rupee_purse`);
a custom shop selling a custom `big_bombs` satchel; a bombable wall leading to a
remembered heart-container gift; a burnable tree leading to a hint cave; and a
gravestone leading to a money-making game. Copy any resource under
`content/caves`, `content/items`, or `content/rooms` to make variants.

## Importer

`tools/import_caves.py` decodes the cave tables (`InitCave`), person texts,
overworld entrances, secrets, shortcut destinations, resident sprites, and item
sprites (`DrawItemBySlot`). Caves selling an item without a native definition are
refused rather than substituted. The manifest lists caves that still lack a
first-quest entrance (Armos, the recorder, or second-quest secrets). Older saves that
named `sword_cave` load through `WorldDefinition.legacy_ids`.

## Verification

- `tests/caves_and_items.gd`: item effects, rupee counting, every cave behavior,
  money-game permutations, the letter, bombs, fire, all push rules, saves, validation,
  and imported cave pairing, ROM prices, and secrets.
- `tests/test_caves.py`: flag decoding, text, entrances, secret persistence, and sprites.
- `tests/visual_preview.gd -- shop`, `bomb`, and `burned` render review screenshots.

## Known approximations

- Item-use pose is 16 ticks and push speed is half a pixel per tick; neither has
  been traced. The pond keeps its water color when drained, and the whirlwind's
  flight is not animated: Link is set down at the destination after the tune.
- Held white and magical swords use grade palettes on the wooden sword's tiles.
  Link's sprite does not change with the magical shield.
- Armos, raft, and ladder are not connected. Bait and the magical rod have no use
  yet. There is no submenu.
- Shortcut-room rocks follow the ROM's shortcut positions. Rooms $1D and $49 point
  at index 0, which has not been checked against an emulator.
