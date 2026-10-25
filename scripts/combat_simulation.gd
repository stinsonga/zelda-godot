class_name CombatSimulation
extends RefCounted

const Beam = preload("res://scripts/sword_beam.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Reward = preload("res://scripts/dropped_reward.gd")
const Rock = preload("res://scripts/rock_projectile.gd")
var beam: RefCounted
var rewards: Array[RefCounted] = []
var enemies: Array[RefCounted] = []
var rocks: Array[RefCounted] = []
var player_invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO

func enter_room(room: Resource, state: RefCounted) -> void:
	beam = null
	enemies.clear()
	rocks.clear()
	rewards.clear()
	shove_remaining = 0
	for spawn in room.enemies:
		if state.defeated.has(String(room.id) + "/" + String(spawn.id)): continue
		var actor = Actor.new()
		actor.setup(spawn)
		enemies.append(actor)

func can_enemy_occupy(world: Node, at: Vector2i) -> bool:
	if at.x < 16 or at.x > 224 or at.y < 13 or at.y > 141: return false
	for point in [at + Vector2i(2, 8), at + Vector2i(13, 8), at + Vector2i(2, 15), at + Vector2i(13, 15)]:
		if world.is_blocked(point): return false
	return true

func hurt_player(world: Node, damage: int, source: Vector2i) -> bool:
	if player_invulnerability > 0 or world.state.health <= 0: return false
	world.state.health = maxi(0, world.state.health - damage)
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
	for actor in enemies:
		if actor.alive() and world.sword.hits(world.player.pixel_position(), actor.position()):
			if actor.receive_hit(world.sword.weapon.damage, world.sword.direction) and actor.health == 0:
				world.state.defeated[String(world.room.id) + "/" + String(actor.id)] = true
		if actor.tick(world.player.pixel_position(), func(at: Vector2i) -> bool: return can_enemy_occupy(world, at)):
			var rock = Rock.new()
			rock.subposition = (actor.position() + actor.facing * 12) * 256
			rock.direction = actor.facing
			rock.speed_subpixels = actor.definition.projectile_speed_subpixels
			rocks.append(rock)
		if actor.health == 0 and actor.death_remaining == 0 and not actor.drop_resolved:
			actor.drop_resolved = true
			world.state.kill_cycle = (world.state.kill_cycle + 1) % 10
			var table: Resource = world.loot_tables.get(actor.definition.id, actor.definition.loot_table)
			if table != null:
				var item: Resource = table.select(world.state.kill_cycle, actor.rng.randi_range(0, 255))
				if item != null:
					var reward = Reward.new()
					reward.definition = item
					reward.position = actor.position()
					rewards.append(reward)
		if actor.alive() and actor.invulnerability == 0 and actor.hurtbox().intersects(player_box(world)):
			hurt_player(world, actor.definition.contact_damage, actor.position())
	for rock in rocks:
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
			if touched: reward.take(world.state)
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
					if actor.health == 0:
						world.state.defeated[String(world.room.id) + "/" + String(actor.id)] = true
					beam.impact()
					return
