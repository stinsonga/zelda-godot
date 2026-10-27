class_name SwordAction
extends RefCounted

var beam_attempted := false
var weapon: Resource
var direction := Vector2i.UP
var ticks_left := 0
var phase := -1

func active() -> bool:
	return phase >= 0

func start(definition: Resource, facing: Vector2i) -> bool:
	if active() or definition == null:
		return false
	beam_attempted = false
	weapon = definition
	direction = facing
	phase = 0
	ticks_left = weapon.phase_ticks[0]
	# Z_07 UpdateSwordOrRod also runs on the frame WieldSword starts the sword.
	tick()
	return true

func tick() -> void:
	if not active():
		return
	ticks_left -= 1
	if ticks_left > 0:
		return
	phase += 1
	if phase >= weapon.phase_ticks.size():
		phase = -1
		return
	ticks_left = weapon.phase_ticks[phase]

func visible() -> bool:
	return phase >= 1 and phase <= 3

func damaging() -> bool:
	return phase == 1

func offset() -> Vector2i:
	if not visible():
		return Vector2i.ZERO
	var index := 0
	if direction == Vector2i.DOWN: index = 1
	elif direction == Vector2i.LEFT: index = 2
	elif direction == Vector2i.RIGHT: index = 3
	index += phase * 4
	return Vector2i(weapon.offsets_x[index], weapon.offsets_y[index])

func hitbox(player_position: Vector2i) -> Rect2i:
	if not damaging():
		return Rect2i()
	var position := player_position + offset()
	return Rect2i(position + Vector2i(4, 0), Vector2i(8, 16)) if direction.x == 0 else Rect2i(position, Vector2i(16, 8))

func hits(player_position: Vector2i, enemy_position: Vector2i) -> bool:
	if not damaging(): return false
	var vertical := direction.x == 0
	var weapon_center := player_position + offset() + (Vector2i(6, 8) if vertical else Vector2i(8, 6))
	var distance := (enemy_position + Vector2i(8, 8) - weapon_center).abs()
	# Z_01 CheckMonsterStabbingCollision: strict thresholds, not sprite bounds.
	return distance.x < (12 if vertical else 16) and distance.y < (16 if vertical else 12)
