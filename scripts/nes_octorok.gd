class_name NesOctorok
extends RefCounted
## Source-order walker/target/shoot state. Random bytes are injected per slot.
var grid_offset := 0
var turn_timer := 0
var shoot_timer := 0
var wants_to_shoot := false
var move_speed := 128
var shove_started := false
## ObjInputDir: the direction Walker_Move moves in. It is 0 for a new monster and
## takes the facing only at the end of each update.
var input_direction := Vector2i.ZERO

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

## Z_07 Walker_CheckTileCollision: keep the moving direction if walkable; else
## Walker_GetNextAltDir tries a random perpendicular to the facing, then the
## opposite of the moving direction (TryNextDir has just made that the rejected
## perpendicular), then the reversed facing. A new monster's moving direction is
## 0 (ObjInputDir), so it starts with the search.
func choose_movement(actor: RefCounted, probe: Callable, random_byte: int, moving: Vector2i = Vector2i(2, 2)) -> Vector2i:
	var original: Vector2i = actor.facing
	if moving == Vector2i(2, 2): moving = original
	if moving != Vector2i.ZERO and probe.call(actor.position(), moving): return moving
	var perpendicular := Vector2i.UP if random_byte & 128 else Vector2i.DOWN
	if original.y != 0: perpendicular = Vector2i.LEFT if random_byte & 128 else Vector2i.RIGHT
	for direction in [perpendicular, -perpendicular, -original]:
		if probe.call(actor.position(), direction):
			actor.facing = direction
			return direction
	actor.facing = -original
	return Vector2i.ZERO

## ObjPosFrac: one fraction byte shared by both axes.
var fraction := 0

## Walker speeds under a pixel a frame follow Z_07 MoveObject: four quarter-steps
## into the shared fraction, a pixel per carry unless the grid offset is at +-16
## (the monster limit). Whole-pixel moves (shoves, jumps) go straight through.
func advance_position(actor: RefCounted, direction: Vector2i, distance: int) -> void:
	if distance < 256 and distance % 4 == 0 and direction != Vector2i.ZERO:
		var forward := direction.x + direction.y > 0
		var pixel: Vector2i = actor.position()
		for quarter in range(4):
			fraction += distance / 4 if forward else -distance / 4
			var carry := fraction >= 256 if forward else fraction < 0
			fraction = posmod(fraction, 256)
			if carry and absi(grid_offset) != 16:
				pixel += direction
				grid_offset += 1 if forward else -1
		actor.subposition = pixel * 256
		if grid_offset != 0 and grid_offset % 16 == 0: grid_offset = 0
		return
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
	if actor.definition.targeting == "dominant_axis":
		wants_to_shoot = false
		if maxi(absi(delta.x), absi(delta.y)) < 81:
			actor.facing = (Vector2i.DOWN if delta.y >= 0 else Vector2i.UP) if absi(delta.y) >= absi(delta.x) else (Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT)
			wants_to_shoot = true
		return
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
	if shoot_timer > 0 and actor.definition.projectile_kind == "boomerang": shoot_timer -= 1
	# Z_04 UpdateGoriya: state $80 waits, unmoving, until the boomerang returns.
	if actor.shot_out: return false
	if turn_timer > 0: turn_timer -= 1
	if actor.shove_remaining > 0:
		shove(actor, probe)
		return false
	shove_started = false
	# Walker_Move occurs before target selection and _TryShooting.
	if move_speed > 0:
		var direction: Vector2i = input_direction
		if grid_offset == 0: direction = choose_movement(actor, probe, random_byte, input_direction)
		if direction != Vector2i.ZERO: advance_position(actor, direction, move_speed)
	select_target(actor, target, random_byte, next_random)
	# L_Walker_SetInputDirAndTryShooting*: the facing becomes the next input.
	input_direction = actor.facing
	if actor.definition.projectile_kind == "boomerang":
		return throw_boomerang(actor, can_shoot, random_byte)
	if not actor.definition.shooting_enabled or actor.definition.shoot_cooldown <= 0:
		shoot_timer = 0
		move_speed = actor.definition.speed_subpixels
		return false
	# Red Octoroks only begin the timer when Random[X] >= $F8; blue bypasses it.
	var threshold: int = actor.definition.shooting_threshold
	if threshold < 0: threshold = 0 if actor.definition.nes_type in [1, 3, 9, 10] else 248
	if shoot_timer == 0 and random_byte < threshold: return false
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

## Z_04 L_Walker_SetInputDirAndTryShootingBoomerang: blue Goriyas throw whenever
## ready; red ones only on chosen random bytes. Afterwards wait up to $3F frames.
func throw_boomerang(actor: RefCounted, can_shoot: bool, random_byte: int) -> bool:
	if not actor.definition.shooting_enabled or shoot_timer > 0 or not wants_to_shoot or not can_shoot: return false
	var values: PackedInt32Array = actor.definition.shoot_random_values
	if not values.is_empty() and random_byte not in values: return false
	wants_to_shoot = false
	shoot_timer = random_byte & 0x3F
	return true
