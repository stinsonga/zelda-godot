class_name OverworldEnemy
extends RefCounted
## Family state stays on the actor; shared editable definitions stay immutable.
const DIRS := [Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1), Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]
var manhandla: RefCounted
var manhandla_offset := Vector2i.ZERO
var manhandla_index := 0
var manhandla_animation := 0
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
	elif actor.definition.behavior == "digdogger" and actor.definition.size.x > 16:
		actor.facing = DIRS[actor.source_random & 7]

func visible(actor: RefCounted) -> bool:
	if actor.definition.behavior == "wallmaster": return phase == 1
	if actor.definition.behavior in ["blue_wizzrobe", "red_wizzrobe"]: return not wizzrobe_hidden
	return actor.definition.behavior != "burrower" or phase != 0

func vulnerable(actor: RefCounted) -> bool:
	# Dodongo_CheckCollisionsStandardSize: mask $FF except while stunned.
	if actor.definition.behavior == "dodongo": return phase == 2
	if actor.definition.behavior == "digdogger": return actor.definition.size.x == 16
	if actor.definition.behavior == "wallmaster": return phase == 1
	if actor.definition.behavior in ["blue_wizzrobe", "red_wizzrobe"]: return not wizzrobe_hidden
	if actor.definition.behavior == "burrower": return phase == 3
	if actor.definition.behavior == "flyer": return phase == 5 or not actor.definition.flight_vulnerable_resting_only
	return true

func contact_enabled(actor: RefCounted) -> bool:
	if actor.definition.behavior == "wallmaster": return phase == 1
	if actor.definition.behavior in ["blue_wizzrobe", "red_wizzrobe"]: return not wizzrobe_hidden
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

## Returns true when the monster fires a shot this tick.
func tick(actor: RefCounted, target: Vector2i, probe: Callable, context: Dictionary) -> bool:
	area = context.get("bounds", area)
	if not initialized: initialize(actor)
	if timer > 0: timer -= 1
	if actor.source.turn_timer > 0: actor.source.turn_timer -= 1
	if actor.definition.behavior == "manhandla":
		if manhandla != null: manhandla.tick(actor,context)
		return false
	if actor.shove_remaining > 0:
		actor.source.shove(actor, probe)
		return false
	actor.source.shove_started = false
	match actor.definition.behavior:
		"blue_wizzrobe": return tick_blue_wizzrobe(actor, context, probe)
		"red_wizzrobe": return tick_red_wizzrobe(actor, context, probe)
		"jumper": tick_jump(actor, target)
		"burrower": tick_burrow(actor, target, probe, context)
		"flyer": tick_flight(actor, target)
		"gel": tick_gel(actor, target, probe)
		"rope": tick_rope(actor, target, probe)
		"trap": tick_trap(actor, context)
		"wallmaster": tick_wallmaster(actor, context)
		"pols_voice": tick_pols_voice(actor, probe)
		"aquamentus": tick_aquamentus(actor, context)
		"dodongo": tick_dodongo(actor, target, probe)
		"gohma": return tick_gohma(actor)
		"digdogger": tick_digdogger(actor, target, context)
	return false

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

## Wizzrobes flicker while teleporting or fading: hidden and untouchable on odd frames.
var wizzrobe_hidden := false
var turn_counter := 0
var teleport_left := 0
var cycle := 0

func square_aligned(at: Vector2i) -> Vector2i:
	return Vector2i((at.x + 8) & 0xF0, ((((at.y + 64) + 8) & 0xF0) - 3) - 64)

## Z_04 UpdateBlueWizzrobe: walk every other frame toward Link, turning every 64
## steps between axes; teleport $20 pixels diagonally when the timer ends or a
## block or water stops it; shoot every 32 frames when facing Link along his row
## or column.
func tick_blue_wizzrobe(actor: RefCounted, context: Dictionary, probe: Callable) -> bool:
	var player: Vector2i = context.get("player", Vector2i.ZERO)
	if not initialized: initialized = true
	wizzrobe_hidden = teleport_left & 1 == 1
	if timer == 0:
		if teleport_left > 0:
			teleport_left -= 1
			actor.subposition += actor.facing * 256
			wizzrobe_hidden = teleport_left & 1 == 1
			return false
		actor.subposition = square_aligned(actor.position()) * 256
		timer = actor.source_random | 0x70
		turn_wizzrobe(actor, player)
	elif timer >= 0x10:
		if actor.animation_ticks % 2 == 0:
			turn_counter += 1
			if turn_counter & 0x3F == 0: turn_wizzrobe(actor, player)
			if probe.call(actor.position(), actor.facing) or actor.source.grid_offset != 0:
				actor.source.advance_position(actor, actor.facing, 256)
			else:
				actor.facing = -actor.facing
	elif timer == 1:
		var corners := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
		var corner: Vector2i = corners[actor.source_random & 3]
		var destination: Vector2i = actor.position() + corner * 0x20
		if area.grow(8).has_point(destination) and context.spawn_allowed.call(destination):
			actor.facing = corner
			teleport_left = 0x20
			turn_counter ^= 0x40
			timer = 0
		else:
			actor.subposition = square_aligned(actor.position()) * 256
			timer = actor.source_random | 0x70
	if teleport_left > 0 or context.get("frame", 0) & 0x1F != 0: return false
	var at: Vector2i = actor.position()
	if (at.y + 64) & 0xF0 == (player.y + 64) & 0xF0:
		return actor.facing == (Vector2i.LEFT if at.x >= player.x else Vector2i.RIGHT)
	if at.x & 0xF0 == player.x:
		return actor.facing == (Vector2i.UP if at.y >= player.y else Vector2i.DOWN)
	return false

func turn_wizzrobe(actor: RefCounted, player: Vector2i) -> void:
	var at: Vector2i = actor.position()
	var direction: Vector2i
	if turn_counter & 0x40: direction = Vector2i.UP if at.y >= player.y else Vector2i.DOWN
	else: direction = Vector2i.LEFT if at.x >= player.x else Vector2i.RIGHT
	if direction != actor.facing:
		actor.facing = direction
		actor.subposition = square_aligned(at) * 256
		actor.source.grid_offset = 0

## Z_04 UpdateRedWizzrobe: a 256-frame cycle counted down in its state. At $FF it
## appears beside Link at a RedWizzrobeOffsets spot facing him; it flickers in,
## stands solid from $BF and shoots at $B0, flickers out from $7F (cut to $4F),
## and hides below $40.
const RED_WIZZROBE_X := [0x00, 0x00, 0xE0, 0x20, 0x00, 0x00, 0xC0, 0x40, 0x00, 0x00, 0xD0, 0x30, 0x00, 0x00, 0xB0, 0x50]
const RED_WIZZROBE_Y := [0xE0, 0x20, 0x00, 0x00, 0xC0, 0x40, 0x00, 0x00, 0xD0, 0x30, 0x00, 0x00, 0xB0, 0x50, 0x00, 0x00]

func tick_red_wizzrobe(actor: RefCounted, context: Dictionary, probe: Callable) -> bool:
	var player: Vector2i = context.get("player", Vector2i.ZERO)
	cycle = (cycle - 1) & 0xFF
	var stage := cycle >> 6
	wizzrobe_hidden = stage == 0
	match stage:
		3:
			if cycle == 0xFF:
				var index: int = actor.source_random
				actor.facing = [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT][index & 3]
				var x: int = (player.x + RED_WIZZROBE_X[index & 15]) & 0xF0
				var y: int = (((player.y + 64 + 3 + RED_WIZZROBE_Y[index & 15]) & 0xF0) - 3) & 0xFF
				var at := Vector2i(x, y - 64)
				if y < 0x5D or y >= 0xC4 or not context.spawn_allowed.call(at):
					cycle = 0   # INC ObjState: try again next frame.
				else:
					actor.subposition = at * 256
			wizzrobe_hidden = cycle & 1 == 1
		1:
			if cycle == 0x7F: cycle = 0x4F
			wizzrobe_hidden = cycle & 1 == 1
		2:
			return cycle == 0xB0
	return false

## Z_04 UpdateAquamentus: pace between X $88 and $C7 one pixel every eight
## frames, in random runs of (random AND $F) OR 7 pixels; when the timer ends,
## breathe three fireballs aimed at Link that drift apart by 0, +1, and -1.
func tick_aquamentus(actor: RefCounted, context: Dictionary) -> void:
	if walk_left == 0:
		walk_left = (actor.source_random & 0x0F) | 7
		actor.facing = Vector2i.LEFT if actor.source_random & 1 else Vector2i.RIGHT
	elif int(context.get("frame", 0)) & 7 == 0:
		var at: Vector2i = actor.position()
		if at.x < 0x88:
			at.x = 0x88
			actor.facing = Vector2i.RIGHT
			walk_left = 7
		elif at.x >= 0xC8:
			at.x = 0xC7
			actor.facing = Vector2i.LEFT
			walk_left = 7
		actor.subposition = Vector2i(at.x + actor.facing.x, at.y) * 256
		walk_left -= 1
	if timer == 0:
		timer = actor.source_random | 0x70
		for spread in [0, 1, -1]:
			actor.pending_shots.append({"position": actor.position() + Vector2i(4, 0), "spread": spread})

## Z_04 UpdateDodongo. State 0 walks (turn rate $20) with its walker logic at the
## head when facing right, up, or down. A ticking bomb at its mouth is eaten
## (state 1): bloated $20 then $40 frames; two eaten bombs make it flicker for
## $40 more and die. A detonating bomb beside it stuns it (state 2) for $20 long
## ticks, when the sword can kill it.
const DODONGO_BLOAT := [0x20, 0x40, 0x40]
var bombs_eaten := 0
var bloat_stage := 0

func tick_dodongo(actor: RefCounted, target: Vector2i, probe: Callable) -> void:
	match phase:
		0:
			var shift := 16 if actor.facing in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP] else 0
			actor.subposition.x += shift * 256
			actor.source.move_speed = actor.definition.speed_subpixels
			var direction: Vector2i = actor.facing
			if actor.source.grid_offset == 0: direction = actor.source.choose_movement(actor, probe, actor.source_random)
			if direction != Vector2i.ZERO: actor.source.advance_position(actor, direction, actor.source.move_speed)
			actor.source.select_target(actor, target, actor.source_random, actor.source_next_random)
			actor.subposition.x -= shift * 256
			if actor.position().x < 0x20: actor.facing = Vector2i.RIGHT
		1:
			if timer > 0: return
			bloat_stage += 1
			if bloat_stage == 2 and bombs_eaten < 2:
				phase = 0
				bloat_stage = 0
			elif bloat_stage == 3:
				actor.health = 0
				actor.death_remaining = 19
			else:
				timer = DODONGO_BLOAT[bloat_stage]
		2:
			if actor.stun_ticks == 0 and timer == 0:
				phase = 0

## Z_04 Dodongo_CheckBombHit with DodongoBombPositive/NegativeLimits: the mouth is
## the middle of the head; ticking bombs within -16..16 are eaten, blasts
## within -12..12 stun.
func dodongo_bombs(actor: RefCounted, objects: Array) -> void:
	if phase != 0: return
	var mouth: Vector2i = actor.position() + Vector2i(16 if actor.facing.x != 0 else 8, 8) + actor.facing * 8
	for object in objects:
		if object.kind != "bomb": continue
		var delta: Vector2i = object.center() - mouth
		if object.showing_bomb() and object.stage == 2 and delta.x >= -16 and delta.x < 17 and delta.y >= -16 and delta.y < 17:
			object.active = false
			bombs_eaten += 1
			phase = 1
			bloat_stage = 0
			timer = DODONGO_BLOAT[0]
			return
		if object.detonating() and absi(delta.x) < 12 and absi(delta.y) < 12:
			phase = 2
			timer = 0x20 * 10

func dodongo_sprite(actor: RefCounted) -> StringName:
	var direction := "right" if actor.facing.x > 0 else "left" if actor.facing.x < 0 else "down" if actor.facing.y > 0 else "up"
	if phase == 1 and bloat_stage < 2: return StringName("dodongo_bloated_" + direction)
	var pose := 1 if (actor.animation_ticks / (0x20 if phase == 2 else 8)) % 2 else 0
	return StringName("dodongo_%s_%d" % [direction, pose])

## Z_04 UpdateGohma: half a pixel a frame, 32 pixels out and back, then a new
## direction (Random >= $B0 right, >= $60 left, else down). The eye opens on a
## $C0|random countdown (stepped every other frame) for $80 frames: half open at
## the ends, fully open between $70 and $10. A fireball ($56) every $41 frames.
var eye_state := 0
var eye_timer := 0
var eye_wait := 0
var eye_blink := 0
var sprints := 0
var going_straight := false
var accumulator := 0
var shot_timer := 1

func tick_gohma(actor: RefCounted) -> bool:
	if not going_straight:
		var roll: int = actor.source_random
		actor.facing = Vector2i.RIGHT if roll >= 0xB0 else Vector2i.LEFT if roll >= 0x60 else Vector2i.DOWN
		going_straight = true
	else:
		accumulator += 0x80
		if accumulator >= 0x100:
			accumulator -= 0x100
			actor.subposition += actor.facing * 256
			distance += 1
			if distance == 0x20:
				distance = 0
				actor.facing = -actor.facing
				if sprints & 1: going_straight = false
				sprints += 1
	if eye_wait == 0:
		eye_timer = 0x80
		eye_wait = 0xC0 | actor.source_random
	if int(actor.animation_ticks) & 1: eye_wait -= 1
	if eye_timer > 0:
		eye_timer -= 1
		eye_state = 3 if eye_timer < 0x70 and eye_timer >= 0x10 else 2
	else:
		eye_blink += 1
		if eye_blink == 8:
			eye_blink = 0
			eye_state = (eye_state & 1) ^ 1
	shot_timer -= 1
	if shot_timer == 0:
		shot_timer = 0x41
		actor.pending_shots.append({"position": actor.position() + Vector2i(20, 0), "spread": 0})
	return false

## Z_04 Gohma_HandleWeaponCollision: only an arrow flying up into the open eye
## (the middle of the body) hurts Gohma.
func gohma_eye_hit(actor: RefCounted, arrow_center: Vector2i, direction: Vector2i) -> bool:
	return eye_state == 3 and direction == Vector2i.UP and absi(arrow_center.x - (actor.position().x + 24)) < 8

## Z_04 UpdateDigdogger: drift in eight directions with speed swinging between
## $40 and $80 (little ones one pixel faster), turning every 16 frames at random
## or toward Link. After the recorder, the big one flickers small for $40
## frames and splits into its children.
var speed := 0x3F
var target_speed := 0x80
var slowing := false
var shrink := -1

func tick_digdogger(actor: RefCounted, target: Vector2i, context: Dictionary) -> void:
	var child: bool = actor.definition.size.x == 16
	if not child and shrink < 0 and context.get("recorder_used", false):
		shrink = 0x40
	if shrink > 0:
		shrink -= 1
		if shrink == 0: actor.split_pending = true
		return
	speed += -1 if slowing else 1
	if speed == target_speed:
		slowing = not slowing
		target_speed = 0x40 if slowing else 0x80
	if timer == 0:
		timer = 0x10
		if actor.source_random >= 0x80: actor.facing = turn_toward(actor.facing, actor.position() + actor.definition.size / 2 - Vector2i(8, 8), target)
		else: actor.facing = DIRS[posmod(maxi(0, DIRS.find(actor.facing)) + (1 if actor.source_next_random & 1 else -1), 8)]
	flight_fraction += speed & 0xE0
	var step := (1 if child else 0) + (1 if flight_fraction >= 0x100 else 0)
	if flight_fraction >= 0x100: flight_fraction -= 0x100
	actor.subposition += actor.facing * step * 256
	var at: Vector2i = actor.position()
	var far: Vector2i = at + actor.definition.size - Vector2i(16, 16)
	if (at.x < area.position.x and actor.facing.x < 0) or (far.x >= area.end.x and actor.facing.x > 0) or (at.y < area.position.y and actor.facing.y < 0) or (far.y >= area.end.y and actor.facing.y > 0):
		actor.facing = -actor.facing
