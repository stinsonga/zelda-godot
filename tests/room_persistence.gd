extends SceneTree

const Main = preload("res://scenes/main.tscn")
var failures := 0
var temporary: String

func _initialize() -> void:
	temporary = OS.get_temp_dir().path_join("zelda-room-check-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	create_timer(10).timeout.connect(func() -> void: push_error("Room persistence suite did not finish"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func make_world(count: int = 4, policy: String = "overworld") -> Node:
	var definitions: Array[Resource] = []
	var tiles := PackedStringArray()
	for y in range(11): tiles.append("................")
	for letter in "abcdefgh":
		var room = preload("res://scripts/room_definition.gd").new()
		room.id = StringName("room_" + letter)
		room.tiles = "\n".join(tiles)
		room.spawn = Vector2i(120, 125)
		room.grid_origin = Vector2i(0, 5)
		room.enemy_persistence = policy
		if letter == "a":
			for i in range(count):
				var spawn = preload("res://scripts/enemy_spawn.gd").new()
				spawn.id = StringName("enemy_%d" % i)
				spawn.enemy = preload("res://content/enemies/blue_octorok.tres").duplicate()
				spawn.enemy.speed_subpixels = 0
				spawn.enemy.shoot_cooldown = 0
				spawn.enemy.spawn_ticks = 0
				spawn.position = Vector2i(32 + (i % 6) * 32, 29 + (i / 6) * 32)
				room.enemies.append(spawn)
		definitions.append(room)
	var cave = preload("res://scripts/room_definition.gd").new()
	cave.id = &"test_cave"
	cave.history_id = &"room_a"
	cave.tiles = "\n".join(tiles)
	cave.spawn = Vector2i(120, 125)
	cave.dialogue = "A GIFT"
	cave.dialogue_until_pickup = &"gift"
	var gift = preload("res://scripts/pickup_definition.gd").new()
	gift.id = &"gift"
	gift.item = preload("res://content/items/wooden_sword.tres")
	gift.position = Vector2i(120, 88)
	cave.pickups.append(gift)
	definitions.append(cave)
	var world = Main.instantiate()
	world.use_imported_world = false
	world.room_resources = definitions
	root.add_child(world)
	world.set_physics_process(false)
	world.save_store = preload("res://scripts/save_store.gd").new(temporary)
	return world

func go(world: Node, letter: String) -> void:
	var room: Resource = world.rooms[StringName("room_" + letter)]
	world.enter_room(room, room.spawn, Vector2i.UP)

func kill(world: Node, indices: Array) -> void:
	for index in indices:
		var actor = world.combat.enemies[index]
		actor.receive_hit(actor.health, Vector2i.RIGHT)
		world.combat.record_permanent_kill(world, actor)
	for tick in range(12): world.combat.tick(world)

func run() -> void:
	var world := make_world()
	check(world.state.room_history == ["room_a"] and world.state.history_cursor == 1, "First room must occupy one history slot")
	kill(world, [2])
	check(world.combat.encounter_kills == 1, "Completed death must count once")
	check(world.state.room_records["room_a"].kills == 0 and world.snapshot().room_records["room_a"].kills == 1, "Saving must include pending room kills without double-committing live state")
	go(world, "b")
	go(world, "a")
	check(world.combat.enemies.size() == 3, "Partial clear must reduce the population on an immediate revisit")
	check(world.combat.enemies[2].id == &"enemy_2", "Original overworld persistence must reduce the count rather than pin specific killed spawn IDs")
	check(world.state.defeated.is_empty(), "Overworld kills must not become permanent per-spawn defeats")
	world.combat.enemies[0].health = 1
	go(world, "b")
	go(world, "a")
	check(world.combat.enemies[0].health == 2, "Surviving enemies must regain health when the room is recreated")
	kill(world, [0, 1, 2])
	go(world, "b")
	check(world.state.room_records["room_a"].cleared, "Defeating the remaining population must mark the room fully cleared")
	go(world, "a")
	check(world.combat.enemies.is_empty(), "A recently cleared room must stay empty")
	for letter in "cdef": go(world, letter)
	check(world.state.room_history == ["room_a", "room_b", "room_c", "room_d", "room_e", "room_f"], "History must hold six distinct insertion slots")
	go(world, "a")
	check(world.state.history_cursor == 0, "Revisiting a remembered room must not refresh its history position")
	check(world.save_game(), "A cleared-room checkpoint must save the full ring and insertion cursor")
	go(world, "g")
	check("room_a" not in world.state.room_history and world.state.history_cursor == 1, "Seventh distinct room must evict the oldest insertion slot")
	go(world, "a")
	check(world.combat.enemies.size() == 4 and not world.state.room_records["room_a"].cleared, "A fully cleared room must repopulate after history eviction")
	check(world.load_game() and world.combat.enemies.is_empty() and world.state.history_cursor == 0 and world.state.room_history.size() == 6, "Loading must restore a full ring and cleared encounter without refreshing its cursor")
	go(world, "g")
	go(world, "a")
	check(world.combat.enemies.size() == 4, "Restored ring must evict the same room on the next new insertion")
	world.free()
	world = make_world()
	kill(world, [1])
	for letter in "bcdefg": go(world, letter)
	check("room_a" not in world.state.room_history, "Partial-clear fixture must leave the six-room history")
	go(world, "a")
	check(world.combat.enemies.size() == 3, "Partial kill count must survive history eviction")
	kill(world, [0, 1, 2])
	var before: Array = world.state.room_history.duplicate()
	var cursor: int = world.state.history_cursor
	var cave: Resource = world.rooms[&"test_cave"]
	world.enter_room(cave, cave.spawn, Vector2i.UP)
	check(world.state.room_history == before and world.state.history_cursor == cursor, "A cave sharing its parent's history ID must not consume or refresh a slot")
	world.state.collect(cave.id, cave.pickups[0])
	world.state.flags["secret/opened"] = true
	go(world, "a")
	check(world.combat.enemies.is_empty(), "Entering and leaving a cave must retain its parent's clear state")
	for letter in "bcdefgh": go(world, letter)
	go(world, "a")
	check(world.combat.enemies.size() == 4 and world.state.flags.has("secret/opened"), "Enemy repopulation must not erase permanent progression flags")
	world.enter_room(cave, cave.spawn, Vector2i.UP)
	check(world.state.equipped_weapon != null and not world.dialogue_visible() and not world.state.collect(cave.id, cave.pickups[0]), "Permanent cave gift and its dialogue suppression must survive history eviction")
	world.free()
	world = make_world()
	var pending = world.combat.enemies[0]
	pending.receive_hit(pending.health, Vector2i.RIGHT)
	for tick in range(11): world.combat.tick(world)
	go(world, "b")
	go(world, "a")
	check(world.combat.enemies.size() == 4, "Leaving before the death effect finishes must not record an overworld kill")
	var drop = preload("res://scripts/dropped_reward.gd").new()
	drop.definition = preload("res://content/items/heart.tres")
	world.combat.rewards.append(drop)
	world.combat.beam = preload("res://scripts/sword_beam.gd").new()
	world.combat.rocks.append(preload("res://scripts/rock_projectile.gd").new())
	go(world, "b")
	check(world.combat.rewards.is_empty() and world.combat.beam == null and world.combat.rocks.is_empty(), "Loose drops and projectiles must not survive leaving a room")
	world.free()
	world = make_world(4, "permanent")
	kill(world, [2])
	for letter in "bcdefgh": go(world, letter)
	go(world, "a")
	check(world.combat.enemies.size() == 3 and world.combat.enemies[2].id == &"enemy_3", "Permanent custom encounter must preserve exact enemy IDs after history eviction")
	world.free()
	world = make_world(4, "reset")
	kill(world, [0, 1, 2, 3])
	go(world, "b")
	go(world, "a")
	check(world.combat.enemies.size() == 4, "Reset-policy encounter must repopulate on every entry")
	world.free()
	world = make_world(9)
	kill(world, [0, 1, 2, 3, 4, 5, 6])
	go(world, "b")
	go(world, "a")
	check(world.combat.enemies.size() == 2 and not world.state.room_records["room_a"].cleared, "Expanded rooms must not confuse seven partial kills with the original all-cleared sentinel")
	world.free()
	# Version 2 checkpoints preserve both completed in-room kills and history.
	world = make_world()
	kill(world, [3])
	check(world.save_game(), "An in-room partial-clear checkpoint must save")
	var saved_history: Array = world.state.room_history.duplicate()
	kill(world, [0, 1])
	check(world.load_game() and world.combat.enemies.size() == 3, "Loading must replace unsaved kills without committing them over restored state")
	check(world.state.room_history == saved_history and world.state.room_records["room_a"].kills == 1, "History and partial counts must round trip without refreshing or double-counting")
	var checkpoint: Dictionary = world.snapshot()
	world.free()
	world = make_world()
	check(world.load_game() and world.combat.enemies.size() == 3, "Partial kill records must survive a fresh process-equivalent world instance")
	var path: String = world.save_store.path_for(world.world_id)
	# A v1 save has no history. Its known flat enemy IDs migrate once to counts.
	checkpoint.version = 1
	checkpoint.erase("room_history")
	checkpoint.erase("history_cursor")
	checkpoint.erase("room_records")
	checkpoint.defeated = ["room_a/enemy_0", "room_a/enemy_2"]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(checkpoint))
	file.close()
	check(world.load_game() and world.combat.enemies.size() == 2 and world.state.defeated.is_empty(), "Version 1 per-enemy flags must migrate to overworld counts")
	check(world.snapshot().version == 2 and world.state.room_history == ["room_a"], "Migrated saves must establish a current history entry and write version 2")
	checkpoint.defeated = ["room_a/enemy_0", "room_a/enemy_1", "room_a/enemy_2", "room_a/enemy_3"]
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(checkpoint))
	file.close()
	check(world.load_game() and world.combat.enemies.is_empty(), "A v1 checkpoint in its fully cleared current room must retain that clear on migration")
	var malformed: Dictionary = world.snapshot()
	malformed.room_history = ["room_a", "room_a"]
	check(not world.save_store.validate(malformed, world.world_id).ok, "Duplicate history entries must be rejected")
	malformed = world.snapshot()
	malformed.history_cursor = 5
	check(not world.save_store.validate(malformed, world.world_id).ok, "Partial history cursor must match its next insertion slot")
	malformed = world.snapshot()
	malformed.room_records["room_a"].kills = -1
	check(not world.save_store.validate(malformed, world.world_id).ok, "Negative kill counts must be rejected")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = Main.instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		check(world.rooms[&"ow_78"].enemy_persistence == "overworld" and world.rooms[&"sword_cave"].history_id == &"ow_77", "Original import must select count persistence and shared cave history")
		world.free()
	for name in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary.path_join(name))
	DirAccess.remove_absolute(temporary)
	print("Room persistence checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
