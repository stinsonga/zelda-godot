extends SceneTree

const Main = preload("res://scenes/main.tscn")
const Lab = preload("res://scenes/combat_lab.tscn")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
var temporary: String

func _initialize() -> void:
	temporary = OS.get_temp_dir().path_join("zelda-save-check-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	create_timer(10).timeout.connect(func() -> void: push_error("Save suite did not complete"); quit(1))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func make_world(original: bool = false) -> Node:
	var world = Main.instantiate() if original else Lab.instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.save_store = Store.new(temporary)
	return world

func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(text)
	file.close()

func run() -> void:
	var world := make_world()
	var initial: RefCounted = world.state
	check(not world.load_game() and world.state == initial, "Missing save must leave the current session untouched")
	world.state.collect(world.room.id, world.room.pickups[0])
	world.state.health = 5
	world.state.rupees = 42
	world.state.kill_cycle = 7
	world.state.flags["quest/test_gate"] = true
	world.state.defeated["combat_lab/red"] = true
	world.player.place(Vector2i(120, 133))
	world.player.subposition.x += 128
	world.player.facing = Vector2i.LEFT
	var first: Dictionary = world.snapshot()
	check(world.save_game(), "First save must create a valid snapshot")
	var path: String = world.save_store.path_for(world.world_id)
	var text := FileAccess.get_file_as_string(path)
	check(not text.contains("res://") and not text.contains(".nes"), "Save must contain stable IDs rather than resource paths or ROM data")
	world.state.health = 4
	world.state.rupees = 17
	check(world.save_game(), "Saving over an existing slot must replace it successfully")
	check(FileAccess.file_exists(path + ".bak"), "Replacing a save must retain the previous valid snapshot")
	world.free()
	world = make_world()
	check(world.state.equipped_weapon == null and world.state.rupees == 0, "Fresh game must start independently of a save until loaded")
	check(world.load_game(), "A new world instance must load the saved session")
	check(world.state.health == 4 and world.state.rupees == 17 and world.state.kill_cycle == 7, "Health, currency, and kill cycle must round trip")
	check(world.state.equipped_weapon.id == &"wooden_sword" and world.state.flags.has("quest/test_gate"), "Equipped item and progression flags must round trip")
	check(world.state.has_collected(&"combat_lab", &"lab_sword") and world.combat.enemies.size() == 1, "Collected items and defeated enemies must remain absent after load")
	check(world.player.subposition == Vector2i(120 * 256 + 128, 133 * 256) and world.player.facing == Vector2i.LEFT, "Position fractions and facing must round trip")
	check(world.combat.player_invulnerability == 48, "Loaded player must receive a short arrival grace period")
	write_text(path, "{ damaged")
	check(world.load_game() and world.state.rupees == 42 and world.status_message == "BACKUP SAVE LOADED", "Damaged primary save must recover the previous valid backup")
	DirAccess.remove_absolute(path + ".bak")
	write_text(path, "{ damaged")
	initial = world.state
	var before: Vector2i = world.player.subposition
	check(not world.load_game() and world.state == initial and world.player.subposition == before, "Invalid JSON without backup must not partially replace the live game")
	var bad := first.duplicate(true)
	bad.version = 99
	write_text(path, JSON.stringify(bad))
	check(not world.load_game() and world.state == initial, "Future save versions must be rejected without changing state")
	bad = first.duplicate(true)
	bad.health = 3.5
	check(not world.save_store.write_snapshot(bad, world.world_id).ok, "Fractional or out-of-range health must be rejected before writing")
	bad = first.duplicate(true)
	bad.facing = [1, 1]
	check(not world.save_store.write_snapshot(bad, world.world_id).ok, "Diagonal saved facing must be rejected")
	bad = first.duplicate(true)
	bad.inventory = ["unavailable_sword"]
	bad.equipped = "unavailable_sword"
	write_text(path, JSON.stringify(bad))
	check(not world.load_game() and world.state == initial, "Unavailable item IDs must not become arbitrary resource loads")
	bad = first.duplicate(true)
	bad.room_id = "removed_room"
	write_text(path, JSON.stringify(bad))
	check(not world.load_game() and world.state == initial, "Unavailable room must fail without modifying the live session")
	bad = first.duplicate(true)
	bad.world_id = "another_world"
	write_text(path, JSON.stringify(bad))
	check(not world.load_game() and world.state == initial, "Saves from another world must be rejected")
	check(world.save_store.path_for("world/a") != world.save_store.path_for("world_a"), "World filenames must avoid sanitized-ID collisions")
	# Changed content can safely relocate a formerly valid player position.
	write_text(path, JSON.stringify(first))
	var changed: Resource = world.room.duplicate()
	var lines: PackedStringArray = changed.rows()
	lines[9] = "################"
	changed.tiles = "\n".join(lines)
	changed.spawn = Vector2i(80, 77)
	world.rooms[changed.id] = changed
	check(world.load_game() and world.player.pixel_position() == changed.spawn, "Edited terrain must relocate a blocked saved position to the room spawn")
	check(world.status_message == "LOADED AT ROOM ENTRANCE", "Relocation must be explained to the player")
	for i in range(11): lines[i] = "################"
	changed.tiles = "\n".join(lines)
	initial = world.state
	check(not world.load_game() and world.state == initial, "A room with no safe saved position or spawn must fail without state replacement")
	world.free()
	world = make_world()
	world.state.collect(world.room.id, world.room.pickups[0])
	check(world.save_game(), "A valid session must still be saveable after malformed-file tests")
	text = FileAccess.get_file_as_string(path)
	for busy in ["transition", "lift", "entry", "dead"]:
		match busy:
			"transition": world.transition = preload("res://scripts/room_transition.gd").new()
			"lift": world.lift_remaining = 1
			"entry": world.entry_walk_remaining = 1
			"dead": world.state.health = 0
		check(not world.save_game() and FileAccess.get_file_as_string(path) == text, "Unsettled player state must not overwrite a save: " + busy)
		world.transition = null
		world.lift_remaining = 0
		world.entry_walk_remaining = 0
		world.state.health = 6
	# A write failure must preserve the primary file; use a temp-path directory
	# instead of relying on machine-specific read-only file permissions.
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not world.save_game() and FileAccess.get_file_as_string(path) == text, "Failed temporary write must preserve the previous save")
	DirAccess.remove_absolute(path + ".tmp")
	world.combat.beam = preload("res://scripts/sword_beam.gd").new()
	world.attack_requested = true
	world.held.append(Vector2i.RIGHT)
	world.transition = preload("res://scripts/room_transition.gd").new()
	check(world.load_game() and world.transition == null and world.combat.beam == null and world.held.is_empty() and not world.attack_requested, "Loading must clear transient actions and pending input")
	world.state.rupees = 55
	var save_key := InputEventKey.new()
	save_key.physical_keycode = KEY_F5
	save_key.pressed = true
	world._input(save_key)
	check(world.status_message == "GAME SAVED", "F5 must call the save action and show confirmation")
	world.state.rupees = 0
	var load_key := InputEventKey.new()
	load_key.physical_keycode = KEY_F9
	load_key.pressed = true
	world._input(load_key)
	check(world.state.rupees == 55 and world.status_message == "GAME LOADED", "F9 must restore the slot and show confirmation")
	var oversized: Dictionary = world.snapshot()
	oversized.flags = []
	for i in range(5000): oversized.flags.append("%05d-" % i + "x".repeat(220))
	text = FileAccess.get_file_as_string(path)
	check(not world.save_store.write_snapshot(oversized, world.world_id).ok and FileAccess.get_file_as_string(path) == text, "A snapshot too large to load must be rejected before writing")
	# Custom content resolves through its configured stable item catalog.
	var custom: Resource = preload("res://content/items/wooden_sword.tres").duplicate()
	custom.id = &"custom_sword"
	world.register_item(custom)
	world.state.inventory[custom.id] = custom
	world.state.equipped_weapon = custom
	check(world.save_game(), "Custom items must save by ID")
	world.state.equipped_weapon = null
	check(world.load_game() and world.state.equipped_weapon == custom, "Custom saved items must resolve through the world catalog")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = make_world(true)
		check(world.world_id == "original_quest_1", "Imported world must have a stable explicit save identity")
		var cave: Resource = world.rooms[&"cave_77"]
		world.state.collected["cave_77/taken"] = true
		world.state.take_item(preload("res://content/items/wooden_sword.tres"))
		world.state.defeated["ow_78/slot_0"] = true
		world.state.rupees = 73
		world.state.health = 5
		var encounter: Resource = world.rooms[&"ow_78"]
		world.enter_room(encounter, encounter.spawn, Vector2i.DOWN)
		check(world.save_game(), "Original-world progression must be saveable")
		world.free()
		world = make_world(true)
		world.room_resources.reverse()
		check(world.load_game() and world.room.id == &"ow_78" and world.state.rupees == 73 and world.state.health == 5, "Original room and counters must survive a fresh instance and reordered content list")
		check(world.combat.enemies.size() == 3 and world.state.equipped_weapon.id == &"wooden_sword", "Original enemy and inventory state must survive reload")
		world.enter_room(cave, Vector2i(112, 109), Vector2i.UP)
		check(not world.dialogue_visible() and world.cave_session.phase == "gone", "Loaded sword gift must stay collected with no repeat dialogue")
		# Version 2 saves named the only cave sword_cave; the world maps old IDs.
		var legacy: Dictionary = world.snapshot()
		legacy.version = 2
		legacy.room_id = "sword_cave"
		legacy.collected = ["sword_cave/sword_gift"]
		legacy.erase("slots")
		legacy.erase("max_bombs")
		legacy.erase("selected_item")
		var legacy_file := FileAccess.open(world.save_store.path_for(world.world_id), FileAccess.WRITE)
		legacy_file.store_string(JSON.stringify(legacy))
		legacy_file.close()
		check(world.load_game() and world.room.id == &"cave_77" and world.state.has_collected(&"cave_77", &"taken") and world.state.item_value(&"sword") == 1, "Version 2 sword cave saves must load into the renamed cave")
		world.free()
	# Only delete files inside the unique temporary directory made by this test.
	for name in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary.path_join(name))
	DirAccess.remove_absolute(temporary)
	print("Save/load checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
