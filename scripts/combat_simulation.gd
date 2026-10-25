class_name CombatSimulation
extends RefCounted

const Beam = preload("res://scripts/sword_beam.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Reward = preload("res://scripts/dropped_reward.gd")
const Rock = preload("res://scripts/rock_projectile.gd")
var source_random = preload("res://scripts/nes_random.gd").new()
var spawn_lists: Array[PackedByteArray] = []
var projectile_limit := 4
var chase_target := Vector2i.ZERO
var chase_other := false
var chase_timer := 0
var frame_clock := 0
var edge_timer := 0
var edge_cursor := 0x40
var encounter_room: Resource
var encounter_total := 0
var encounter_kills := 0
var base_kills := 0
var beam: RefCounted
var rewards: Array[RefCounted] = []
var enemies: Array[RefCounted] = []
var rocks: Array[RefCounted] = []
var player_invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO

func enter_room(room: Resource, state: RefCounted, restoring: bool = false, entry_position: Vector2i = Vector2i.ZERO, entry_direction: Vector2i = Vector2i.UP) -> void:
	beam = null
	enemies.clear()
	rocks.clear()
	rewards.clear()
	shove_remaining = 0
	encounter_room = room
	encounter_kills = 0
	base_kills = 0
	var count: int = room.enemies.size()
	if room.enemy_persistence == "overworld":
		count = state.prepare_overworld_room(room, restoring)
		base_kills = int(state.room_records[String(room.id)].kills)
	for i in range(count):
		var spawn: Resource = room.enemies[i]
		if room.enemy_persistence == "permanent" and state.defeated.has(String(room.id) + "/" + String(spawn.id)): continue
		var actor = Actor.new()
		actor.setup(spawn)
		actor.slot = i + 1
		enemies.append(actor)
	encounter_total = enemies.size()
	if room.source_edge_spawns:
		for actor in enemies:
			if actor.definition.behavior == "nes_octorok":
				actor.waiting_spawn = true
				actor.spawn_remaining = 0
	else:
		assign_source_spawns(room, state, entry_position, entry_direction)

func can_enemy_occupy(world: Node, at: Vector2i) -> bool:
	if at.x < 16 or at.x > 224 or at.y < 13 or at.y > 141: return false
	for point in [at + Vector2i(2, 8), at + Vector2i(13, 8), at + Vector2i(2, 15), at + Vector2i(13, 15)]:
		if world.is_blocked(point): return false
	return true

func hurt_player(world: Node, damage: int, source: Vector2i) -> bool:
	if player_invulnerability > 0 or world.state.health <= 0: return false
	world.state.health = maxi(0, world.state.health - damage)
	if world.state.health == 0: world.audio.silence()
	world.audio.play(&"player_hurt")
	player_invulnerability = 48
	var delta: Vector2i = world.player.pixel_position() - source
	var relative: Vector2i = world.player.subposition - world.player.grid_origin * 256
	var on_grid: bool = posmod(relative.x, 2048) == 0 and posmod(relative.y, 2048) == 0
	var horizontal: bool = absi(delta.x) >= absi(delta.y) if on_grid else world.player.facing.x != 0
	shove_direction = (Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT) if horizontal else (Vector2i.DOWN if delta.y >= 0 else Vector2i.UP)
	shove_remaining = 32
	world.sword.phase = -1
	return true

func move_shoved_player(world: Node) -> void:
	var before: Vector2i = world.player.pixel_position()
	var facing: Vector2i = world.player.facing
	world.player.facing = shove_direction
	world.player.step(shove_direction, world.can_occupy, world.can_enter_segment, mini(4, shove_remaining) * 256)
	world.player.facing = facing
	var moved: Vector2i = world.player.pixel_position() - before
	if moved == Vector2i.ZERO: shove_remaining = 0
	else: shove_remaining = maxi(0, shove_remaining - absi(moved.x) - absi(moved.y))

func tick(world: Node) -> void:
	if world.state.health <= 0: return
	player_invulnerability = maxi(0, player_invulnerability - 1)
	var launched := false
	if world.sword.phase == 2 and not world.sword.beam_attempted:
		world.sword.beam_attempted = true
		launched = launch_beam(world)
	if not launched: tick_beam(world)
	update_chase_target(world.player.pixel_position())
	update_edge_spawns(world)
	var updates: Array = enemies.duplicate()
	updates.reverse()
	for actor in updates:
		actor.source_random = source_random.at(actor.slot)
		actor.source_next_random = source_random.at(actor.slot + 1)
		if actor.alive() and world.sword.hits(world.player.pixel_position(), actor.position()):
			if actor.receive_hit(world.sword.weapon.damage, world.sword.direction):
				world.audio.play(&"enemy_hit")
				if actor.health == 0:
					world.audio.play(&"enemy_die")
					record_permanent_kill(world, actor)
		var original: bool = actor.definition.behavior == "nes_octorok"
		var target: Vector2i = chase_target if original else world.player.pixel_position()
		if actor.tick(target, func(at: Vector2i) -> bool: return can_enemy_occupy(world, at),
			func(at: Vector2i, direction: Vector2i) -> bool: return source_can_enter(world, at, direction), rocks.size() < projectile_limit):
			if rocks.size() < projectile_limit:
				var rock = Rock.new()
				rock.source_rules = original
				rock.subposition = actor.subposition if original else (actor.position() + actor.facing * 12) * 256
				rock.direction = actor.facing
				rock.speed_subpixels = actor.definition.projectile_speed_subpixels
				rocks.append(rock)
		if actor.health == 0 and actor.death_remaining == 0 and not actor.drop_resolved:
			actor.drop_resolved = true
			encounter_kills += 1
			world.state.kill_cycle = (world.state.kill_cycle + 1) % 10
			var table: Resource = world.loot_tables.get(actor.definition.id, actor.definition.loot_table)
			if table != null:
				var item: Resource = table.select(world.state.kill_cycle, actor.source_random if original else actor.rng.randi_range(0, 255))
				if item != null:
					var reward = Reward.new()
					reward.definition = item
					reward.position = actor.position()
					rewards.append(reward)
		if actor.alive() and actor.invulnerability == 0 and (source_contact(actor.position(), world.player.pixel_position()) if original else actor.hurtbox().intersects(player_box(world))):
			hurt_player(world, actor.definition.contact_damage, actor.position())
	for rock in rocks:
		if rock.source_rules:
			tick_source_rock(world, rock)
			continue
		var remaining: int = rock.speed_subpixels
		while remaining > 0 and rock.alive:
			var amount := mini(256, remaining)
			rock.subposition += rock.direction * amount
			remaining -= amount
			var at: Vector2i = rock.position()
			if at.x < -16 or at.x > 256 or at.y < -16 or at.y > 176:
				rock.alive = false
			elif world.room.is_pixel_solid(at + Vector2i(8, 8)):
				rock.alive = false
			elif rock.hurtbox().intersects(player_box(world)):
				# The basic shield blocks rocks arriving from the facing direction,
				# while Link is free to defend (not using the sword).
				if world.player.facing == -rock.direction and not world.sword.active():
					world.audio.play(&"parry")
					rock.alive = false
				elif hurt_player(world, 1, at):
					rock.alive = false
	rocks = rocks.filter(func(rock: RefCounted) -> bool: return rock.alive)
	for reward in rewards:
		reward.age += 1
		if world.state.health > 0 and reward.available():
			var touched: bool = reward.touches(world.player.pixel_position())
			if world.sword.visible():
				touched = touched or reward.touches(world.player.pixel_position() + world.sword.offset())
			if touched:
				reward.take(world.state)
				world.audio.play(&"heart" if reward.definition.effect == "health" else &"rupee")
	rewards = rewards.filter(func(reward: RefCounted) -> bool: return not reward.collected and reward.age < Reward.LIFETIME)

func player_box(world: Node) -> Rect2i:
	return Rect2i(world.player.pixel_position() + Vector2i(2, 2), Vector2i(12, 12))

func launch_beam(world: Node) -> bool:
	if beam != null or not world.sword.weapon.fires_beam:
		return false
	# MakeSwordShot requires the last partial heart to be at least half full.
	if world.state.health < world.state.max_health - 1:
		return false
	var at: Vector2i = world.player.pixel_position() + world.sword.direction * 16
	if world.sword.direction.x != 0 and (at.x < 20 or at.x >= 236):
		return false
	beam = Beam.new()
	beam.position = at
	beam.direction = world.sword.direction
	beam.damage = world.sword.weapon.damage
	return true

func tick_beam(world: Node) -> void:
	if beam == null: return
	if beam.burst_remaining > 0:
		beam.burst_remaining -= 1
		if beam.burst_remaining == 0:
			beam.finished = true
			beam = null
		return
	# MoveShot checks room bounds. Beam flight does not use rock terrain checks.
	for pixel in range(Beam.SPEED):
		var next: Vector2i = beam.position + beam.direction
		if not world.room.movement_bounds.has_point(next):
			beam.impact()
			return
		beam.position = next
		for actor in enemies:
			if actor.alive() and beam.hits(actor.position()):
				if actor.receive_hit(beam.damage, beam.direction):
					world.audio.play(&"enemy_hit")
					if actor.health == 0:
						world.audio.play(&"enemy_die")
						record_permanent_kill(world, actor)
					beam.impact()
					return

func record_permanent_kill(world: Node, actor: RefCounted) -> void:
	if world.room.enemy_persistence == "permanent":
		world.state.defeated[String(world.room.id) + "/" + String(actor.id)] = true

func persisted_records(state: RefCounted) -> Dictionary:
	var records: Dictionary = state.room_records.duplicate(true)
	if encounter_room != null and encounter_room.enemy_persistence == "overworld" and not encounter_room.enemies.is_empty():
		var cleared := encounter_total == 0 or encounter_kills >= encounter_total
		records[String(encounter_room.id)] = {
			"kills": encounter_room.enemies.size() if cleared else base_kills + encounter_kills,
			"cleared": cleared}
	return records

func commit_room(state: RefCounted) -> void:
	state.room_records.assign(persisted_records(state))

func advance_frame() -> void:
	source_random.advance()
	frame_clock += 1
	if frame_clock % 10 == 0:
		chase_timer = maxi(0, chase_timer - 1)
		edge_timer = maxi(0, edge_timer - 1)

func update_chase_target(player: Vector2i) -> void:
	if not chase_other: chase_target = player
	if chase_timer != 0: return
	chase_timer = source_random.at(1) & 7
	chase_other = not chase_other
	if chase_other and chase_target.x == player.x:
		# XOR $FF operates on the NES screen Y, including its 64-pixel HUD.
		chase_target = Vector2i(255 - chase_target.x, 127 - chase_target.y)

func source_contact(a: Vector2i, b: Vector2i) -> bool:
	var delta := (a - b).abs()
	return delta.x < 9 and delta.y < 9

func source_can_enter(world: Node, at: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i.LEFT and at.x < 17: return false
	if direction == Vector2i.RIGHT and at.x >= 224: return false
	if direction == Vector2i.UP and at.y < 14: return false
	if direction == Vector2i.DOWN and at.y >= 141: return false
	var probe := at + Vector2i(0, 11)
	if direction.x != 0:
		probe.x += 16 if direction.x > 0 else -16
		return not world.is_blocked(probe)
	probe.y += 16 if direction.y > 0 else -16
	return not world.is_blocked(probe) and not world.is_blocked(probe + Vector2i(8, 0))

func assign_source_spawns(room: Resource, state: RefCounted, player: Vector2i, direction: Vector2i) -> void:
	var original: Array = enemies.filter(func(actor: RefCounted) -> bool: return actor.definition.behavior == "nes_octorok")
	if original.is_empty() or spawn_lists.size() != 4: return
	var list_index := 0
	if direction == Vector2i.LEFT: list_index = 1
	elif direction == Vector2i.DOWN: list_index = 2
	elif direction == Vector2i.UP: list_index = 3
	var points: PackedByteArray = spawn_lists[list_index]
	var cursor: int = state.spawn_cycle
	var positions: Array[Vector2i] = []
	# The original assigns nine slots even if fewer enemies are active.
	for slot in range(9):
		var found := false
		for attempt in range(9):
			var packed := int(points[cursor])
			cursor = (cursor + 1) % 9
			var at := Vector2i((packed & 15) * 16, (packed & 240) + 13 - 64)
			var delta := (player - at).abs()
			if not room.is_pixel_solid(at + Vector2i(0, 11)) and (delta.x >= 34 or delta.y >= 34):
				positions.append(at)
				found = true
				break
		if not found:
			for actor in original: actor.waiting_spawn = true
			return
	state.spawn_cycle = cursor
	for i in range(original.size()):
		var actor = original[i]
		actor.subposition = positions[i % 9] * 256
		actor.facing = Vector2i.ZERO
		actor.source.initialize_facing(actor, player)
		actor.waiting_spawn = false

func next_edge_cell(cell: int) -> int:
	if (cell & 15) == 0: cell += 16
	elif (cell & 15) == 15: cell -= 16
	if (cell & 240) == 0xE0: cell += 1
	elif (cell & 240) == 0x40: cell -= 1
	return cell & 255

func update_edge_spawns(world: Node) -> void:
	var waiting: Array = enemies.filter(func(actor: RefCounted) -> bool: return actor.waiting_spawn)
	if waiting.is_empty(): return
	if not world.room.source_edge_spawns:
		assign_source_spawns(world.room, world.state, world.player.pixel_position(), world.player.facing)
		return
	if edge_timer != 0: return
	# Source initialization visits the highest object slot first.
	waiting.reverse()
	var actor = waiting[0]
	var found := false
	for cell in range(50):
		edge_cursor = next_edge_cell(edge_cursor)
		if edge_cursor in world.room.source_edge_cells:
			found = true
			break
	edge_timer = (source_random.at(actor.slot + 1) & 3) + 2
	if not found: return
	var at := Vector2i((edge_cursor & 15) * 16, (edge_cursor & 240) - 3 - 64)
	var delta: Vector2i = (world.player.pixel_position() - at).abs()
	if delta.x < 34 and delta.y < 34: return
	actor.subposition = at * 256
	actor.facing = Vector2i.ZERO
	actor.source.initialize_facing(actor, world.player.pixel_position())
	actor.waiting_spawn = false
	actor.spawn_remaining = 0

func tick_source_rock(world: Node, rock: RefCounted) -> void:
	rock.age += 1
	if rock.age == 1: return
	if rock.bounce_remaining > 0:
		var displacement := Vector2i(1, -2)
		if rock.bounce_direction == Vector2i.DOWN: displacement = Vector2i(-1, 2)
		elif rock.bounce_direction == Vector2i.LEFT: displacement = Vector2i(-2, -1)
		elif rock.bounce_direction == Vector2i.RIGHT: displacement = Vector2i(2, -1)
		rock.subposition += displacement * 256
		rock.bounce_remaining -= 1
		if rock.bounce_remaining == 0: rock.alive = false
		return
	if not source_can_enter(world, rock.position(), rock.direction):
		rock.alive = false
		return
	rock.subposition += rock.direction * rock.speed_subpixels
	var center: Vector2i = rock.position() + Vector2i(4, 8)
	var player_center: Vector2i = world.player.pixel_position() + Vector2i(8, 8)
	if player_invulnerability == 0 and source_contact(center, player_center):
		if world.player.facing == -rock.direction and not world.sword.active():
			world.audio.play(&"parry")
			rock.bounce_direction = world.player.facing
			rock.bounce_remaining = 16
		else:
			hurt_player(world, 1, rock.position())
			rock.alive = false
