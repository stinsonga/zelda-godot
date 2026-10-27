extends SceneTree

var failures := 0

func _initialize() -> void:
	create_timer(10).timeout.connect(func() -> void: push_error("Octorok suite did not finish"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func actor(kind: int = 7) -> RefCounted:
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"fixture"
	spawn.enemy = preload("res://content/enemies/red_octorok.tres").duplicate()
	spawn.enemy.behavior = "nes_octorok"
	spawn.enemy.nes_type = kind
	spawn.enemy.speed_subpixels = 256 if kind in [8, 10] else 128
	spawn.enemy.turn_chance = 160 if kind >= 9 else 112
	spawn.position = Vector2i(64, 45)
	spawn.facing = Vector2i.RIGHT
	var result = preload("res://scripts/enemy_actor.gd").new()
	result.setup(spawn)
	result.spawn_remaining = 0
	return result

func open_probe(_at: Vector2i, _direction: Vector2i) -> bool:
	return true

func run() -> void:
	var random = preload("res://scripts/nes_random.gd").new()
	random.bytes = PackedByteArray([2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	random.advance()
	check(random.bytes[0] == 129 and random.bytes[1] == 0, "NES random feedback must enter bit 7 before the carry propagates")
	random.advance()
	check(random.bytes[0] == 64 and random.bytes[1] == 128, "NES ROR must propagate the previous byte's low bit")
	var enemy = actor()
	enemy.subposition = Vector2i(79, 45) * 256
	enemy.source.grid_offset = 15
	enemy.source.move_speed = 256
	# Mid-walk, the previous update left its facing as the input direction.
	enemy.source.input_direction = enemy.facing
	enemy.source.tick(enemy, Vector2i(80, 13), open_probe, true, 42, 0)
	check(enemy.position() == Vector2i(80, 45) and enemy.facing == Vector2i.UP, "Walker must move to its grid boundary before choosing the next facing")
	check(enemy.source.turn_timer == 42 and enemy.source.wants_to_shoot, "Aligned targeting must latch wants-to-shoot and use the current random byte as its timer")
	enemy.source.move_speed = 256
	enemy.source.tick(enemy, Vector2i(160, 45), open_probe, true, 0, 0)
	check(enemy.position() == Vector2i(80, 44) and enemy.facing == Vector2i.UP, "Target changes must not turn an enemy between grid points")
	enemy = actor()
	enemy.source.turn_timer = 5
	enemy.source.select_target(enemy, Vector2i(100, 100), 60, 255)
	check(enemy.facing == Vector2i.RIGHT and not enemy.source.wants_to_shoot, "A non-aligned target must preserve facing until the turn timer expires")
	enemy.source.turn_timer = 0
	enemy.source.select_target(enemy, Vector2i(100, 0), 60, 255)
	check(enemy.facing == Vector2i.UP and enemy.source.turn_timer == 60 and enemy.source.wants_to_shoot, "Expired turn timer must choose the target-facing perpendicular axis")
	enemy = actor()
	var attempts: Array[Vector2i] = []
	var probe := func(_at: Vector2i, direction: Vector2i) -> bool:
		attempts.append(direction)
		return direction == Vector2i.DOWN
	check(enemy.source.choose_movement(enemy, probe, 128) == Vector2i.DOWN, "Blocked walker must search the random perpendicular direction, then its opposite")
	check(attempts == [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN], "Alternate direction order must match the source")
	enemy = actor()
	enemy.source.move_speed = 0
	enemy.source.wants_to_shoot = true
	enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 247, 0)
	check(enemy.source.shoot_timer == 0, "Red Octorok must reject a shooting random byte below F8")
	enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 248, 0)
	check(enemy.source.shoot_timer == 48 and enemy.source.move_speed == 0, "F8 must start the 48-tick shot timer")
	for tick in range(31):
		check(not enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 0, 0), "Shot must not emit before timer 10")
	check(enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 0, 0) and enemy.source.shoot_timer == 16, "Shot must emit when the timer reaches 10 hex")
	for tick in range(16): enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 0, 0)
	check(enemy.source.shoot_timer == 0 and enemy.source.move_speed == 128, "Post-shot recovery must finish before normal movement resumes")
	enemy = actor(9)
	enemy.source.move_speed = 0
	enemy.source.wants_to_shoot = true
	enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 0, 0)
	check(enemy.source.shoot_timer == 48, "Blue Octorok must bypass the red random shooting gate")
	enemy.source.shoot_timer = 17
	check(not enemy.source.tick(enemy, Vector2i(128, 45), open_probe, false, 0, 0), "Full projectile slots must prevent emission at timer 10")
	enemy.invulnerability = 10
	enemy.source.tick(enemy, Vector2i(128, 45), open_probe, true, 0, 0)
	check(enemy.source.shoot_timer == 0, "Temporary invulnerability must cancel an active shot timer")
	check(actor(8).source.move_speed == 192 and actor(8).definition.speed_subpixels == 256, "Fast Octorok must distinguish initial 0.75 speed from its later 1-pixel update speed")
	enemy = actor()
	enemy.source.grid_offset = 3
	enemy.shove_direction = Vector2i.UP
	enemy.shove_remaining = 64
	enemy.source.shove(enemy, open_probe)
	check(enemy.shove_remaining == 0, "Perpendicular shove must cancel between source grid points")
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.combat.enemies.clear()
	check(world.combat.source_contact(Vector2i(80, 77), Vector2i(88, 85)), "Contact must include an eight-pixel separation on both axes")
	check(not world.combat.source_contact(Vector2i(80, 77), Vector2i(89, 77)), "Contact must exclude the exact nine-pixel threshold")
	var room: Resource = world.room.duplicate()
	room.collision_tiles.resize(704)
	room.collision_tiles.fill(0)
	world.room = room
	room.collision_tiles[7 * 32 + 10] = 1
	check(not world.combat.source_can_enter(world, Vector2i(64, 45), Vector2i.RIGHT), "Horizontal walker probe must inspect its leading column at Y plus eleven")
	room.collision_tiles.fill(0)
	room.collision_tiles[9 * 32 + 9] = 1
	check(not world.combat.source_can_enter(world, Vector2i(64, 45), Vector2i.DOWN), "Vertical probe must inspect both eight-pixel columns sixteen pixels ahead")
	room.collision_tiles.fill(0)
	check(not world.combat.source_can_enter(world, Vector2i(16, 45), Vector2i.LEFT), "Source left room bound must reject outward movement")
	check(not world.combat.source_can_enter(world, Vector2i(224, 45), Vector2i.RIGHT), "Source right room bound must reject outward movement")
	world.combat.source_random.bytes.fill(0)
	world.combat.source_random.bytes[1] = 3
	world.combat.chase_other = false
	world.combat.chase_timer = 0
	world.combat.update_chase_target(Vector2i(80, 77))
	check(world.combat.chase_other and world.combat.chase_target == Vector2i(175, 50), "Chase target reflection must include NES screen-Y coordinates")
	for tick in range(29): world.combat.advance_frame()
	check(world.combat.chase_timer == 1, "Long chase timer must decrement every ten frames")
	world.combat.advance_frame()
	check(world.combat.chase_timer == 0, "Long chase timer must expire on its tenth-frame boundary")
	# Hand-authored position lists exercise the importer-independent spawn model.
	for direction in range(4):
		var points := PackedByteArray()
		for i in range(9): points.append(0x75 + direction)
		world.combat.spawn_lists.append(points)
	enemy = actor()
	world.combat.enemies.append(enemy)
	world.combat.assign_source_spawns(room, world.state, Vector2i(0, 77), Vector2i.LEFT)
	check(enemy.position() == Vector2i(96, 61) and not enemy.waiting_spawn, "Entry facing must select its directional spawn list")
	world.combat.assign_source_spawns(room, world.state, Vector2i(96, 61), Vector2i.LEFT)
	check(enemy.waiting_spawn, "A list entirely too close to Link must remain pending instead of hanging")
	world.combat.assign_source_spawns(room, world.state, Vector2i(0, 77), Vector2i.LEFT)
	check(not enemy.waiting_spawn, "Moving away must allow pending cloud spawns to retry")
	room.source_edge_spawns = true
	room.source_edge_cells = PackedByteArray([0x50, 0x60, 0x70])
	enemy.waiting_spawn = true
	world.combat.edge_cursor = 0x40
	world.combat.edge_timer = 0
	world.player.place(Vector2i(120, 125))
	world.combat.update_edge_spawns(world)
	check(not enemy.waiting_spawn and enemy.position() == Vector2i(0, 13) and enemy.spawn_remaining == 0, "Edge enemies must initialize at the boundary without cloud delay")
	check(world.combat.edge_timer >= 2 and world.combat.edge_timer <= 5, "Edge spawn interval must use two through five long-timer units")
	world.combat.enemies.clear()
	world.player.place(Vector2i(80, 77))
	world.player.facing = Vector2i.RIGHT
	world.combat.player_invulnerability = 0
	var rock = preload("res://scripts/rock_projectile.gd").new()
	rock.source_rules = true
	rock.speed_subpixels = 768
	rock.subposition = Vector2i(96, 77) * 256
	rock.direction = Vector2i.LEFT
	world.combat.tick_source_rock(world, rock)
	check(rock.position().x == 96, "Newly emitted source rock must wait for its next update")
	# Its init frame (InitObject) comes next; it moves on the third.
	world.combat.tick_source_rock(world, rock)
	check(rock.position().x == 96, "and spends a frame being initialized")
	world.combat.tick_source_rock(world, rock)
	check(rock.position().x == 93, "Source rock must move three pixels per update")
	world.combat.tick_source_rock(world, rock)
	check(rock.bounce_remaining == 16 and world.state.health == 6, "Facing shield must start a harmless source bounce")
	for tick in range(16): world.combat.tick_source_rock(world, rock)
	check(not rock.alive and rock.position() == Vector2i(122, 61), "Shield bounce must use source displacements for sixteen ticks")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		check(world.combat.spawn_lists.size() == 4 and world.rooms[&"ow_78"].source_edge_spawns, "Import must provide source position lists and east-screen edge spawning")
		world.enter_room(world.rooms[&"ow_78"], Vector2i(0, 77), Vector2i.RIGHT)
		check(world.combat.enemies.size() == 4 and world.combat.enemies.all(func(a: RefCounted) -> bool: return a.waiting_spawn), "East encounter must initially wait at its edge-spawn scheduler")
		for tick in range(400):
			world.combat.player_invulnerability = 10000
			world.simulate_tick(Vector2i.ZERO)
		check(world.combat.enemies.any(func(a: RefCounted) -> bool: return a.alive()), "Actual edge encounter must eventually spawn walking Octoroks")
		world.free()
	print("Octorok fidelity checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
