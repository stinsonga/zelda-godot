class_name RoomTransition
extends RefCounted

var source: Resource
var target: Resource
var source_position := Vector2i.ZERO
var destination := Vector2i.ZERO
var direction := Vector2i.RIGHT
var distance := 0
var ticks := 0

func length() -> int:
	return 256 if direction.x != 0 else 176

func tick() -> bool:
	ticks += 1
	if direction.x != 0:
		distance = mini(length(), distance + 4)
	elif ticks % 2 == 0:
		distance = mini(length(), distance + 8)
	return distance == length()

func player_position() -> Vector2i:
	var at := source_position - direction * distance
	if direction.x > 0: at.x = maxi(destination.x, at.x)
	elif direction.x < 0: at.x = mini(destination.x, at.x)
	elif direction.y > 0: at.y = maxi(destination.y, at.y)
	else: at.y = mini(destination.y, at.y)
	return at
