extends SceneTree
## The front end (Z_02 modes 1, $E, $F; Z_05 modes 8 and $11) with temporary
## save files. Runs without imported content.
var failures := 0
var front: Node
var temporary := ""

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Front end suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func menu(count := 1, direction := Vector2i.ZERO, start := false, select := false, a := false, b := false) -> void:
	for i in range(count): front.tick(direction, start and i == 0, select and i == 0, a and i == 0, b and i == 0)

func play_ticks(count := 1, start := false, select := false) -> void:
	for i in range(count): front.world.simulate_tick(Vector2i.ZERO, false, false, start and i == 0, select and i == 0)

func run() -> void:
	temporary = OS.get_temp_dir().path_join("zelda-front-end-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	front = preload("res://scenes/front_end.tscn").instantiate()
	front.files_directory = temporary
	root.add_child(front)
	front.set_physics_process(false)
	check_registration()
	check_play_and_death()
	check_elimination()
	front.free()
	cleanup()
	print("Front end checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func cleanup() -> void:
	var base := ProjectSettings.globalize_path(temporary)
	for folder in DirAccess.get_directories_at(base):
		for file in DirAccess.get_files_at(base.path_join(folder)): DirAccess.remove_absolute(base.path_join(folder).path_join(file))
		DirAccess.remove_absolute(base.path_join(folder))
	for file in DirAccess.get_files_at(base): DirAccess.remove_absolute(base.path_join(file))
	DirAccess.remove_absolute(base)

func check_registration() -> void:
	check(front.mode == "files" and front.cursor == 3, "With no files the cursor starts on REGISTER")
	check(not front.world.visible, "The world waits behind the menus")
	menu(1, Vector2i.ZERO, true)
	check(front.mode == "register" and front.cursor == 0, "Registration starts at the first free file")
	# A writes the highlighted character and moves the name cursor on.
	menu(1, Vector2i.ZERO, false, false, true)
	menu(1, Vector2i.RIGHT)
	menu(1, Vector2i.ZERO, false, false, true)
	check(front.names[0].slice(0, 2) == [0x0A, 0x0B] and front.name_cursor == 2, "A and B typed into the first name")
	# Held directions repeat after $10 frames, then every 8.
	var start: int = front.board
	menu(1, Vector2i.RIGHT)
	var first: int = front.board
	menu(16, Vector2i.RIGHT)
	var held: int = front.board
	menu(1, Vector2i.RIGHT)
	check(first == start + 1 and held == first and front.board == first + 1, "Holding a direction repeats after a pause")
	menu(1)
	menu(1, Vector2i.ZERO, false, false, false, true)
	check(front.name_cursor == 3, "B moves the name cursor without writing")
	# The second file is named ZELDA: the second quest.
	menu(1, Vector2i.ZERO, false, true)
	check(front.cursor == 1 and front.name_cursor == 0, "Select moves to the next free file")
	for code in [0x23, 0x0E, 0x15, 0x0D, 0x0A]:
		front.board = front.CHAR_MAP.find(code)
		menu(1, Vector2i.ZERO, false, false, true)
	menu(1, Vector2i.ZERO, false, true)
	menu(1, Vector2i.ZERO, false, true)
	check(front.cursor == 3, "Then to END")
	menu(1, Vector2i.ZERO, true)
	check(front.mode == "files" and front.files.active(0) and front.files.active(1) and not front.files.active(2), "END registers the named files")
	check(front.files.meta[0].quest == 1 and front.files.meta[1].quest == 2 and front.files.meta[0].max_health == 6, "ZELDA starts the second quest; new files have three hearts")
	check(front.cursor == 0, "Back on the menu, the first file is selected")
	menu(1, Vector2i.ZERO, false, true)
	check(front.cursor == 1, "Select moves between files in use")
	menu(1, Vector2i.ZERO, false, true)
	check(front.cursor == 3, "Skipping the empty one")

func check_play_and_death() -> void:
	front.cursor = 0
	menu(1, Vector2i.ZERO, true)
	var world: Node = front.world
	check(front.mode == "playing" and world.visible and world.room == world.start_room and world.state.health == 6, "A file starts at the overworld start with three hearts")
	world.state.take_item(load("res://content/items/bombs.tres"))
	world.state.max_health = 10
	# Death: the sequence, then Continue/Save/Retry and a death on the file.
	world.state.health = 0
	var frames := 0
	while world.game_phase != "continue" and frames < 1000:
		play_ticks()
		frames += 1
	check(world.game_phase == "continue", "Death leads to Continue/Save/Retry")
	check(frames >= 0x21 + 80 + 40 + 0x17 + 0x0F + 0x2D + 0x5F and frames < 0x21 + 80 + 40 + 0x17 + 0x0F + 0x2D + 0x5F + 10, "The death sequence takes the original time (%d)" % frames)
	check(front.files.meta[0].deaths == 1, "The file counts the death")
	# Select SAVE, then Start: the choice flashes $40 frames.
	play_ticks(1, false, true)
	check(world.continue_choice == 1, "Select steps to SAVE")
	play_ticks(1, true)
	play_ticks(0x3F)
	check(world.game_phase == "continue", "The choice flashes for $40 frames")
	play_ticks(1)
	check(front.mode == "files" and front.files.read_state(0, world.world_id).has("slots"), "SAVE writes the file and returns to the menu")
	check(front.files.meta[0].health == 6 and front.files.meta[0].max_health == 10, "It is saved with three full hearts")
	# Loading keeps the items; RETRY drops what happened since.
	front.cursor = 0
	menu(1, Vector2i.ZERO, true)
	check(world.state.item_value(&"bombs") == 4 and world.state.max_health == 10, "The saved file keeps its items")
	world.state.take_item(load("res://content/items/bombs.tres"))
	world.open_continue_menu()
	play_ticks(1, false, true)
	play_ticks(1, false, true)
	play_ticks(1, true)
	play_ticks(0x40)
	check(front.mode == "files", "RETRY returns to the menu")
	front.cursor = 0
	menu(1, Vector2i.ZERO, true)
	check(world.state.item_value(&"bombs") == 4, "without saving")
	# CONTINUE resumes play at the start with three hearts.
	world.state.health = 2
	world.open_continue_menu()
	play_ticks(1, true)
	play_ticks(0x40)
	check(world.game_phase == "play" and world.state.health == 6 and world.room == world.start_room, "CONTINUE resumes at the start with three hearts")
	front.show_files()

func check_elimination() -> void:
	front.cursor = 4
	menu(1, Vector2i.ZERO, true)
	check(front.mode == "eliminate" and front.cursor == 0, "ELIMINATION MODE opens on the first file")
	menu(1, Vector2i.ZERO, true)
	check(not front.files.active(0) and front.files.read_state(0, front.world.world_id).is_empty(), "Start erases the file and its saved game")
	menu(1, Vector2i.ZERO, false, true)
	menu(1, Vector2i.ZERO, false, true)
	menu(1, Vector2i.ZERO, false, true)
	menu(1, Vector2i.ZERO, true)
	check(front.mode == "register", "END moves on to registration")
	var reloaded = preload("res://scripts/save_files.gd").new(temporary)
	check(not reloaded.active(0) and reloaded.active(1) and reloaded.meta[1].quest == 2, "Files persist on disk")
