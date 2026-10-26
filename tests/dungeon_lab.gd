extends SceneTree
## The ROM-free dungeon lab (scenes/dungeon_lab.tscn): doors from direction and
## kind alone, a shutter room of editable monster presets, a false wall, a push
## block with stairs to a cellar, level items, and leaving the level. Needs no
## imported content.
const ItemObject = preload("res://scripts/item_object.gd")
const Door = preload("res://scripts/door_definition.gd")
var failures := 0
var world: Node

func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Dungeon lab suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

## Walk in one direction until the condition holds or the ticks run out.
func walk(direction: Vector2i, until: Callable, limit := 400) -> bool:
	for i in range(limit):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(direction)
		if until.call(): return true
	return false

func in_room(id: StringName) -> Callable:
	return func() -> bool: return world.room.id == id and world.transition == null and world.entry_walk_remaining == 0

func at_x(x: int) -> Callable:
	return func() -> bool: return world.player.pixel_position().x == x

func run() -> void:
	world = preload("res://scenes/dungeon_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.scroll_transitions = false
	check_doors()
	check_entry()
	check_hall()
	check_block_and_cellar()
	check_treasure_and_exit()
	check_editable_settings()
	check_key_doors()
	world.free()
	print("Dungeon lab checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_doors() -> void:
	for definition in world.room_resources:
		check(definition.validation_errors().is_empty(), "%s validates" % definition.id)
		check(definition.tile_atlas == null, "%s uses no atlas" % definition.id)
		for door in definition.doors:
			check(door.cells.is_empty() and door.door_cells().size() == Door.STANDARD_CELLS[door.direction].size(), "%s doors need only direction and kind" % definition.id)
	var bad: Resource = Door.new()
	bad.kind = "wall"
	bad.cells = PackedInt32Array([7])
	bad.open_tiles = PackedInt32Array([0])
	bad.open_collision = PackedInt32Array([0])
	check(not bad.validation_errors().is_empty(), "Wall doors cannot carry doorway cells")

func check_entry() -> void:
	check(world.room.id == &"lab_dungeon_gate", "The lab starts at the gate")
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_entry")), "The gate's entrance leads into the dungeon")
	check(world.state.current_level == 10 and world.player.pixel_position() == Vector2i(120, 141), "Link walks in from the south doorway")
	# The north key door blocks until Link brings a key.
	check(not walk(Vector2i.UP, in_room(&"lab_dungeon_hall"), 60), "The locked door holds without a key")
	world.player.place(Vector2i(48, 45))
	walk(Vector2i.ZERO, func() -> bool: return true, 1)
	check(world.state.item_value(&"keys") == 1, "Link picks up the key")
	world.player.place(Vector2i(120, 45))
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_hall")), "The key opens the north door")
	check(world.state.item_value(&"keys") == 0, "The key was spent")

func check_hall() -> void:
	var shutter: Resource = world.room.doors[0]
	check(shutter.kind == "shutter" and not world.door_passable(world.room, shutter), "The shutter closes while monsters live")
	var kinds: Array = world.combat.enemies.map(func(a: RefCounted) -> String: return a.definition.behavior)
	check(kinds == ["walker", "walker", "flyer", "gel"], "The hall holds the skeleton, bat, and slime presets")
	for i in range(80): walk(Vector2i.ZERO, func() -> bool: return false, 1)
	check(world.combat.enemies.all(func(a: RefCounted) -> bool: return a.alive()), "The presets spawn and move without imported content")
	for actor in world.combat.enemies:
		actor.invulnerability = 0
		actor.receive_hit(actor.health, Vector2i.UP, "sword")
		# As the sword path does: permanent rooms remember each defeat.
		world.combat.record_permanent_kill(world, actor)
	walk(Vector2i.ZERO, func() -> bool: return world.room_clear(), 60)
	check(world.door_passable(world.room, shutter), "Clearing the room opens the shutter")
	world.player.place(Vector2i(120, 77))
	walk(Vector2i.ZERO, func() -> bool: return true, 1)
	check(world.state.has_level_item(&"compass", 10), "The cleared room gives the compass")
	# The north side is a false wall: it looks solid but Link walks through.
	world.player.place(Vector2i(120, 45))
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_treasure")), "Link walks through the false wall")
	world.player.place(Vector2i(64, 77))
	walk(Vector2i.ZERO, func() -> bool: return true, 1)
	check(world.state.has_level_item(&"map", 10), "The treasure room has the map")
	world.player.place(Vector2i(120, 125))
	check(walk(Vector2i.DOWN, in_room(&"lab_dungeon_hall")), "Back through the false wall")
	world.player.place(Vector2i(120, 125))
	check(walk(Vector2i.DOWN, in_room(&"lab_dungeon_entry")), "The cleared hall stays clear and lets Link back south")

func check_block_and_cellar() -> void:
	var wall: Resource = world.room.doors[1]
	check(wall.kind == "bombable" and not world.door_passable(world.room, wall), "The east wall hides a bombable door")
	world.player.place(Vector2i(192, 45))
	walk(Vector2i.ZERO, func() -> bool: return true, 1)
	check(world.state.item_value(&"bombs") > 0, "Link picks up bombs")
	world.item_objects.append(ItemObject.bomb(wall.bomb_hotspot() - Vector2i(16, 0), Vector2i.RIGHT))
	walk(Vector2i.ZERO, func() -> bool: return world.door_passable(world.room, wall), 120)
	check(world.door_passable(world.room, wall) and world.state.flags.get("door/lab_dungeon_block/left", false), "A bomb opens it from both sides")
	world.player.place(Vector2i(192, 77))
	check(walk(Vector2i.RIGHT, in_room(&"lab_dungeon_block")), "Link walks into the block room")
	# Push the block right from its left side for 16 ticks.
	world.player.place(Vector2i(80, 77))
	walk(Vector2i.RIGHT, func() -> bool: return world.secrets.revealed, 80)
	check(world.secrets.revealed, "Pushing the block reveals the stairs")
	world.player.place(Vector2i(208, 45))
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_cellar")), "The stairs lead down into the cellar")
	check(world.player.pixel_position() == Vector2i(48, 29), "Link climbs down the ladder")
	walk(Vector2i.DOWN, func() -> bool: return world.player.pixel_position().y == 125)
	walk(Vector2i.RIGHT, func() -> bool: return world.state.item_value(&"bow") > 0)
	check(world.state.item_value(&"bow") > 0 and world.lift_remaining > 0, "The cellar's bow is lifted overhead")
	walk(Vector2i.ZERO, func() -> bool: return world.lift_remaining == 0)
	walk(Vector2i.LEFT, at_x(48))
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_block")), "The ladder climbs back to the block room")

func check_treasure_and_exit() -> void:
	var temporary := OS.get_temp_dir().path_join("zelda-dungeon-lab-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	world.save_store = preload("res://scripts/save_store.gd").new(temporary)
	check(world.save_game() and world.load_game(), "Saving and loading inside the lab works")
	check(world.room.id == &"lab_dungeon_block" and world.state.has_level_item(&"map", 10) and world.state.item_value(&"bow") > 0, "The checkpoint keeps the room and items")
	var path: String = world.save_store.path_for(world.world_id)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(temporary)
	world.enter_room(world.rooms[&"lab_dungeon_treasure"], Vector2i(120, 125), Vector2i.UP)
	world.player.place(Vector2i(120, 61))
	walk(Vector2i.ZERO, func() -> bool: return world.room.id == &"lab_dungeon_gate", 400)
	check(world.state.has_level_item(&"triforce", 10) and world.room.id == &"lab_dungeon_gate", "The triforce sends Link back out of the level")

## B-item, Rope, and monster-bound settings come from resources, not code.
func check_editable_settings() -> void:
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	var short: Resource = load("res://content/items/boomerang.tres").duplicate()
	short.use_range = 16
	short.use_speed = 2
	world.register_item(short)
	world.state.slots[&"boomerang"] = 1
	world.state.selected_item = &"boomerang"
	world.item_objects.clear()
	check(world.use_item() and world.item_objects.back().limit == 16 and world.item_objects.back().speed == 2, "Boomerang range and speed are item settings")
	for i in range(8): world.item_objects.back().tick()
	check(world.item_objects.back().returning, "The short boomerang turns back after 16 pixels")
	world.item_objects.clear()
	world.item_use_remaining = 0
	var quick: Resource = load("res://content/items/bombs.tres").duplicate()
	quick.use_fuse_ticks = PackedInt32Array([2, 2, 2, 2])
	world.item_catalog[&"bombs"] = quick
	world.state.slots[&"bombs"] = 4
	world.state.selected_item = &"bombs"
	check(world.use_item(), "A bomb is set")
	var bomb: RefCounted = world.item_objects.back()
	var ticks := 0
	while not bomb.detonating() and ticks < 100:
		bomb.tick()
		ticks += 1
	check(ticks <= 4, "Bomb fuse lengths are item settings (%d)" % ticks)
	world.item_objects.clear()
	var candle: Resource = load("res://content/items/red_candle.tres")
	check(not candle.use_once_per_room and load("res://content/items/blue_candle.tres").use_once_per_room, "Candle reuse is an item setting")
	check(load("res://content/items/silver_arrows.tres").use_damage == 4 and load("res://content/items/magical_boomerang.tres").use_range == 0xFF, "Graded items carry their own use settings")
	# A Rope variant that rushes slowly from farther away.
	var rope: Resource = preload("res://scripts/enemy_definition.gd").new()
	rope.id = &"lab_rope"
	rope.behavior = "rope"
	rope.speed_subpixels = 128
	rope.rope_rush_speed = 192
	rope.rope_line_up = 40
	rope.spawn_cloud = false
	rope.shooting_enabled = false
	check(rope.validation_errors().is_empty(), "The Rope variant validates")
	var room: Resource = world.rooms[&"lab_dungeon_block"].duplicate()
	room.id = &"rope_fixture"
	room.secret = null
	room.portals = Array([], TYPE_OBJECT, "Resource", null)
	room.monster_bounds = Rect2i(48, 45, 144, 64)
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"rope"
	spawn.enemy = rope
	spawn.position = Vector2i(96, 77)
	room.enemies.assign([spawn])
	world.rooms[room.id] = room
	world.enter_room(room, Vector2i(64, 109), Vector2i.UP)
	check(world.combat.bounds == Rect2i(48, 45, 144, 64), "Rooms can set their own monster bounds")
	var actor: RefCounted = world.combat.enemies[0]
	var rushed := false
	for i in range(120):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)
		if actor.family.rope_speed == 192: rushed = true
	check(rushed, "Rope rush speed and line-up distance are definition settings")

## Z_05 TouchDoorKey and UpdateDoors: one key per door, none with the magical
## key, a short opening that holds Link, and flags that outlive the visit.
func check_key_doors() -> void:
	var temporary := OS.get_temp_dir().path_join("zelda-key-doors-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	world.save_store = preload("res://scripts/save_store.gd").new(temporary)
	for key in world.state.flags.keys():
		if String(key).begins_with("door/"): world.state.flags.erase(key)
	world.state.slots[&"magic_key"] = 0
	world.state.slots[&"keys"] = 0
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 45), Vector2i.UP)
	var door: Resource = world.room.doors[0]
	check(not walk(Vector2i.UP, in_room(&"lab_dungeon_hall"), 40) and world.state.item_value(&"keys") == 0, "Without a key the door holds")
	world.state.slots[&"keys"] = 2
	world.player.place(Vector2i(120, 45))
	var held := 0
	for i in range(world.DOOR_OPEN_TICKS + 30):
		world.simulate_tick(Vector2i.UP)
		if world.room.id != &"lab_dungeon_entry": break
		if i < world.DOOR_OPEN_TICKS - 1 and not world.door_passable(world.room, door): held += 1
	check(world.state.item_value(&"keys") == 1, "Pressing on during the opening spends only one key")
	check(held >= world.DOOR_OPEN_TICKS - 2, "The opening door holds Link briefly (%d)" % held)
	check(world.room.id == &"lab_dungeon_hall", "Then Link walks through")
	check(world.door_passable(world.room, world.room.doors[0]) or world.state.flags.get("door/lab_dungeon_hall/down", false), "The far side is marked open too")
	walk(Vector2i.ZERO, func() -> bool: return world.transition == null and world.entry_walk_remaining == 0 and world.state.rupees_settled(), 80)
	var saved: bool = world.save_game()
	var loaded: bool = world.load_game()
	check(saved and loaded, "A checkpoint after opening loads")
	check(world.state.flags.get("door/lab_dungeon_entry/up", false) and world.state.item_value(&"keys") == 1, "Opened doors and the key count survive loading")
	var path: String = world.save_store.path_for(world.world_id)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(temporary)
	# The magical key opens without spending, and the HUD shows XA.
	world.state.flags.erase("door/lab_dungeon_entry/up")
	world.state.flags.erase("door/lab_dungeon_hall/down")
	world.state.slots[&"magic_key"] = 1
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 45), Vector2i.UP)
	check(walk(Vector2i.UP, in_room(&"lab_dungeon_hall"), 80) and world.state.item_value(&"keys") == 1, "The magical key opens without spending a key")
	check(world.key_count_text() == "XA", "With the magical key the HUD shows XA")
	world.state.slots[&"magic_key"] = 0
	check(world.key_count_text() == "X1", "Otherwise it shows the count")
