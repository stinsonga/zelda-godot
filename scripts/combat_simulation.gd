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
var ambush_timer := 50
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
## Z_05 ObjectRoomBoundsOW and ObjectRoomBoundsUW in play-area pixels.
const BOUNDS_OVERWORLD := Rect2i(17, 14, 207, 127)
const BOUNDS_UNDERWORLD := Rect2i(33, 30, 175, 95)
var bounds := BOUNDS_OVERWORLD
var wallmaster_cooldown := 0

func enter_room(room: Resource, state: RefCounted, restoring: bool = false, entry_position: Vector2i = Vector2i.ZERO, entry_direction: Vector2i = Vector2i.UP) -> void:
	beam = null
	enemies.clear()
	rocks.clear()
	rewards.clear()
	shove_remaining = 0
	ambush_timer = 50
	encounter_room = room
	bounds = BOUNDS_UNDERWORLD if room.dungeon_level > 0 else BOUNDS_OVERWORLD
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
			if actor.definition.behavior != "native":
				actor.waiting_spawn = true
				actor.spawn_remaining = 0
	elif room.source_spawn_lists:
		assign_source_spawns(room, state, entry_position, entry_direction)
	setup_gleeoks()
	setup_multipart_bosses()
	encounter_total = enemies.filter(func(a: RefCounted) -> bool: return a.definition.counts_for_persistence).size()

func setup_gleeoks() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior != "gleeok": continue
		var group = preload("res://scripts/gleeok.gd").new()
		group.setup(actor)
		actor.family.gleeok = group
		for i in range(actor.definition.gleeok_neck_count):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id)+"_neck_"+str(i))
			spawn.enemy = actor.definition.gleeok_head
			spawn.spawn_ticks = 0
			var head = Actor.new()
			head.setup(spawn)
			head.spawn_remaining = 0
			head.slot = i+7
			head.family.gleeok = group
			group.add_head(head,i,actor.hit_position(),actor.definition.gleeok_head_delay)
			enemies.append(head)
		enemies.erase(actor)
		enemies.append(actor)

func setup_multipart_bosses() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior != "manhandla" or actor.definition.boss_hand == null: continue
		var group = preload("res://scripts/manhandla.gd").new()
		actor.source_random = source_random.at(actor.slot)
		group.setup(actor)
		actor.family.manhandla = group
		for i in range(actor.definition.boss_hand_offsets.size()):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id)+"_hand_"+str(i))
			spawn.enemy = actor.definition.boss_hand
			spawn.position = actor.position()+Vector2i(actor.definition.boss_hand_offsets[i])
			spawn.spawn_ticks = 0
			var hand = Actor.new()
			hand.setup(spawn)
			hand.spawn_remaining = 0
			hand.slot = i+1
			hand.family.manhandla = group
			hand.family.manhandla_offset = Vector2i(actor.definition.boss_hand_offsets[i])
			hand.family.manhandla_index = i
			group.hands.append(weakref(hand))
			enemies.append(hand)
		actor.slot = 5
		# Reverse update order visits the base before its hands, as on the NES.
		enemies.erase(actor)
		enemies.append(actor)

func can_enemy_occupy(world: Node, at: Vector2i) -> bool:
	if at.x < bounds.position.x - 1 or at.x > bounds.end.x or at.y < bounds.position.y - 1 or at.y > bounds.end.y: return false
	for point in [at + Vector2i(2, 8), at + Vector2i(13, 8), at + Vector2i(2, 15), at + Vector2i(13, 15)]:
		if world.is_blocked(point): return false
	return true

func hurt_player(world: Node, damage: int, source: Vector2i) -> bool:
	if player_invulnerability > 0 or world.state.health <= 0: return false
	world.state.take_damage(damage)
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
	ambush_timer = maxi(0,ambush_timer-1)
	wallmaster_cooldown = maxi(0, wallmaster_cooldown - 1)
	var context := {"player":world.player.pixel_position(), "player_facing":world.player.facing, "bounds":bounds, "chase_target":chase_target, "random":source_random.at(0), "head_random":source_random.at(5),
		"wallmaster_cooldown":wallmaster_cooldown, "player_moving":world.held.size() > 0, "frame":frame_clock,
		"recorder_used":world.recorder_used_here and world.recorder_ticks == 0,
		"ambush_timer":ambush_timer, "active_ambush":enemies.filter(func(a: RefCounted) -> bool: return a.alive() and a.definition.behavior == "burrower" and a.definition.burrow_style == "ambush" and a.family.phase != 0).size(),
		"spawn_allowed":func(at: Vector2i) -> bool: return not world.is_blocked(at+Vector2i(0,11))}
	var updates: Array = enemies.duplicate()
	updates.reverse()
	for actor in updates:
		actor.source_random = source_random.at(actor.slot)
		actor.source_next_random = source_random.at(actor.slot + 1)
		if actor.targetable() and world.sword.hits(world.player.pixel_position(), actor.hit_position()):
			if actor.receive_hit(world.sword.weapon.damage, world.sword.direction, "sword"):
				world.audio.play(&"enemy_hit")
				if actor.health == 0:
					world.audio.play(&"enemy_die")
					record_permanent_kill(world, actor)
			elif actor.parried_hit:
				world.audio.play(&"parry")
		var was_alive: bool = actor.health > 0
		var original: bool = actor.definition.behavior != "native"
		var target: Vector2i = chase_target if original else world.player.pixel_position()
		if actor.tick(target, func(at: Vector2i) -> bool: return can_enemy_occupy(world, at),
			func(at: Vector2i, direction: Vector2i) -> bool: return source_can_enter(world, at, direction), rocks.size() < projectile_limit, context):
			if rocks.size() < projectile_limit:
				var rock = Rock.new()
				rock.source_rules = original
				rock.kind = actor.definition.projectile_kind
				rock.damage = actor.definition.projectile_damage
				rock.blockable = actor.definition.projectile_blockable
				if rock.kind == "boomerang":
					rock.owner = actor
					rock.source_rules = false
					actor.shot_out = true
				rock.subposition = actor.subposition if original else (actor.position() + actor.facing * 12) * 256
				rock.direction = actor.facing
				rock.speed_subpixels = actor.definition.projectile_speed_subpixels
				rocks.append(rock)
		if was_alive and actor.health == 0:
			record_permanent_kill(world,actor)
			if actor.definition.behavior == "gleeok": world.audio.play(&"enemy_die")
		for shot in actor.pending_shots:
			if rocks.size() >= projectile_limit: break
			var fireball: RefCounted = make_fireball(world, shot.position, shot.spread)
			fireball.damage = actor.definition.projectile_damage
			fireball.magic_blockable = actor.definition.projectile_magic_blockable
			rocks.append(fireball)
		actor.pending_shots.clear()
		if actor.health == 0 and actor.death_remaining == 0 and not actor.drop_resolved:
			actor.drop_resolved = true
			if actor.definition.counts_for_persistence: encounter_kills += 1
			world.state.kill_cycle = (world.state.kill_cycle + 1) % 10 if actor.definition.advances_kill_cycle else world.state.kill_cycle
			var table: Resource = world.loot_tables.get(actor.definition.id, actor.definition.loot_table)
			if table != null:
				var item: Resource = table.select(world.state.kill_cycle, actor.source_random if original else actor.rng.randi_range(0, 255))
				if item != null:
					var reward = Reward.new()
					reward.definition = item
					reward.position = actor.position()
					rewards.append(reward)
		var reach: Vector2i = actor.collision_size() / 2 + Vector2i.ONE
		var gap: Vector2i = (actor.position() + actor.definition.collision_offset + actor.collision_size() / 2 - world.player.pixel_position() - Vector2i(8, 8)).abs()
		if actor.can_touch_player() and actor.invulnerability == 0 and ((gap.x < reach.x and gap.y < reach.y) if original else actor.hurtbox().intersects(player_box(world))):
			touch_player(world, actor)
	ambush_timer = int(context.ambush_timer)
	wallmaster_cooldown = int(context.wallmaster_cooldown)
	split_zols(world)
	for rock in rocks:
		if rock.kind == "boomerang":
			tick_boomerang(world, rock)
			continue
		if rock.kind == "fireball":
			tick_fireball(world, rock)
			continue
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
				if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
					world.audio.play(&"parry")
					rock.alive = false
				elif hurt_player(world, rock.damage, at):
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

## The magical shield also turns Lynel sword shots (Z_07 HandleShotBlocked).
func shield_blocks(world: Node, rock: RefCounted) -> bool:
	return rock.blockable or (rock.kind in ["sword", "magic", "fireball"] and rock.magic_blockable and world.state.item_value(&"magic_shield") > 0)

## Contact effects: damage, capture (Like Like, Wallmaster), or a Bubble's
## effect on the sword (Z_04 UpdateBubble).
func touch_player(world: Node, actor: RefCounted) -> void:
	match actor.definition.contact_effect:
		"block_sword":
			world.state.sword_block_ticks = 0xA0
		"curse_sword":
			world.state.sword_cursed = true
		"restore_sword":
			world.state.sword_cursed = false
		"capture":
			if world.captor == null and player_invulnerability == 0:
				world.captor = actor
				actor.capture_ticks = 1
				if actor.definition.behavior == "wallmaster": world.player.place(actor.position())
			if actor.definition.contact_damage > 0: hurt_player(world, actor.definition.contact_damage, actor.position())
			# UpdateLikeLike clears Link's shove; a held Link is never knocked away.
			if world.captor == actor: shove_remaining = 0
		_:
			hurt_player(world, actor.definition.contact_damage, actor.position())

## Z_04 Zol_CheckCollisions and UpdateZolState2_Split: a Zol that survives a
## hit becomes two Gels darting perpendicular to it, without a drop.
func split_zols(world: Node) -> void:
	for actor in enemies.duplicate():
		if not actor.split_pending: continue
		actor.split_pending = false
		actor.health = 0
		actor.death_remaining = 0
		actor.drop_resolved = true
		var first := Vector2i.LEFT if actor.facing.y != 0 else Vector2i.UP
		# UpdateVire: two red Keese fly off in their own random directions; Digdogger's
		# children take random eight-way directions from InitDigdogger1.
		var directions: Array = [first, -first] if actor.definition.behavior == "gel" else []
		if directions.is_empty():
			for i in range(actor.definition.split_count): directions.append(Vector2i.ZERO)
		for direction in directions:
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id) + "_gel")
			spawn.enemy = actor.definition.splits_into
			spawn.position = actor.position()
			spawn.facing = direction
			spawn.spawn_ticks = 0
			var gel = Actor.new()
			gel.setup(spawn)
			gel.spawn_remaining = 0
			gel.slot = actor.slot
			if actor.definition.behavior == "digdogger":
				gel.subposition = (actor.position() + Vector2i(8, 8)) * 256
				gel.facing = OverworldEnemy.DIRS[(source_random.at(actor.slot) + directions.size()) & 7]
			if actor.definition.behavior == "gel":
				gel.family.split_ticks = 5
				gel.family.initialized = true
			gel.source.grid_offset = actor.source.grid_offset
			enemies.append(gel)
		encounter_total += directions.size() - 1

## Z_04 UpdateFireball: aimed at Link when made (FireballQSpeeds by the
## _CalcDiagonalSpeedIndex angle), still for 16 frames, then flying through walls
## until it leaves the room bounds.
const FIREBALL_X := [0x70, 0x68, 0x60, 0x58, 0x50, 0x3C, 0x26, 0x10, 0x00]
const FIREBALL_Y := [0x00, 0x10, 0x26, 0x3C, 0x50, 0x58, 0x60, 0x68, 0x70]

func make_fireball(world: Node, at: Vector2i, spread: int) -> RefCounted:
	var rock = Rock.new()
	rock.kind = "fireball"
	rock.subposition = at * 256
	rock.blockable = false
	rock.travelled = spread
	var player: Vector2i = world.player.pixel_position()
	var dx := player.x - at.x
	var dy := player.y - at.y
	var far := absi(dx)
	var near := absi(dy)
	var index := 4
	var step := -1
	if far < near:
		var swap := far
		far = near
		near = swap
		step = 1
	if far - near >= 8:
		while true:
			index += step
			if index == 0 or index == 8: break
			far -= near
			if far < near: break
	rock.direction = Vector2i(signi(dx) if dx != 0 else 1, signi(dy) if dy != 0 else 1)
	rock.velocity = Vector2i(FIREBALL_X[index], FIREBALL_Y[index]) * 4
	rock.age = 0
	return rock

func tick_fireball(world: Node, rock: RefCounted) -> void:
	rock.age += 1
	# Aquamentus spreads its three fireballs a pixel every other frame.
	if rock.travelled != 0 and frame_clock % 2 == 0 and rock.age < 0x70: rock.subposition.y += rock.travelled * 256
	if rock.age > 0x10:
		rock.subposition += Vector2i(rock.direction.x * rock.velocity.x, rock.direction.y * rock.velocity.y)
		if not bounds.grow(8).has_point(rock.position()):
			rock.alive = false
			return
	if player_invulnerability == 0 and source_contact(rock.position(), world.player.pixel_position()):
		if shield_blocks(world, rock) and world.player.facing.dot(rock.direction) < 0 and not world.sword.active():
			world.audio.play(&"parry")
		else:
			hurt_player(world, rock.damage, rock.position())
		rock.alive = false

## Z_07 UpdateArrowOrBoomerang for monster boomerangs: 2.5 pixels a frame out to
## $51 pixels or the room bounds, then back to the thrower.
func tick_boomerang(world: Node, rock: RefCounted) -> void:
	var owner: RefCounted = rock.owner
	if owner == null or owner.health <= 0:
		rock.alive = false
		if owner != null: owner.shot_out = false
		return
	if not rock.returning:
		rock.subposition += rock.direction * 640
		rock.travelled += 2
		var at: Vector2i = rock.position()
		if rock.travelled >= 0x51 or not bounds.grow(16).has_point(at): rock.returning = true
	else:
		var delta: Vector2i = owner.position() - rock.position()
		if absi(delta.x) < 8 and absi(delta.y) < 8:
			rock.alive = false
			owner.shot_out = false
			return
		rock.subposition += Vector2i(signi(delta.x), signi(delta.y)) * 640
	if player_invulnerability == 0 and source_contact(rock.position(), world.player.pixel_position()):
		if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
			world.audio.play(&"parry")
			rock.returning = true
		else:
			hurt_player(world, rock.damage, rock.position())

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
			if actor.targetable() and beam.hits(actor.hit_position()):
				if actor.receive_hit(beam.damage, beam.direction, "beam"):
					world.audio.play(&"enemy_hit")
					if actor.health == 0:
						world.audio.play(&"enemy_die")
						record_permanent_kill(world, actor)
					beam.impact()
					return
				if actor.parried_hit:
					world.audio.play(&"parry")
					beam.impact()
					return

func record_permanent_kill(world: Node, actor: RefCounted) -> void:
	if world.room.enemy_persistence == "permanent" and actor.definition.counts_for_persistence:
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
	if direction == Vector2i.LEFT and at.x < bounds.position.x: return false
	if direction == Vector2i.RIGHT and at.x >= bounds.end.x: return false
	if direction == Vector2i.UP and at.y < bounds.position.y: return false
	if direction == Vector2i.DOWN and at.y >= bounds.end.y: return false
	var probe := at + Vector2i(0, 11)
	if direction.x != 0:
		probe.x += 16 if direction.x > 0 else -16
		return not world.is_blocked(probe)
	probe.y += 16 if direction.y > 0 else -16
	return not world.is_blocked(probe) and not world.is_blocked(probe + Vector2i(8, 0))

func assign_source_spawns(room: Resource, state: RefCounted, player: Vector2i, direction: Vector2i) -> void:
	# Traps keep their fixed spots; Wallmasters wait in the walls.
	var original: Array = enemies.filter(func(actor: RefCounted) -> bool: return actor.definition.behavior not in ["native", "trap", "wallmaster", "aquamentus", "gohma", "gleeok"])
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
	if not source_within_bounds(rock.position(),rock.direction) or (rock.kind not in ["sword", "magic"] and not source_can_enter(world, rock.position(), rock.direction)):
		rock.alive = false
		return
	rock.subposition += rock.direction * rock.speed_subpixels
	var center: Vector2i = rock.position() + (Vector2i(4,8) if rock.kind == "rock" else Vector2i(8,8))
	var player_center: Vector2i = world.player.pixel_position() + Vector2i(8, 8)
	if player_invulnerability == 0 and source_contact(center, player_center):
		if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
			world.audio.play(&"parry")
			rock.bounce_direction = world.player.facing
			rock.bounce_remaining = 16
		else:
			hurt_player(world, rock.damage, rock.position())
			rock.alive = false

func source_within_bounds(at: Vector2i, direction: Vector2i) -> bool:
	if direction.x < 0 and at.x < bounds.position.x: return false
	if direction.x > 0 and at.x >= bounds.end.x: return false
	if direction.y < 0 and at.y < bounds.position.y: return false
	if direction.y > 0 and at.y >= bounds.end.y: return false
	return true
