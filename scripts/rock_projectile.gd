class_name RockProjectile
extends RefCounted
var subposition := Vector2i.ZERO
var direction := Vector2i.RIGHT
var speed_subpixels := 512
var alive := true

func position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

func hurtbox() -> Rect2i:
	return Rect2i(position() + Vector2i(4, 4), Vector2i(8, 8))
