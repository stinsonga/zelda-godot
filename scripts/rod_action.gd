class_name RodAction
extends "res://scripts/sword_action.gd"
## Z_01 CheckMonsterArrowOrRodCollision checks every active rod state,
## unlike the sword's state-2-only thrust. State 5 retains the previous position.
func damaging() -> bool:
	return active()

func offset() -> Vector2i:
	if not active(): return Vector2i.ZERO
	var index := 0
	if direction == Vector2i.DOWN: index = 1
	elif direction == Vector2i.LEFT: index = 2
	elif direction == Vector2i.RIGHT: index = 3
	index += mini(phase, 3) * 4
	return Vector2i(weapon.offsets_x[index], weapon.offsets_y[index])
