class_name RoomTransition
extends RefCounted

var source: Resource
var target: Resource
var source_position := Vector2i.ZERO
var destination := Vector2i.ZERO
var direction := Vector2i.RIGHT
var distance := 0
var ticks := 0
## Dungeons scroll at half speed with their own lead, tail, and lag frames.
var overworld := true

## The NES spends frames before and after the visible scroll: mode 6 (leave),
## InitMode7 (laying out the next room a row per frame), UpdateMode7Scroll's
## other submodes, and mode 4 (enter). Measured against the NES, per direction:
## ticks before the scroll starts, and ticks after it until free play, the last
## of which is the first free frame. Totals are 104 frames horizontally, 85 up,
## and 83 down, counted from the frame the transition begins.
const LEAD_TICKS := {Vector2i.RIGHT: 32, Vector2i.LEFT: 32, Vector2i.UP: 33, Vector2i.DOWN: 32}
const TAIL_TICKS := {Vector2i.RIGHT: 8, Vector2i.LEFT: 8, Vector2i.UP: 8, Vector2i.DOWN: 7}
## Lag frames, also measured: laying out the next room takes the NES two frames
## longer than one, and the NMI skips its random and timer updates on them.
const LAG_TICKS := {Vector2i.RIGHT: [5, 6], Vector2i.LEFT: [5, 6], Vector2i.UP: [30, 31], Vector2i.DOWN: [5, 6]}
## In a dungeon the scroll is two pixels a frame across and a row every fourth
## frame up or down (Z_05 ScrollWorld), and laying out the room lags three frames.
## The tail's last tick is mode 4's first, which sets the entry walk (Z_05
## InitMode_EnterRoom); the walk and the settling frame follow as in free play.
## Measured horizontally in level 1: 180 frames to the end of the walk. The
## vertical values follow the overworld's differences and are not yet measured.
const DUNGEON_LEAD_TICKS := {Vector2i.RIGHT: 34, Vector2i.LEFT: 34, Vector2i.UP: 35, Vector2i.DOWN: 34}
const DUNGEON_TAIL_TICKS := {Vector2i.RIGHT: 7, Vector2i.LEFT: 7, Vector2i.UP: 7, Vector2i.DOWN: 6}
const DUNGEON_LAG_TICKS := {Vector2i.RIGHT: [6, 7, 8], Vector2i.LEFT: [6, 7, 8], Vector2i.UP: [31, 32, 33], Vector2i.DOWN: [6, 7, 8]}

func length() -> int:
	return 256 if direction.x != 0 else 176

## Ticks of visible scrolling: in the overworld four pixels a frame across, eight
## every other frame up or down; dungeons take twice as long.
func scroll_ticks() -> int:
	return (64 if direction.x != 0 else 44) * (1 if overworld else 2)

## Whether the coming tick is a lag frame.
func lags_next() -> bool:
	return (ticks + 1) in (LAG_TICKS if overworld else DUNGEON_LAG_TICKS)[direction]

func lead_ticks() -> int:
	return (LEAD_TICKS if overworld else DUNGEON_LEAD_TICKS)[direction]

func total_ticks() -> int:
	return lead_ticks() + scroll_ticks() + (TAIL_TICKS if overworld else DUNGEON_TAIL_TICKS)[direction]

func tick() -> bool:
	ticks += 1
	var scrolled: int = ticks - lead_ticks()
	if scrolled > 0 and scrolled <= scroll_ticks():
		if direction.x != 0:
			distance = mini(length(), distance + (4 if overworld else 2))
		elif scrolled % (2 if overworld else 4) == 0:
			distance = mini(length(), distance + 8)
	return ticks >= total_ticks()

func player_position() -> Vector2i:
	var at := source_position - direction * distance
	if direction.x > 0: at.x = maxi(destination.x, at.x)
	elif direction.x < 0: at.x = mini(destination.x, at.x)
	elif direction.y > 0: at.y = maxi(destination.y, at.y)
	else: at.y = mini(destination.y, at.y)
	return at
