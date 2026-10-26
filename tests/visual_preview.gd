extends SceneTree
## Render deterministic cave, shop, secret, lifting, or sword views for screenshot review.
func _initialize() -> void:
	call_deferred("preview")

func preview() -> void:
	var args := OS.get_cmdline_user_args()
	# The ROM-free dungeon lab: dungeon_lab [entry|hall|block|cellar|treasure].
	if args.has("dungeon_lab"):
		var lab = preload("res://scenes/dungeon_lab.tscn").instantiate()
		root.add_child(lab)
		lab.set_physics_process(false)
		for name in ["entry", "hall", "block", "cellar", "treasure"]:
			if args.has(name): lab.enter_room(lab.rooms[StringName("lab_dungeon_" + name)], Vector2i(120, 125), Vector2i.UP)
		if args.has("block"):
			lab.secrets.revealed = true
			lab.overrides = lab.compute_overrides(lab.room)
		lab.queue_redraw()
		return
	if args.has("bait_lab"):
		var lab = preload("res://scenes/bait_lab.tscn").instantiate()
		root.add_child(lab)
		lab.set_physics_process(false)
		for i in range(1000):
			if lab.cave_session.phase == "waiting_bait": break
			lab.simulate_tick(Vector2i.ZERO)
		lab.queue_redraw()
		return
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	if not world.rooms.has(&"cave_77"):
		push_error("Visual previews require a local ROM import")
		quit(1)
		return
	if args.has("bait"):
		world.enter_room(world.rooms[&"l7_28"], Vector2i(120,125), Vector2i.UP)
		for i in range(1000):
			if world.cave_session.phase == "waiting_bait": break
			world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("dark_room") or args.has("lit_room"):
		for candidate in world.room_resources:
			if not candidate.dark_room or candidate.dungeon_level!=4:continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP,0,true)
			if args.has("lit_room"):world.lighting.stage=0
			world.queue_redraw()
			return
		push_error("Dark room preview missing")
		quit(1)
		return
	if args.has("ganon_dark") or args.has("ganon_fade"):
		for candidate in world.room_resources:
			if not candidate.enemies.any(func(s:Resource)->bool:return s.enemy.behavior=="ganon"):continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			if args.has("ganon_fade"):
				var fight=world.combat.enemies.filter(func(a:RefCounted)->bool:return a.definition.behavior=="ganon")[0].family.ganon
				fight.darkness=1
			world.queue_redraw()
			return

	if args.has("ganon") or args.has("ganon_brown") or args.has("ganon_burst") or args.has("zelda"):
		if args.has("zelda"):
			world.enter_room(world.rooms[&"l9_32"], Vector2i(120, 125), Vector2i.UP)
			world.queue_redraw()
			return
		world.enter_room(world.rooms[&"l9_42"], Vector2i(120, 125), Vector2i.UP)
		var ganon: RefCounted = world.combat.enemies[0]
		var fight: RefCounted = ganon.family.ganon
		# The intro preview stops while the room is still brightening.
		for tick in range(0x40 + (12 if args.has("ganon") else 400)):
			world.combat.player_invulnerability = 10000
			world.simulate_tick(Vector2i.ZERO)
		if not args.has("ganon"):
			ganon.receive_hit(ganon.health, Vector2i.UP, "sword")
			if args.has("ganon_burst"):
				world.combat.ganon_arrow_hit(ganon, true)
				for tick in range(0x60):
					world.combat.player_invulnerability = 10000
					world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("moldorm"):
		for candidate in world.room_resources:
			if not candidate.enemies.any(func(s:Resource)->bool:return s.enemy.behavior=="moldorm"):continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			for tick in range(140):
				world.combat.player_invulnerability=10000
				world.simulate_tick(Vector2i.ZERO)
			world.queue_redraw()
			return
		push_error("Moldorm preview room missing")
		quit(1)
		return
	if args.has("gleeok2") or args.has("gleeok4"):
		var count := 4 if args.has("gleeok4") else 2
		for candidate in world.room_resources:
			if not candidate.enemies.any(func(s: Resource)->bool: return s.enemy.behavior=="gleeok" and s.enemy.gleeok_neck_count==count):continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			for tick in range(100):
				world.combat.player_invulnerability=10000
				world.simulate_tick(Vector2i.ZERO)
			if args.has("detached"):
				var group = world.combat.enemies.back().family.gleeok
				group.heads[0].get_ref().receive_hit(100,Vector2i.UP,"sword")
				for tick in range(25):world.simulate_tick(Vector2i.ZERO)
			world.queue_redraw()
			return
		push_error("Gleeok preview room missing")
		quit(1)
		return
	if args.has("manhandla"):
		for candidate in world.room_resources:
			if candidate.dungeon_level != 3 or not candidate.enemies.any(func(spawn: Resource) -> bool: return spawn.enemy.behavior == "manhandla"): continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			for actor in world.combat.enemies:
				actor.family.manhandla.center = Vector2i(120,77)
				actor.subposition = (Vector2i(120,77)+actor.family.manhandla_offset)*256
			world.queue_redraw()
			return
		push_error("Imported Manhandla room missing")
		quit(1)
		return
	if args.has("enemies"):
		world.enter_room(world.rooms[&"ow_78"],Vector2i(120,141),Vector2i.UP)
		world.combat.enemies.clear()
		var labels := ["red_moblin", "blue_moblin", "red_lynel", "blue_lynel", "red_tektite", "blue_tektite", "red_leever", "blue_leever", "peahat"]
		for i in range(labels.size()):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(labels[i])
			spawn.enemy = load("res://imported/enemies/" + labels[i] + ".tres")
			spawn.position = Vector2i(64+(i%3)*48,29+(i/3)*48)
			spawn.facing = [Vector2i.RIGHT,Vector2i.DOWN,Vector2i.UP][i%3]
			var actor = preload("res://scripts/enemy_actor.gd").new()
			actor.setup(spawn)
			actor.spawn_remaining = 0
			actor.family.initialized = true
			if actor.definition.behavior == "burrower": actor.family.phase = 3
			world.combat.enemies.append(actor)
		world.queue_redraw()
		return
	if args.has("octorok") or args.has("octorok_cloud"):
		var room_id: StringName = &"ow_67" if args.has("octorok_cloud") else &"ow_78"
		var at := Vector2i(120, 157) if args.has("octorok_cloud") else Vector2i(0, 77)
		var facing := Vector2i.UP if args.has("octorok_cloud") else Vector2i.RIGHT
		world.enter_room(world.rooms[room_id], at, facing)
		for tick in range(10 if args.has("octorok_cloud") else 400):
			world.combat.player_invulnerability = 10000
			world.simulate_tick(Vector2i.ZERO)
		world.combat.player_invulnerability = 0
		world.queue_redraw()
		return
	for label in ["scroll_right", "scroll_left", "scroll_up", "scroll_down"]:
		if not args.has(label): continue
		var direction := Vector2i.RIGHT
		var id: StringName = &"ow_77"
		var at := Vector2i(240, 77)
		match label:
			"scroll_left":
				id = &"ow_78"
				at = Vector2i(0, 77)
				direction = Vector2i.LEFT
			"scroll_up":
				at = Vector2i(120, -3)
				direction = Vector2i.UP
			"scroll_down":
				id = &"ow_67"
				at = Vector2i(120, 157)
				direction = Vector2i.DOWN
		world.enter_room(world.rooms[id], at, direction)
		world.try_exit(direction)
		assert(world.transition != null, "Preview exit is blocked")
		for tick in range(32 if direction.x != 0 else 22): world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("combat") or args.has("beam") or args.has("burst") or args.has("health") or args.has("saved"):
		world.enter_room(world.rooms[&"ow_78"], Vector2i(120, 77), Vector2i.UP)
		world.state.equipped_weapon = preload("res://content/items/wooden_sword.tres")
		world.state.health = 4
		world.state.rupees = 13
		if args.has("saved"): world.show_status("GAME SAVED")
		if args.has("health"):
			world.state.health = world.state.max_health
			world.combat.hurt_player(world, 1, Vector2i(100, 77))
		for i in range(world.combat.enemies.size()):
			var actor = world.combat.enemies[i]
			actor.spawn_remaining = 0
			actor.waiting_spawn = false
			actor.subposition = Vector2i(64 + i * 32, 93) * 256
			actor.facing = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN][i % 4]
			actor.animation_ticks = (i % 2) * 6
		var reward = preload("res://scripts/dropped_reward.gd").new()
		reward.definition = preload("res://content/items/heart.tres")
		reward.position = Vector2i(80, 80)
		reward.age = 40
		world.combat.rewards.append(reward)
		reward = preload("res://scripts/dropped_reward.gd").new()
		reward.definition = preload("res://content/items/rupee.tres")
		reward.position = Vector2i(128, 112)
		reward.age = 40
		world.combat.rewards.append(reward)
		if args.has("beam") or args.has("burst"):
			world.state.health = 6
			world.player.place(Vector2i(120, 93))
			world.player.facing = Vector2i.RIGHT
			world.sword.start(world.state.equipped_weapon, Vector2i.RIGHT)
			world.combat.launch_beam(world)
			world.sword.phase = -1
			world.combat.beam.position = Vector2i(160, 93)
			world.simulation_tick = 1
			if args.has("burst"):
				world.combat.beam.impact()
				world.combat.beam.burst_remaining = 12
		world.queue_redraw()
		return
	if args.has("monsters1") or args.has("monsters2") or args.has("regulars") or args.has("wizzrobes"):
		var level := 1 if args.has("monsters1") else 2
		for arg in args:
			if arg.begins_with("lv"): level = int(arg.substr(2))
		var start: Resource = null
		for definition in world.rooms.values():
			if definition.dungeon_level == level and definition.portals.any(func(p: Resource) -> bool: return world.rooms[p.target_room].dungeon_level == 0): start = definition
		world.enter_room(start, Vector2i(120, 141), Vector2i.UP)
		world.combat.enemies.clear()
		var names := ["stalfos", "red_goriya", "blue_goriya", "gel", "zol", "blue_keese", "red_keese", "rope"]
		if args.has("regulars"): names = ["red_darknut", "blue_darknut", "gibdo", "like_like", "vire", "pols_voice", "bubble", "trap"]
		if args.has("wizzrobes"): names = ["blue_wizzrobe", "red_wizzrobe", "blue_wizzrobe", "red_wizzrobe"]
		for i in range(names.size()):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(names[i])
			spawn.enemy = load("res://imported/enemies/" + names[i] + ".tres")
			spawn.position = Vector2i(48 + (i % 4) * 48, 45 + (i / 4) * 48)
			spawn.facing = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP][i % 4]
			var actor = preload("res://scripts/enemy_actor.gd").new()
			actor.setup(spawn)
			actor.spawn_remaining = 0
			actor.family.initialized = true
			world.combat.enemies.append(actor)
		world.queue_redraw()
		return
	if args.has("dungeon") or args.has("cellar") or args.has("level9"):
		world.state.max_health = 16
		world.state.health = 16
		world.state.slots[&"keys"] = 2
		world.state.flags["map/1"] = true
		world.state.flags["compass/1"] = true
		world.state.flags["door/l1_73/up"] = args.has("opened")
		if args.has("cellar"):
			world.enter_room(world.rooms[&"l1_c7f"], Vector2i(48, 1), Vector2i.DOWN, 28)
		elif args.has("level9"):
			world.enter_room(world.rooms[&"l9_76"], Vector2i(120, 157), Vector2i.UP, 16)
		else:
			world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 157), Vector2i.UP, 16)
		for tick in range(60): world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("boss"):
		var id := &"l1_35"
		for arg in args:
			if arg.begins_with("room="): id = StringName(arg.substr(5))
		world.state.max_health = 16
		world.state.health = 16
		world.enter_room(world.rooms[id], Vector2i(32, 77), Vector2i.RIGHT)
		for tick in range(150):
			world.combat.player_invulnerability = 100000
			world.simulate_tick(Vector2i.ZERO)
		world.combat.player_invulnerability = 0
		world.queue_redraw()
		return
	if args.has("shop"):
		world.state.rupees = 87
		for item in ["bombs", "blue_candle", "white_sword"]: world.state.take_item(load("res://content/items/" + item + ".tres"))
		world.enter_room(world.rooms[&"cave_25"], Vector2i(120, 109), Vector2i.UP)
		for tick in range(400): world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("bomb") or args.has("burned"):
		world.state.take_item(load("res://content/items/bombs.tres"))
		world.state.take_item(load("res://content/items/blue_candle.tres"))
		var id: StringName = &"ow_0d" if args.has("bomb") else &"ow_28"
		world.enter_room(world.rooms[id], Vector2i(144, 29) if args.has("bomb") else Vector2i(176, 93), Vector2i.UP)
		world.player.facing = Vector2i.UP if args.has("bomb") else Vector2i.RIGHT
		world.state.selected_item = &"bombs" if args.has("bomb") else &"candle"
		world.use_item()
		for tick in range(56 if args.has("bomb") else 100): world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	world.enter_room(world.rooms[&"cave_77"], Vector2i(112, 109), Vector2i.UP)
	for tick in range(400): world.simulate_tick(Vector2i.ZERO)
	if args.has("lift") or args.has("sword"):
		world.player.place(Vector2i(120, 85))
		world.simulate_tick(Vector2i.ZERO)
	if args.has("sword"):
		world.lift_remaining = 0
		world.simulation_tick = 100
		world.player.facing = Vector2i.RIGHT
		world.sword.start(world.state.equipped_weapon, Vector2i.RIGHT)
		for tick in range(5): world.sword.tick()
	world.queue_redraw()
