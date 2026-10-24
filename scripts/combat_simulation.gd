class_name CombatSimulation
extends RefCounted

const Actor = preload("res://scripts/enemy_actor.gd")
const Rock = preload("res://scripts/rock_projectile.gd")
var enemies: Array[RefCounted] = []
var rocks: Array[RefCounted] = []
var player_invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO

func enter_room(room: Resource, state: RefCounted) -> void:
	enemies.clear()
	rocks.clear()
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
	for actor in enemies:
		if actor.alive() and world.sword.damaging() and world.sword.hitbox(world.player.pixel_position()).intersects(actor.hurtbox()):
			if actor.receive_hit(world.sword.weapon.damage, world.sword.direction) and actor.health == 0:
				world.state.defeated[String(world.room.id) + "/" + String(actor.id)] = true
		if actor.tick(world.player.pixel_position(), func(at: Vector2i) -> bool: return can_enemy_occupy(world, at)):
			var rock = Rock.new()
			rock.subposition = (actor.position() + actor.facing * 12) * 256
			rock.direction = actor.facing
			rock.speed_subpixels = actor.definition.projectile_speed_subpixels
			rocks.append(rock)
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
			elif rock.hurtbox().intersects(player_box(world)):
				# The basic shield blocks rocks arriving from the facing direction,
				# while Link is free to defend (not using the sword).
				if world.player.facing == -rock.direction and not world.sword.active():
					rock.alive = false
				elif hurt_player(world, 1, at):
					rock.alive = false
	rocks = rocks.filter(func(rock: RefCounted) -> bool: return rock.alive)

func player_box(world: Node) -> Rect2i:
	return Rect2i(world.player.pixel_position() + Vector2i(2, 2), Vector2i(12, 12))
