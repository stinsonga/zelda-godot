extends SceneTree
var failures := 0
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: push_error("Enemy suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func actor(definition: Resource) -> RefCounted:
	var spawn := Spawn.new()
	spawn.id = &"fixture"
	spawn.enemy = definition
	spawn.position = Vector2i(80,77)
	spawn.facing = Vector2i.RIGHT
	var result := Actor.new()
	result.setup(spawn)
	result.spawn_remaining = 0
	return result
func open_probe(_at: Vector2i, _direction: Vector2i) -> bool: return true
func run() -> void:
	var moblin = actor(preload("res://content/enemies/moblin.tres"))
	var lynel = actor(preload("res://content/enemies/lynel.tres"))
	lynel.source.select_target(lynel,Vector2i(120,141),0,0)
	check(lynel.facing == Vector2i.DOWN and lynel.source.wants_to_shoot, "Lynel must target the farther axis inside its source range")
	lynel.source.select_target(lynel,Vector2i(200,141),0,0)
	check(not lynel.source.wants_to_shoot, "Lynel must refuse targets beyond 80 pixels")
	moblin.source.select_target(moblin,Vector2i(120,77),10,0)
	check(moblin.facing == Vector2i.RIGHT, "Moblin must use aligned targeting")
	moblin.source.move_speed = 0
	moblin.source.wants_to_shoot = true
	moblin.source.tick(moblin,Vector2i(120,77),open_probe,true,247,0)
	check(moblin.source.shoot_timer == 0, "Red Moblin must use the red shooting gate")
	var swift = actor(preload("res://content/enemies/swift_moblin.tres"))
	swift.source.move_speed = 0
	swift.source.wants_to_shoot = true
	swift.source.tick(swift,Vector2i(120,77),open_probe,true,0,0)
	check(swift.source.shoot_timer == 48 and swift.health == 3 and swift.definition.speed_subpixels == 192, "Editable Moblin variant must change health, speed, and shooting gate")
	var tek = actor(preload("res://content/enemies/tektite.tres"))
	tek.family.initialized = true
	tek.family.jump_direction = Vector2i.RIGHT
	tek.family.begin_jump(tek)
	var start: Vector2i = tek.position()
	tek.tick(Vector2i(160,77),func(_at: Vector2i) -> bool: return false,func(_at: Vector2i,_d: Vector2i) -> bool: return false)
	check(tek.position().x > start.x and tek.position().y < start.y, "Tektite must jump over solid terrain")
	for tick in range(100):
		if tek.family.phase == 0: break
		tek.tick(Vector2i(160,77),func(_at: Vector2i) -> bool: return false,open_probe)
	check(tek.family.phase == 0, "Tektite must land and enter a waiting state")
	var high = actor(preload("res://content/enemies/high_tektite.tres"))
	high.family.begin_jump(high)
	check(high.family.velocity_y < tek.definition.jump_velocity_subpixels and high.health == 3, "Editable Tektite must use its own launch velocity and health")
	var leever = actor(preload("res://content/enemies/leever.tres"))
	check(not leever.body_visible() and not leever.targetable() and not leever.can_touch_player(), "Hidden Leever must neither draw nor collide")
	check(not leever.receive_hit(1,Vector2i.RIGHT), "Hidden Leever must reject damage")
	leever.family.phase = 2
	check(leever.body_visible() and not leever.targetable(), "Emerging Leever must be visible without vulnerability")
	leever.family.phase = 3
	check(leever.targetable() and leever.can_touch_player() and leever.receive_hit(1,Vector2i.RIGHT), "Exposed Leever must participate in combat")
	var ambush = actor(preload("res://content/enemies/ambush_leever.tres"))
	ambush.family.initialized = true
	var context := {"player":Vector2i(120,77),"player_facing":Vector2i.RIGHT,"ambush_timer":0,"active_ambush":0,"spawn_allowed":func(_at: Vector2i) -> bool: return true}
	ambush.tick(Vector2i(120,77),func(_at: Vector2i) -> bool: return true,open_probe,true,context)
	check(ambush.position() == Vector2i(160,77) and ambush.facing == Vector2i.LEFT and ambush.family.phase == 1, "Red Leever must emerge ahead of Link and face back toward him")
	check(context.ambush_timer == 20 and context.active_ambush == 1, "Red Leevers must share emergence spacing and active-count controls")
	var blocked = actor(preload("res://content/enemies/ambush_leever.tres"))
	context.ambush_timer = 0
	context.active_ambush = 2
	blocked.tick(Vector2i(120,77),func(_at: Vector2i) -> bool: return true,open_probe,true,context)
	check(blocked.family.phase == 0, "At most two red Leevers may be above ground")
	var flyer = actor(preload("res://content/enemies/peahat.tres"))
	flyer.family.initialized = true
	flyer.family.phase = 2
	flyer.family.flight_speed = 160
	flyer.family.timer = 20
	check(not flyer.targetable() and flyer.can_touch_player() and not flyer.receive_hit(1,Vector2i.RIGHT), "Flying Peahat must hurt Link but reject weapon damage")
	start = flyer.position()
	for tick in range(4): flyer.tick(Vector2i(180,77),func(_at: Vector2i) -> bool: return false,func(_at: Vector2i,_d: Vector2i) -> bool: return false)
	check(flyer.position() != start, "Flying Peahat must ignore terrain")
	flyer.family.phase = 5
	flyer.family.timer = 10
	flyer.family.flight_speed = 31
	start = flyer.position()
	for tick in range(4): flyer.tick(Vector2i.ZERO,func(_at: Vector2i) -> bool: return true,open_probe)
	check(flyer.position() == start and flyer.receive_hit(1,Vector2i.RIGHT), "Resting Peahat must stop and become vulnerable")
	var independent = actor(preload("res://content/enemies/peahat.tres"))
	check(independent.family.phase == 0 and independent.health == 2, "Actors sharing definitions must retain independent mutable state")
	var invalid: Resource = preload("res://content/enemies/leever.tres").duplicate()
	invalid.burrow_times = PackedInt32Array([1,2])
	check(not invalid.validation_errors().is_empty(), "Malformed editable behavior data must be rejected")
	var world = preload("res://scenes/enemy_gallery.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check(world.room.validation_errors().is_empty() and world.combat.enemies.size() == 9, "Source-only enemy gallery must load all families and custom variants")
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.equipped_weapon != null, "Gallery must provide a sword at its entrance")
	# Custom rooms retain authored positions even when the world has NES lists.
	for i in range(4): world.combat.spawn_lists.append(PackedByteArray([0x75,0x75,0x75,0x75,0x75,0x75,0x75,0x75,0x75]))
	world.enter_room(world.room,world.room.spawn,Vector2i.UP)
	check(world.combat.enemies[0].position() == world.room.enemies[0].position, "Native room positions must survive in a world with original spawn tables")
	world.combat.enemies.clear()
	var room: Resource = world.room.duplicate()
	room.collision_tiles.resize(704)
	room.collision_tiles.fill(0)
	world.room = room
	world.player.place(Vector2i(80,77))
	world.player.facing = Vector2i.RIGHT
	for kind in ["arrow","sword"]:
		world.state.health = 6
		world.combat.player_invulnerability = 0
		var rock = preload("res://scripts/rock_projectile.gd").new()
		rock.source_rules = true
		rock.kind = kind
		rock.damage = 2 if kind == "sword" else 1
		rock.blockable = kind != "sword"
		rock.speed_subpixels = 768 if kind == "sword" else 512
		rock.subposition = Vector2i(96,77)*256
		rock.direction = Vector2i.LEFT
		for tick in range(6):
			if rock.alive: world.combat.tick_source_rock(world,rock)
		check(rock.bounce_remaining > 0 if kind == "arrow" else world.state.health == 4 and not rock.alive, "Arrows must block; Lynel swords must penetrate the basic shield with their own damage")
	# Simultaneous ready walkers share the original global shot cap and retain kinds.
	world.state.health = 6
	world.combat.player_invulnerability = 10000
	world.combat.rocks.clear()
	for i in range(6):
		var shooter = actor(preload("res://content/enemies/swift_moblin.tres"))
		shooter.slot = i+1
		shooter.source.shoot_timer = 17
		shooter.source.move_speed = 0
		shooter.source.wants_to_shoot = true
		world.combat.enemies.append(shooter)
	world.combat.tick(world)
	check(world.combat.rocks.size() == 4 and world.combat.rocks.all(func(r: RefCounted) -> bool: return r.kind == "arrow" and r.speed_subpixels == 768), "Mixed walkers must share the shot cap and honor editable projectile speed/type")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		var seen := {}
		var mixed := 0
		var rooms_checked := 0
		for definition in world.room_resources:
			if definition.enemies.is_empty() or definition.dungeon_level > 0: continue
			world.enter_room(definition,definition.spawn,Vector2i.UP)
			var types := {}
			for enemy in definition.enemies:
				types[enemy.enemy.id] = true
				seen[enemy.enemy.id] = true
			if types.size() > 1: mixed += 1
			for tick in range(500):
				world.combat.player_invulnerability = 10000
				world.simulate_tick(Vector2i.ZERO)
			check(world.combat.rocks.size() <= 4, "Imported encounter must respect projectile limit")
			rooms_checked += 1
		check(seen.size() == 16 and mixed > 0 and rooms_checked > 80, "Import must populate the thirteen common enemy types, the Ghini, boulder sets, pond fairies, and mixed encounters (%d)" % seen.size())
		print("Imported encounters simulated: ",rooms_checked,"; mixed: ",mixed,"; types: ",seen.size())
		world.free()
	print("More enemy checks: ","PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
