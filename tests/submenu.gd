extends SceneTree
## The pause submenu (Z_05 UpdateMenu, FindAndSelectOccupiedItemSlot,
## Submenu_WriteSheetMapRowTransferRecord). The lab scenes need no ROM; the
## imported checks run with a local import.
const Submenu = preload("res://scripts/submenu.gd")
var failures := 0
var world: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Submenu suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func tick(count := 1, direction := Vector2i.ZERO, start := false) -> void:
	for i in range(count): world.simulate_tick(direction, false, false, start and i == 0)

func give(items: Array) -> void:
	for item in items: world.state.take_item(load("res://content/items/%s.tres" % item))

func run() -> void:
	world = preload("res://scenes/item_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_opening(false)
	check_selection()
	world.free()
	world = preload("res://scenes/dungeon_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_opening(true)
	check_sheet_map()
	world.free()
	check_imported()
	print("Submenu checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_opening(underworld: bool) -> void:
	if underworld: world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	tick(5)
	var at: Vector2i = world.player.pixel_position()
	world.state.rupees_to_add = 10
	var rupees: int = world.state.rupees
	tick(1, Vector2i.ZERO, true)
	check(world.submenu.is_open() and world.submenu.offset == 0, "Start opens the submenu")
	var setup: int = Submenu.SETUP_FRAMES_UNDERWORLD if underworld else Submenu.SETUP_FRAMES_OVERWORLD
	var frames := 1
	while not world.submenu.active() and frames < 200:
		tick(1, Vector2i.LEFT)
		frames += 1
	# Setup frames, then 3 pixels a frame from 2 to 176.
	check(frames == 1 + setup + 58, "It takes the original %d frames to open (%d)" % [1 + setup + 58, frames])
	check(world.submenu.offset == Submenu.HEIGHT, "Open, it fills the top 176 lines")
	check(world.player.pixel_position() == at, "The game waits while it opens")
	check(world.state.rupees > rupees, "The rupee meter still counts")
	tick(1, Vector2i.ZERO, true)
	var closing := 1
	while world.submenu.is_open() and closing < 200:
		tick(1, Vector2i.ZERO, true)
		closing += 1
	# The Start press takes a frame, then 59 frames scroll it away.
	check(closing == 60, "It scrolls away in 59 frames after the press, ignoring Start meanwhile (%d)" % closing)
	tick(10, Vector2i.LEFT)
	check(world.player.pixel_position() != at, "Afterwards the game resumes")

func open_menu() -> void:
	tick(1, Vector2i.ZERO, true)
	while not world.submenu.active(): tick()

func close_menu() -> void:
	tick(1, Vector2i.ZERO, true)
	while world.submenu.is_open(): tick()

func check_selection() -> void:
	var state: RefCounted = world.state
	state.slots.clear()
	state.selected_item = &""
	open_menu()
	check(world.submenu.slot == 0 and state.selected_item == &"", "With no B items the cursor rests on slot 0")
	close_menu()
	give(["bombs", "arrows", "blue_candle", "letter"])
	state.selected_item = &"bombs"
	open_menu()
	var order: Array = []
	for i in range(5):
		tick(1, Vector2i.RIGHT)
		order.append(state.selected_item)
		tick(1)
	check(order == [&"candle", &"letter", &"bombs", &"candle", &"letter"], "Right skips arrows without the bow and the empty slots (%s)" % [order])
	give(["bow", "blue_potion"])
	tick(1, Vector2i.LEFT)
	tick(1)
	check(state.selected_item == &"candle", "Left steps back")
	tick(1, Vector2i.LEFT)
	check(state.selected_item == &"arrows", "Arrows join once the bow is owned")
	tick(10, Vector2i.LEFT)
	check(state.selected_item == &"arrows", "Holding a direction moves once")
	tick(1)
	tick(1, Vector2i.RIGHT)
	tick(1)
	tick(1, Vector2i.RIGHT)
	check(state.selected_item == &"potion", "Slot 7 shows the potion over the letter")
	tick(1, Vector2i.UP)
	check(state.selected_item == &"potion", "Up and down leave the selection alone")
	close_menu()
	# The selection drives the B button.
	state.selected_item = &"bombs"
	open_menu()
	close_menu()
	check(state.selected_item == &"bombs", "Closing keeps the chosen item")
	check(Submenu.find_occupied(state, 3, 0) == 0, "An empty current slot falls back to slot 0")

func check_sheet_map() -> void:
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	check(world.state.flags.get("visited/lab_dungeon_entry", false), "Entering a dungeon room marks it visited")
	var entry: Resource = world.rooms[&"lab_dungeon_entry"]
	world.state.flags.erase("door/lab_dungeon_entry/up")
	world.state.flags.erase("door/lab_dungeon_entry/right")
	check(world.doorway_mask(entry) == 0b0100, "Only the open south doorway counts while the others are shut")
	world.state.flags["door/lab_dungeon_entry/up"] = true
	check(world.doorway_mask(entry) == 0b1100, "An opened key door counts")
	check(world.doorway_mask(world.rooms[&"lab_dungeon_treasure"]) == 0, "False walls never count")

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/submenu.tres"): return
	world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var layout: Resource = world.submenu_layout
	check(layout != null and layout.triforce_positions.size() == 24 and layout.map_rotations.size() == 9, "The imported layout holds 24 Triforce slots and nine maps")
	for level in range(1, 9): world.state.flags.erase("triforce/%d" % level)
	var empty: Dictionary = world.submenu_triforce_tiles()
	world.state.flags["triforce/5"] = true
	var one: Dictionary = world.submenu_triforce_tiles()
	world.state.flags["triforce/6"] = true
	var two: Dictionary = world.submenu_triforce_tiles()
	# Slot 12 (level 5) half fills a tile that slot 15 (level 6) then fills.
	var shared: Vector2 = layout.triforce_positions[12]
	check(layout.triforce_positions[15] == shared, "Levels 5 and 6 share a tile")
	check(one[shared] == 0xE5 and two[shared] == 0xF5, "One piece half fills it; both fill it ($%X, $%X)" % [one[shared], two[shared]])
	check(empty.values().all(func(t: int) -> bool: return t in [0x24, 0xE9, 0xEA]), "No pieces leave the Triforce empty")
	check(world.visual_theme.sprites.has(&"submenu_ow") and world.visual_theme.sprites.has(&"submenu_l9_tiles"), "Backdrops and tile atlases are imported")
	world.free()
