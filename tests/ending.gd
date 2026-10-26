extends SceneTree
## The ending (Z_02 mode $13) from Zelda's rescue to the second quest. Needs a
## local import; skips without one.
var failures := 0
var world: Node
var choices: Array = []

func _initialize() -> void:
	create_timer(180).timeout.connect(func() -> void: push_error("Ending suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func tick(count := 1, start := false) -> void:
	for i in range(count): world.simulate_tick(Vector2i.ZERO, false, false, start and i == 0)

func run() -> void:
	if EndingSequence.load_data().is_empty() or not ResourceLoader.exists("res://imported/rooms/l9_32.tres"):
		print("Ending checks: SKIP (no local import)")
		quit(0)
		return
	for quest in [1, 2]: check_ending(quest)
	print("Ending checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

## Whether a run of tile codes appears in a nametable row.
func row_has(codes: Array) -> bool:
	for table in world.ending_screen.tables:
		for row in range(30):
			var line: Array = Array(table.slice(row * 32, row * 32 + 32))
			for column in range(32 - codes.size() + 1):
				if line.slice(column, column + codes.size()) == codes: return true
	return false

func text(value: String) -> Array:
	var codes: Array = []
	for character in value:
		var code := character.unicode_at(0)
		codes.append(code - 48 if code >= 48 and code <= 57 else code - 55 if code >= 65 and code <= 90 else {",": 0x28, "'": 0x2A, ".": 0x2C}.get(character, 0x24))
	return codes

func check_ending(quest: int) -> void:
	world = preload("res://scenes/main.tscn").instantiate()
	world.menus_enabled = true
	root.add_child(world)
	world.set_physics_process(false)
	world.menu_choice.connect(func(choice: String) -> void: choices.append(choice))
	var name := [0x15, 0x12, 0x17, 0x14, 0x24, 0x24, 0x24, 0x24]
	world.file_info = {"quest": quest, "name": name, "deaths": 7}
	world.enter_room(world.rooms[&"l9_32"], Vector2i(0x78, 0x95 - 64 + 16), Vector2i.UP)
	while world.curtain >= 0: tick()
	world.player.place(Vector2i(0x78, 0x95 - 64))
	var frames := 0
	while world.game_phase != "ending" and frames < 400:
		tick()
		frames += 1
	check(world.game_phase == "ending" and world.audio.current_music == &"zelda", "The rescue plays Zelda's song, then the ending begins")
	var ending: RefCounted = world.ending
	# The furl waits for the song, then takes 16 steps of 5 frames.
	frames = 0
	while ending.furled() == 0 and frames < 400:
		tick()
		frames += 1
	check(absi(frames - (int(ending.data.zelda_song_frames) - 0x80)) <= 1, "The furl starts when the fanfare ends (%d)" % frames)
	frames = 0
	while not ending.on_screen() and frames < 200:
		tick()
		frames += 1
	check(frames == 75 and ending.furled() == 16, "Sixteen columns a side, five frames apart (%d)" % frames)
	while not ending.updating: tick()
	check(row_has(text("THANKS LINK,YOU'RE")) and row_has(text("THE HERO OF HYRULE.")), "Zelda's thanks are typed out")
	# The flash: from $40 the backdrop cycles EndingFlashColors.
	var backdrops := {}
	for i in range(0xC0):
		tick()
		if ending.submode == 0: backdrops[world.ending_screen.palette[0]] = true
	check(backdrops.size() == 4 and ending.submode == 1 and world.audio.current_music == &"ending", "The backdrop flashes, then the ending song starts")
	while ending.submode in [1, 2]: tick()
	check(row_has(text("FINALLY,")) and row_has(text("PEACE RETURNS TO HYRULE.")) and row_has(text("THIS ENDS THE STORY.")), "The peace text is typed out")
	frames = 0
	while ending.submode == 3 and frames < 3000:
		tick()
		frames += 1
	var lines: int = (int(ending.data.last_screens[quest - 1]) * 240 + int(ending.data.last_scrolls[quest - 1]))
	check(absi(frames - lines * 2) <= 2, "The credits scroll half a line a frame (%d for %d lines)" % [frames, lines])
	check(ending.status_bar_overwritten, "The credits overwrite the status bar's rows")
	if quest == 1:
		check(row_has(text("ANOTHER QUEST WILL START")) and not row_has(text("YOU ARE GREAT")), "The first quest invites another")
	else:
		check(row_has(text("YOU ARE GREAT")) and row_has(name) and not row_has(text("ANOTHER QUEST WILL START")), "The second quest names the hero")
	tick(1, true)
	check(world.game_phase == "ending", "Start waits $40 frames")
	tick(0x40)
	tick(1, true)
	check(world.game_phase == "play" and choices.back() == "second_quest" and world.state.max_health == 6 and world.state.item_value(&"bombs") == 0, "Start moves the file on to the second quest")
	world.free()
