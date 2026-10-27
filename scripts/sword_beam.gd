class_name SwordBeam
extends RefCounted

const SPEED := 3
const BURST_TICKS := 22
var position := Vector2i.ZERO
var direction := Vector2i.UP
var damage := 1
## Sword and rod shots share slot $0E. Magic uses its own damage type.
var kind := "beam"
var speed_subpixels := 768
var fraction := 0
var burst_remaining := 0
var finished := false

func flying() -> bool:
	return not finished and burst_remaining == 0

func impact() -> void:
	if flying(): burst_remaining = BURST_TICKS

## Z_01 CheckMonsterSlenderWeaponCollision2 offsets the shot by Link's facing,
## not its own direction, so a shot sent up checks wider once Link turns sideways.
func hits(enemy_position: Vector2i, link_facing: Vector2i = Vector2i.ZERO) -> bool:
	if not flying(): return false
	var facing := direction if link_facing == Vector2i.ZERO else link_facing
	var center := position + (Vector2i(6, 8) if facing.x == 0 else Vector2i(8, 6))
	var distance := (enemy_position + Vector2i(8, 8) - center).abs()
	return distance.x < 12 and distance.y < 12
