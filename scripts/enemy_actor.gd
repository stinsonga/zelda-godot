class_name EnemyActor
extends RefCounted

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
var definition: Resource
var id: StringName
var subposition := Vector2i.ZERO
var facing := Vector2i.DOWN
var health := 1
var spawn_remaining := 0
var death_remaining := 0
var invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO
var animation_ticks := 0
var cooldown := 0
var windup := 0
var rng := RandomNumberGenerator.new()

func setup(spawn: Resource) -> void:
	id = spawn.id
	definition = spawn.enemy
	health = definition.health
	subposition = spawn.position * 256
	facing = spawn.facing
	rng.seed = spawn.seed_value
	spawn_remaining = definition.spawn_ticks
	cooldown = definition.shoot_cooldown

func position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

func alive() -> bool:
	return health > 0 and spawn_remaining == 0

func hurtbox() -> Rect2i:
	return Rect2i(position() + Vector2i(2, 2), Vector2i(12, 12))

func receive_hit(damage: int, direction: Vector2i) -> bool:
	if not alive() or invulnerability > 0:
		return false
	health = maxi(0, health - damage)
	invulnerability = 32
	windup = 0
	shove_direction = direction
	shove_remaining = 64
	if health == 0:
		death_remaining = 12
	return true

## Returns true on the frame a rock should be emitted.
func tick(target: Vector2i, can_occupy: Callable) -> bool:
	if spawn_remaining > 0:
		spawn_remaining -= 1
		return false
	if health <= 0:
		death_remaining = maxi(0, death_remaining - 1)
		return false
	animation_ticks += 1
	invulnerability = maxi(0, invulnerability - 1)
	if shove_remaining > 0:
		for pixel in range(mini(4, shove_remaining)):
			var candidate := position() + shove_direction
			if not can_occupy.call(candidate):
				shove_remaining = 0
				break
			subposition += shove_direction * 256
			shove_remaining -= 1
		return false
	if windup > 0:
		windup -= 1
		if windup == 0:
			cooldown = definition.shoot_cooldown
			return true
		return false
	cooldown = maxi(0, cooldown - 1)
	var at := position()
	var delta := target - at
	# Recover grid phase after a shove; no sideways snapping through terrain.
	var phase := posmod(subposition.x if facing.x != 0 else subposition.y - 13 * 256, 16 * 256)
	if phase == 0 or not can_occupy.call(at + facing):
		var choices: Array[Vector2i] = []
		for direction in DIRECTIONS:
			if can_occupy.call(at + direction * 16): choices.append(direction)
		if choices.is_empty(): return false
		var aimed := Vector2i.ZERO
		if absi(delta.x) < 9: aimed = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
		elif absi(delta.y) < 9: aimed = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
		if aimed in choices and rng.randi_range(0, 255) <= definition.turn_chance:
			facing = aimed
			if cooldown == 0 and definition.shoot_cooldown > 0:
				windup = definition.shoot_windup
				return false
		elif facing not in choices or rng.randi_range(0, 255) < 48:
			facing = choices[rng.randi_range(0, choices.size() - 1)]
	var remaining: int = definition.speed_subpixels
	while remaining > 0:
		var amount := mini(256, remaining)
		var candidate := subposition + facing * amount
		var pixel := Vector2i(floori(candidate.x / 256.0), floori(candidate.y / 256.0))
		if not can_occupy.call(pixel): break
		subposition = candidate
		remaining -= amount
	return false
