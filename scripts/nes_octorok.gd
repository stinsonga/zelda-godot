class_name NesOctorok
extends RefCounted
## Source-order walker/target/shoot state. Random bytes are injected per slot.
var grid_offset := 0
var turn_timer := 0
var shoot_timer := 0
var wants_to_shoot := false
var move_speed := 128
var shove_started := false

func setup(enemy_type: int) -> void:
	move_speed = 192 if enemy_type in [8, 10] else 128

func initialize_facing(actor: RefCounted, target: Vector2i) -> void:
	if actor.facing != Vector2i.ZERO: return
	var at: Vector2i = actor.position()
	var dx := (target.x - at.x) & 255
	var dy := (target.y - at.y) & 255
	actor.facing = Vector2i.DOWN if target.y >= at.y else Vector2i.UP
	if dy >= dx:
		actor.facing = Vector2i.LEFT if target.x >= at.x else Vector2i.RIGHT

func choose_movement(actor: RefCounted, probe: Callable, random_byte: int) -> Vector2i:
	var original: Vector2i = actor.facing
	if probe.call(actor.position(), original): return original
	var perpendicular := Vector2i.UP if random_byte & 128 else Vector2i.DOWN
	if original.y != 0: perpendicular = Vector2i.LEFT if random_byte & 128 else Vector2i.RIGHT
	for direction in [perpendicular, -perpendicular, -original]:
		if probe.call(actor.position(), direction):
			actor.facing = direction
			return direction
	actor.facing = -original
	return Vector2i.ZERO

func advance_position(actor: RefCounted, direction: Vector2i, distance: int) -> void:
	var before: Vector2i = actor.position()
	actor.subposition += direction * distance
	var delta: Vector2i = actor.position() - before
	grid_offset += delta.x + delta.y
	if absi(grid_offset) >= 16: grid_offset %= 16

func shove(actor: RefCounted, probe: Callable) -> void:
	if not shove_started:
		shove_started = true
		if grid_offset != 0 and actor.facing.x * actor.shove_direction.x + actor.facing.y * actor.shove_direction.y == 0:
			actor.shove_remaining = 0
		return
	for pixel in range(mini(4, actor.shove_remaining)):
		if grid_offset == 0 and not probe.call(actor.position(), actor.shove_direction):
			actor.shove_remaining = 0
			return
		advance_position(actor, actor.shove_direction, 256)
		actor.shove_remaining -= 1

func select_target(actor: RefCounted, target: Vector2i, random_byte: int, next_random: int) -> void:
	if move_speed == 0 or grid_offset != 0: return
	var delta: Vector2i = target - actor.position()
	var aimed := Vector2i.ZERO
	if next_random <= actor.definition.turn_chance:
		if absi(delta.x) < 9: aimed = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
		elif absi(delta.y) < 9: aimed = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
	if aimed == Vector2i.ZERO:
		wants_to_shoot = false
		if turn_timer != 0: return
		if actor.facing.y != 0: aimed = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
		else: aimed = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
	actor.facing = aimed
	turn_timer = random_byte
	wants_to_shoot = true

func tick(actor: RefCounted, target: Vector2i, probe: Callable, can_shoot: bool, random_byte: int, next_random: int) -> bool:
	initialize_facing(actor, target)
	if turn_timer > 0: turn_timer -= 1
	if actor.shove_remaining > 0:
		shove(actor, probe)
		return false
	shove_started = false
	# Walker_Move occurs before target selection and _TryShooting.
	if move_speed > 0:
		var direction: Vector2i = actor.facing
		if grid_offset == 0: direction = choose_movement(actor, probe, random_byte)
		if direction != Vector2i.ZERO: advance_position(actor, direction, move_speed)
	select_target(actor, target, random_byte, next_random)
	if not actor.definition.shooting_enabled or actor.definition.shoot_cooldown <= 0:
		shoot_timer = 0
		move_speed = actor.definition.speed_subpixels
		return false
	# Red Octoroks only begin the timer when Random[X] >= $F8; blue bypasses it.
	if actor.definition.nes_type < 9 and shoot_timer == 0 and random_byte < 0xF8: return false
	if actor.invulnerability > 0: shoot_timer = 0
	elif shoot_timer > 0: shoot_timer -= 1
	elif wants_to_shoot: shoot_timer = 0x30
	move_speed = actor.definition.speed_subpixels
	if shoot_timer == 0: return false
	move_speed = 0
	if shoot_timer == 0x10 and wants_to_shoot and can_shoot:
		wants_to_shoot = false
		return true
	return false
