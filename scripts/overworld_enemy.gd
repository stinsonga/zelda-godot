class_name OverworldEnemy
extends RefCounted
## Family state stays on the actor; shared editable definitions stay immutable.
const DIRS := [Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1), Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]
var initialized := false
var phase := 0
var timer := 0
var velocity_y := 0
var target_y := 0
var jump_direction := Vector2i.RIGHT
var flight_speed := 31
var flight_fraction := 0
var distance := 0
var turns := 0
var anim_ticks := 0
var pose := 0

func initialize(actor: RefCounted) -> void:
	initialized = true
	if actor.definition.behavior == "jumper":
		var index: int = actor.source_next_random & 3
		jump_direction = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i(1,1), Vector2i(-1,-1)][index]
		timer = [4,8,20,40][index]
	elif actor.definition.behavior == "flyer":
		actor.facing = Vector2i.UP

func visible(actor: RefCounted) -> bool:
	return actor.definition.behavior != "burrower" or phase != 0

func vulnerable(actor: RefCounted) -> bool:
	if actor.definition.behavior == "burrower": return phase == 3
	if actor.definition.behavior == "flyer": return phase == 5
	return true

func contact_enabled(actor: RefCounted) -> bool:
	return actor.definition.behavior != "burrower" or phase == 3

func frame(actor: RefCounted) -> int:
	if actor.definition.behavior == "jumper": return 1 if phase == 1 else 0 if timer < 33 else (actor.animation_ticks / 16) % 2
	if actor.definition.behavior == "burrower": return maxi(0, phase - 1) * 2 + pose
	return distance & 1

func turn_toward(current: Vector2i, at: Vector2i, target: Vector2i) -> Vector2i:
	var desired := Vector2i(signi(target.x-at.x), signi(target.y-at.y))
	var index: int = maxi(0, DIRS.find(current))
	for offset in [1,0,-1]:
		if DIRS[posmod(index+offset,8)] == desired: return current
	# Translate TurnTowardsPlayer8's component/combined-direction test.
	var desired_bits := bits(desired)
	for offset in [-1,0,1]:
		var next: Vector2i = DIRS[posmod(index+offset,8)]
		if bits(next) & desired_bits and (bits(next) | desired_bits) < 7: return next
	return DIRS[posmod(index+1,8)]

func bits(direction: Vector2i) -> int:
	return (1 if direction.x > 0 else 2 if direction.x < 0 else 0) | (4 if direction.y > 0 else 8 if direction.y < 0 else 0)

func bound(actor: RefCounted) -> bool:
	var at: Vector2i = actor.position()
	if (at.x < 17 and actor.facing.x < 0) or (at.x >= 224 and actor.facing.x > 0) or (at.y < 14 and actor.facing.y < 0) or (at.y >= 141 and actor.facing.y > 0):
		actor.facing = -actor.facing
		return false
	return true

func tick(actor: RefCounted, target: Vector2i, probe: Callable, context: Dictionary) -> void:
	if not initialized: initialize(actor)
	if timer > 0: timer -= 1
	if actor.source.turn_timer > 0: actor.source.turn_timer -= 1
	if actor.shove_remaining > 0:
		actor.source.shove(actor, probe)
		return
	actor.source.shove_started = false
	match actor.definition.behavior:
		"jumper": tick_jump(actor, target)
		"burrower": tick_burrow(actor, target, probe, context)
		"flyer": tick_flight(actor, target)

func begin_jump(actor: RefCounted) -> void:
	var definition: Resource = actor.definition
	target_y = clampi(actor.position().y + jump_direction.y * definition.jump_target_offset, 13, 141)
	velocity_y = definition.jump_velocity_subpixels
	phase = 1
	actor.facing = jump_direction

func tick_jump(actor: RefCounted, target: Vector2i) -> void:
	var definition: Resource = actor.definition
	if phase == 0:
		if timer > 0: return
		jump_direction = turn_toward(jump_direction, actor.position(), target)
		if jump_direction.x == 0: jump_direction.x = 1 if target.x >= actor.position().x else -1
		begin_jump(actor)
		return
	actor.facing = jump_direction
	if not bound(actor):
		jump_direction = actor.facing
		begin_jump(actor)
		return
	# NES stores whole Y separately from fractional acceleration.
	actor.subposition.y += floori(velocity_y / 256.0) * 256
	var acceleration: int = definition.jump_horizontal_acceleration if jump_direction.y == 0 else definition.jump_up_acceleration if jump_direction.y < 0 else definition.jump_down_acceleration
	velocity_y = mini(512, velocity_y + acceleration)
	actor.subposition.x += jump_direction.x * definition.speed_subpixels
	if velocity_y >= 0 and absi(actor.position().y-target_y) < 3:
		phase = 0
		var random_byte: int = actor.source_next_random
		timer = (random_byte + 16) & 255
		if timer < 32: timer = (timer - 64) & 255
		if definition.jump_wait_style == "red":
			timer &= 127
			if random_byte >= 160: timer &= 15

func cycle_burrow(actor: RefCounted) -> void:
	phase = (phase + 1) % 6
	timer = actor.definition.burrow_times[phase]
	pose = 0
	anim_ticks = 0

func tick_burrow(actor: RefCounted, target: Vector2i, probe: Callable, context: Dictionary) -> void:
	var definition: Resource = actor.definition
	var ambush: bool = definition.burrow_style == "ambush"
	if ambush and phase == 0:
		if int(context.get("ambush_timer",0)) > 0 or int(context.get("active_ambush",0)) >= 2: return
		var facing: Vector2i = context.get("player_facing",Vector2i.UP)
		if actor.source_next_random >= 192: facing = -facing
		var at: Vector2i = context.get("player",target)
		at += facing * definition.ambush_distance
		if facing.x != 0: at.x &= 248
		else: at.y = (((at.y+64)&240)|13)-64
		if at.x < 0 or at.x > 239 or at.y < 29 or at.y > 141 or not context.spawn_allowed.call(at): return
		actor.subposition = at * 256
		actor.facing = -facing
		actor.source.grid_offset = 0
		cycle_burrow(actor)
		context.active_ambush = int(context.get("active_ambush",0)) + 1
		context.ambush_timer = 20
	elif timer == 0:
		cycle_burrow(actor)
		if ambush and phase == 0: return
	actor.source.move_speed = definition.burrow_speeds[phase]
	if ambush:
		if phase == 3:
			if not probe.call(actor.position(),actor.facing): cycle_burrow(actor)
			else:
				actor.source.advance_position(actor,actor.facing,definition.burrow_speeds[3])
				timer = definition.burrow_times[3]
	else:
		actor.source.initialize_facing(actor,target)
		if actor.source.move_speed > 0:
			var direction: Vector2i = actor.facing
			if actor.source.grid_offset == 0: direction = actor.source.choose_movement(actor,probe,actor.source_random)
			actor.source.advance_position(actor,direction,actor.source.move_speed)
		actor.source.select_target(actor,target,actor.source_random,actor.source_next_random)
	anim_ticks += 1
	if anim_ticks >= definition.burrow_animation_ticks[phase]:
		anim_ticks = 0
		pose ^= 1

func tick_flight(actor: RefCounted, target: Vector2i) -> void:
	var definition: Resource = actor.definition
	match phase:
		0:
			flight_speed += definition.flight_acceleration
			if (flight_speed & 224) == 0:
				phase = 5
				timer = definition.flight_rest_min + (actor.source_random & definition.flight_rest_random_mask)
			elif (flight_speed & 224) >= definition.flight_max_speed: phase = 1
		1:
			phase = 2 if actor.source_random >= 176 else 3 if actor.source_random >= 32 else 4
			turns = definition.flight_turn_count
		2,3:
			if timer == 0:
				turns -= 1
				if turns == 0: phase = 1
				else:
					timer = definition.flight_turn_ticks
					if phase == 2: actor.facing = turn_toward(actor.facing,actor.position(),target)
					else:
						var offset := 0 if actor.source_next_random >= 160 else 1 if actor.source_next_random >= 80 else -1
						actor.facing = DIRS[posmod(maxi(0,DIRS.find(actor.facing))+offset,8)]
		4:
			flight_speed = maxi(0,flight_speed-definition.flight_acceleration)
			if flight_speed < 32:
				phase = 5
				timer = definition.flight_rest_min + (actor.source_random & definition.flight_rest_random_mask)
		5:
			if timer == 0: phase = 0
	flight_fraction += flight_speed & 224
	if flight_fraction >= 256:
		flight_fraction -= 256
		actor.subposition += actor.facing * 256
		distance += 1
		bound(actor)
