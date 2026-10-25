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
## Object bounds for the current room (Z_05 ObjectRoomBoundsOW/UW), play-area pixels.
var area := Rect2i(17, 14, 207, 127)
var rope_speed := 128
var split_ticks := 0
## Z_04 VireJumpOffsets, indexed by distance into the square.
const VIRE_HOPS := [0, -3, -2, -1, -1, 0, -1, 0, 0, 1, 0, 1, 1, 2, 3, 0]
var origin := Vector2i.ZERO
var path_step := 0
var tiles_crossed := 0
var carried_out := false
var jump_speed := 0
var jump_target := 0
var walk_left := 0

func initialize(actor: RefCounted) -> void:
	initialized = true
	if actor.definition.behavior == "jumper":
		var index: int = actor.source_next_random & 3
		jump_direction = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i(1,1), Vector2i(-1,-1)][index]
		timer = [4,8,20,40][index]
	elif actor.definition.behavior == "flyer":
		actor.facing = Vector2i.UP
		flight_speed = actor.definition.flight_initial_speed
		# Z_04 InitBlueKeese: one of eight random directions.
		if actor.definition.flight_random_start: actor.facing = DIRS[actor.source_random & 7]
	elif actor.definition.behavior == "rope":
		rope_speed = 128
	elif actor.definition.behavior == "trap":
		origin = actor.position()

func visible(actor: RefCounted) -> bool:
	if actor.definition.behavior == "wallmaster": return phase == 1
	return actor.definition.behavior != "burrower" or phase != 0

func vulnerable(actor: RefCounted) -> bool:
	if actor.definition.behavior == "wallmaster": return phase == 1
	if actor.definition.behavior == "burrower": return phase == 3
	if actor.definition.behavior == "flyer": return phase == 5 or not actor.definition.flight_vulnerable_resting_only
	return true

func contact_enabled(actor: RefCounted) -> bool:
	if actor.definition.behavior == "wallmaster": return phase == 1
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
	if (at.x < area.position.x and actor.facing.x < 0) or (at.x >= area.end.x and actor.facing.x > 0) or (at.y < area.position.y and actor.facing.y < 0) or (at.y >= area.end.y and actor.facing.y > 0):
		actor.facing = -actor.facing
		return false
	return true

func tick(actor: RefCounted, target: Vector2i, probe: Callable, context: Dictionary) -> void:
	area = context.get("bounds", area)
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
		"gel": tick_gel(actor, target, probe)
		"rope": tick_rope(actor, target, probe)
		"trap": tick_trap(actor, context)
		"wallmaster": tick_wallmaster(actor, context)
		"pols_voice": tick_pols_voice(actor, probe)

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
			phase = 2 if actor.source_random >= definition.flight_chase_threshold else 3 if actor.source_random >= 32 else 4
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

## Z_04 UpdateNormalZolOrGel: walk only while the timer is below 5, and wait
## at each square for one of four delays. Split children first dart away.
func tick_gel(actor: RefCounted, target: Vector2i, probe: Callable) -> void:
	var source: RefCounted = actor.source
	if split_ticks > 0:
		# Gel_MoveSplitting: quarter speed $FF until blocked or five frames pass.
		split_ticks -= 1
		var blocked: bool = source.grid_offset == 0 and not probe.call(actor.position(), actor.facing)
		if not blocked: source.advance_position(actor, actor.facing, 1020)
		if blocked or split_ticks == 0:
			split_ticks = 0
			var at: Vector2i = actor.position()
			actor.subposition = Vector2i((at.x + 8) & 0xF0, ((((at.y + 64) + 8) & 0xF0) | 0x0D) - 64) * 256
			source.grid_offset = 0
		return
	if timer >= 5: return
	var direction: Vector2i = actor.facing
	if source.grid_offset == 0: direction = source.choose_movement(actor, probe, actor.source_random)
	if direction != Vector2i.ZERO: source.advance_position(actor, direction, actor.definition.speed_subpixels)
	source.select_target(actor, target, actor.source_random, actor.source_next_random)
	if source.grid_offset == 0 and timer == 0:
		timer = actor.definition.hop_delays[actor.source_random & 3]

## Z_04 UpdateRope: wander slowly, turning at random; rush when lined up within 8 pixels.
func tick_rope(actor: RefCounted, target: Vector2i, probe: Callable) -> void:
	var source: RefCounted = actor.source
	var original: Vector2i = actor.facing
	if source.grid_offset == 0 and not probe.call(actor.position(), actor.facing):
		face_unblocked(actor, probe)
	else:
		source.advance_position(actor, actor.facing, rope_speed)
	if rope_speed != 384 and timer == 0:
		timer = actor.source_random & 0x3F
		face_unblocked(actor, probe)
	if actor.facing != original: rope_speed = 128
	if rope_speed == 128 and source.grid_offset == 0:
		var delta: Vector2i = target - actor.position()
		if absi(delta.x) < 8:
			actor.facing = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
			rope_speed = 384
		elif absi(delta.y) < 8:
			actor.facing = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
			rope_speed = 384

## Z_07 _FaceUnblockedDir: starting from a random direction, the first open one.
func face_unblocked(actor: RefCounted, probe: Callable) -> void:
	var cardinal := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	var start: int = actor.source_next_random & 3
	for i in range(4):
		var direction: Vector2i = cardinal[(start + i) % 4]
		if probe.call(actor.position(), direction):
			actor.facing = direction
			return

## Z_01 UpdateTrap_Full: sense Link within $0E on one axis, slide toward the room
## middle at 1.75 pixels a frame, stop within 5 of it, and creep back at 0.5.
## Traps only slide toward the middle (TrapAllowedDirs, derived from position).
func tick_trap(actor: RefCounted, context: Dictionary) -> void:
	var at: Vector2i = actor.position()
	var player: Vector2i = context.get("player", Vector2i.ZERO)
	match phase:
		0:
			var direction := Vector2i.ZERO
			if absi(player.y - at.y) < 0x0E and player.x != at.x: direction = Vector2i(signi(player.x - at.x), 0)
			elif absi(player.x - at.x) < 0x0E and player.y != at.y: direction = Vector2i(0, signi(player.y - at.y))
			var middle := Vector2i(120, 77)
			if direction != Vector2i.ZERO and (direction.x == signi(middle.x - origin.x) and direction.x != 0 or direction.y == signi(middle.y - origin.y) and direction.y != 0):
				actor.facing = direction
				phase = 1
		1:
			actor.subposition += actor.facing * 448
			var middle_coordinate: int = 120 if actor.facing.x != 0 else 80
			var coordinate: int = actor.position().x if actor.facing.x != 0 else actor.position().y
			if absi(coordinate - middle_coordinate) < 5:
				actor.facing = -actor.facing
				phase = 2
		2:
			actor.subposition += actor.facing * 128
			var home: int = origin.x if actor.facing.x != 0 else origin.y
			var now: int = actor.position().x if actor.facing.x != 0 else actor.position().y
			if (now - home) * (actor.facing.x + actor.facing.y) >= 0:
				actor.subposition = origin * 256
				phase = 0

## Z_04 UpdateWallmaster. Waits until Link stands against a wall (and no other
## Wallmaster has emerged for $60 ticks), appears ahead of him from the wall,
## then follows its seven-square path (WallmasterDirsAndAttrs) at q-speed $18.
const WALLMASTER_PATHS := [
	0x01, 0x01, 0x08, 0x08, 0x08, 0x02, 0x02, 0x02, 0xC1, 0xC1, 0xC4, 0xC4, 0xC4, 0xC2, 0xC2, 0xC2,
	0x42, 0x42, 0x48, 0x48, 0x48, 0x41, 0x41, 0x41, 0x82, 0x82, 0x84, 0x84, 0x84, 0x81, 0x81, 0x81,
	0xC4, 0xC4, 0xC2, 0xC2, 0xC2, 0xC8, 0xC8, 0xC8, 0x84, 0x84, 0x81, 0x81, 0x81, 0x88, 0x88, 0x88,
	0x48, 0x48, 0x42, 0x42, 0x42, 0x44, 0x44, 0x44, 0x08, 0x08, 0x01, 0x01, 0x01, 0x04, 0x04, 0x04]

static func nes_direction(bits: int) -> Vector2i:
	match bits & 0x0F:
		1: return Vector2i.RIGHT
		2: return Vector2i.LEFT
		4: return Vector2i.DOWN
	return Vector2i.UP

func tick_wallmaster(actor: RefCounted, context: Dictionary) -> void:
	if phase == 0:
		if int(context.get("wallmaster_cooldown", 0)) > 0: return
		var player: Vector2i = context.get("player", Vector2i.ZERO)
		var facing: Vector2i = context.get("player_facing", Vector2i.UP)
		var moving: bool = context.get("player_moving", false)
		var distance := 0x32 if moving else 0x24
		var start := Vector2i.ZERO
		if (player.x < 0x29 or player.x >= 0xC8) and (player.y < 0x6D - 64 or player.y >= 0xB5 - 64): return
		if player.x == 0x20 or player.x == 0xD0:
			path_step = 0
			if facing == Vector2i.UP:
				path_step += 8
				distance = -distance
			var far := player.x != 0x20
			if far: path_step += 16
			start = Vector2i(0xF0 if far else 0x00, player.y + distance)
		elif player.y == 0x5D - 64 or player.y == 0xBD - 64:
			path_step = 32
			if facing == Vector2i.LEFT:
				path_step += 8
				distance = -distance
			var far := player.y != 0x5D - 64
			if far: path_step += 16
			start = Vector2i(player.x + distance, (0xDD if far else 0x3D) - 64)
		else:
			return
		context.wallmaster_cooldown = 0x60
		actor.subposition = start * 256
		actor.facing = nes_direction(WALLMASTER_PATHS[path_step])
		distance_moved_reset(actor)
		phase = 1
		return
	if actor.shove_remaining > 0:
		actor.source.shove(actor, func(_at: Vector2i, _d: Vector2i) -> bool: return true)
		return
	actor.source.advance_position(actor, actor.facing, 96)
	if absi(actor.source.grid_offset) == 0 and distance != 0:
		tiles_crossed += 1
		path_step += 1
		distance = 0
		if tiles_crossed >= 7:
			carried_out = actor.capture_ticks > 0
			actor.capture_ticks = 0
			phase = 0
			return
		actor.facing = nes_direction(WALLMASTER_PATHS[path_step])
	elif actor.source.grid_offset != 0:
		distance = 1

func distance_moved_reset(actor: RefCounted) -> void:
	actor.source.grid_offset = 0
	tiles_crossed = 0
	distance = 0

## Z_04 UpdatePolsVoice, simplified: every other frame walk a random cardinal
## distance, bounce off walls, and hop with gravity $38/256 toward a target Y.
## Provisional: the original's eight-way jump table is not yet translated.
func tick_pols_voice(actor: RefCounted, probe: Callable) -> void:
	actor.facing = actor.facing if actor.facing != Vector2i.ZERO else Vector2i.RIGHT
	if actor.animation_ticks % 2: return
	if phase == 0:
		if walk_left <= 0:
			phase = 1
			jump_speed = -3 * 256 if actor.facing.y <= 0 else -256
			jump_target = actor.position().y + (32 if actor.facing.y > 0 else -32 if actor.facing.y < 0 else 0)
			jump_target = clampi(jump_target, area.position.y, area.end.y)
			return
		walk_left -= 1
		if probe.call(actor.position(), actor.facing) or actor.source.grid_offset != 0:
			actor.source.advance_position(actor, actor.facing, 256)
		else:
			actor.facing = -actor.facing
	else:
		jump_speed += 0x38
		actor.subposition.y += jump_speed
		if actor.facing.x != 0: actor.subposition.x += actor.facing.x * 256
		if jump_speed >= 0 and actor.position().y >= jump_target:
			phase = 0
			actor.facing = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP][actor.source_random & 3]
			walk_left = 0x30 + (actor.source_random & 0x40)
			var at: Vector2i = actor.position()
			actor.subposition = Vector2i((at.x + 8) & 0xF0, (((at.y + 64 + 8) & 0xF0) - 3) - 64) * 256
			actor.source.grid_offset = 0
		bound(actor)
