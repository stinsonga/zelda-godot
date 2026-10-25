class_name EnemyActor
extends RefCounted

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
var family = preload("res://scripts/overworld_enemy.gd").new()
var source = preload("res://scripts/nes_octorok.gd").new()
var waiting_spawn := false
var source_random := 0
var source_next_random := 0
var slot := 1
var drop_resolved := false
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
## A thrown boomerang is out; the thrower waits for it.
var shot_out := false
## Set when a Zol survives a hit; the combat simulation splits it.
var split_pending := false
## Like Like and Wallmaster: ticks spent holding Link; 0 when free.
var capture_ticks := 0
## The boomerang (and later the clock) freezes monsters for $A0 frames.
var stun_ticks := 0

func setup(spawn: Resource) -> void:
	id = spawn.id
	definition = spawn.enemy
	health = definition.health
	subposition = spawn.position * 256
	facing = spawn.facing
	rng.seed = spawn.seed_value
	spawn_remaining = definition.spawn_ticks if spawn.spawn_ticks < 0 else spawn.spawn_ticks
	cooldown = definition.shoot_cooldown
	if definition.behavior != "native":
		source.setup(definition.nes_type)
		spawn_remaining += 12
		if definition.behavior != "nes_octorok": source.move_speed = definition.speed_subpixels
		if not definition.spawn_cloud: spawn_remaining = 0

func position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

## Hit checks compare 16-pixel shapes; larger monsters are measured from their middle.
func hit_position() -> Vector2i:
	return position() + (definition.size - Vector2i(16, 16)) / 2

## Several shots fired in one tick (Aquamentus): {kind, position, spread}.
var pending_shots: Array[Dictionary] = []

func alive() -> bool:
	return health > 0 and spawn_remaining == 0 and not waiting_spawn

func hurtbox() -> Rect2i:
	return Rect2i(position() + Vector2i(2, 2), Vector2i(12, 12))

## Z_01 HandleMonsterWeaponCollision. Returns false for misses and parries;
## parried() reports a parry so the caller can play the sound.
var parried_hit := false

func receive_hit(damage: int, direction: Vector2i, kind: String = "sword") -> bool:
	parried_hit = false
	if not targetable() or invulnerability > 0:
		return false
	# Darknuts parry weapons arriving head-on; masks parry whole damage types.
	if kind in definition.invincible_to or (definition.front_shield and direction == -facing):
		parried_hit = true
		return false
	health = maxi(0, health - damage)
	invulnerability = 32
	windup = 0
	source.shove_started = false
	shove_direction = direction
	shove_remaining = 64
	if health == 0:
		death_remaining = 19 if definition.behavior != "native" else 12
	elif definition.splits_into != null:
		split_pending = true
	return true

## Returns true on the frame a rock should be emitted.
func tick(target: Vector2i, can_occupy: Callable, segment_probe: Callable = Callable(), can_shoot: bool = true, context: Dictionary = {}) -> bool:
	if waiting_spawn: return false
	if spawn_remaining > 0:
		spawn_remaining -= 1
		return false
	if health <= 0:
		death_remaining = maxi(0, death_remaining - 1)
		return false
	animation_ticks += 1
	invulnerability = maxi(0, invulnerability - 1)
	if stun_ticks > 0:
		stun_ticks -= 1
		return false
	if definition.behavior != "native":
		var probe := segment_probe
		if not probe.is_valid(): probe = func(at: Vector2i, direction: Vector2i) -> bool: return can_occupy.call(at + direction * 16)
		if definition.behavior in ["nes_octorok", "walker"]:
			# A capturing Like Like stays on Link instead of walking.
			if capture_ticks > 0: return false
			var shot: bool = source.tick(self, target, probe, can_shoot, source_random, source_next_random)
			if definition.hops and facing.x != 0 and shove_remaining == 0:
				subposition.y += family.VIRE_HOPS[absi(source.grid_offset) % 16] * 256
			return shot
		return family.tick(self, target, probe, context)
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
	var remaining: int = definition.speed_subpixels
	while remaining > 0:
		var at := position()
		var coordinate := subposition.x if facing.x != 0 else subposition.y - 13 * 256
		var phase := posmod(coordinate, 4096)
		if phase == 0:
			var choices: Array[Vector2i] = []
			for direction in DIRECTIONS:
				var clear := true
				for distance in range(1, 17):
					if not can_occupy.call(at + direction * distance):
						clear = false
						break
				if clear: choices.append(direction)
			if choices.is_empty(): return false
			var delta := target - at
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
			coordinate = subposition.x if facing.x != 0 else subposition.y - 13 * 256
			phase = posmod(coordinate, 4096)
		var to_boundary := 4096 - phase if facing.x + facing.y > 0 else phase
		if to_boundary == 0: to_boundary = 4096
		var amount := mini(remaining, mini(256, to_boundary))
		var candidate := subposition + facing * amount
		var pixel := Vector2i(floori(candidate.x / 256.0), floori(candidate.y / 256.0))
		if not can_occupy.call(pixel):
			# A surviving enemy can be left between grid points by a shove.
			# Back out along the same axis rather than turning off-grid.
			facing = -facing
			return false
		subposition = candidate
		remaining -= amount
	return false

func targetable() -> bool:
	return alive() and family.vulnerable(self)

func can_touch_player() -> bool:
	return alive() and family.contact_enabled(self)

func body_visible() -> bool:
	return family.visible(self)

func sprite_name() -> StringName:
	if definition.behavior in ["jumper", "burrower", "flyer"]:
		return StringName(String(definition.sprite) + "_" + str(family.frame(self)))
	if definition.sprite_style == "frames":
		return StringName(String(definition.sprite) + "_" + str((animation_ticks / definition.animation_frame_ticks) % 2))
	var direction := "right" if facing.x > 0 else "left" if facing.x < 0 else "down" if facing.y > 0 else "up"
	return StringName(String(definition.sprite) + "_" + direction + "_" + str((animation_ticks / 6) % 2))
