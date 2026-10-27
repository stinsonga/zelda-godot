class_name RoomTransition
extends RefCounted

var source: Resource
var target: Resource
var source_position := Vector2i.ZERO
var destination := Vector2i.ZERO
var direction := Vector2i.RIGHT
var distance := 0
var ticks := 0
## The lead and tail are measured in the overworld; dungeon transitions keep the
## bare scroll until they are measured too.
var overworld := true

## The NES spends frames before and after the visible scroll: mode 6 (leave),
## InitMode7 (laying out the next room a row per frame), UpdateMode7Scroll's
## other submodes, and mode 4 (enter). Measured against the NES, per direction:
## ticks before the scroll starts, and ticks after it until free play, the last
## of which is the first free frame. Totals are 104 frames horizontally, 85 up,
## and 83 down, counted from the frame the transition begins.
const LEAD_TICKS := {Vector2i.RIGHT: 32, Vector2i.LEFT: 32, Vector2i.UP: 33, Vector2i.DOWN: 32}
const TAIL_TICKS := {Vector2i.RIGHT: 8, Vector2i.LEFT: 8, Vector2i.UP: 8, Vector2i.DOWN: 7}

func length() -> int:
	return 256 if direction.x != 0 else 176

## Ticks of visible scrolling: four pixels a frame across, eight every other
## frame up or down.
func scroll_ticks() -> int:
	return 64 if direction.x != 0 else 44

func lead_ticks() -> int:
	return LEAD_TICKS[direction] if overworld else 0

func total_ticks() -> int:
	return lead_ticks() + scroll_ticks() + (TAIL_TICKS[direction] if overworld else 0)

func tick() -> bool:
	ticks += 1
	var scrolled: int = ticks - lead_ticks()
	if scrolled > 0:
		if direction.x != 0:
			distance = mini(length(), distance + 4)
		elif scrolled % 2 == 0:
			distance = mini(length(), distance + 8)
	return ticks >= total_ticks()

func player_position() -> Vector2i:
	var at := source_position - direction * distance
	if direction.x > 0: at.x = maxi(destination.x, at.x)
	elif direction.x < 0: at.x = mini(destination.x, at.x)
	elif direction.y > 0: at.y = maxi(destination.y, at.y)
	else: at.y = mini(destination.y, at.y)
	return at
