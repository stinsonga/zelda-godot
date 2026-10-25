class_name SwordBeam
extends RefCounted

const SPEED := 3
const BURST_TICKS := 22
var position := Vector2i.ZERO
var direction := Vector2i.UP
var damage := 1
var burst_remaining := 0
var finished := false

func flying() -> bool:
	return not finished and burst_remaining == 0

func impact() -> void:
	if flying(): burst_remaining = BURST_TICKS

func hits(enemy_position: Vector2i) -> bool:
	if not flying(): return false
	var center := position + (Vector2i(6, 8) if direction.x == 0 else Vector2i(8, 6))
	var distance := (enemy_position + Vector2i(8, 8) - center).abs()
	return distance.x < 12 and distance.y < 12
