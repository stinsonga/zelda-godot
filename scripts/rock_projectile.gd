class_name RockProjectile
extends RefCounted
var subposition := Vector2i.ZERO
var direction := Vector2i.RIGHT
var speed_subpixels := 512
var kind := "rock"
var damage := 1
var blockable := true
var source_rules := false
var age := 0
var bounce_remaining := 0
var bounce_direction := Vector2i.UP
var alive := true
## Boomerangs: the thrower, pixels flown, and whether they are coming back.
var owner: RefCounted
var travelled := 0
var returning := false
## Fireballs: subpixels per tick on each axis (direction holds the signs).
var velocity := Vector2i.ZERO

func position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

func hurtbox() -> Rect2i:
	return Rect2i(position() + Vector2i(4, 4), Vector2i(8, 8))
