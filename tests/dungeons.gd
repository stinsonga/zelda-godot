extends SceneTree
## Dungeon foundations: entrances, doors, cellars, items, and level exits.
## Needs a local ROM import; reports a skip without one.
var failures := 0
const Main = preload("res://scenes/main.tscn")
const Saves = preload("res://scripts/save_store.gd")
const ItemObject = preload("res://scripts/item_object.gd")

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Dungeon suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func ticks(world: Node, count: int, direction: Vector2i = Vector2i.ZERO) -> void:
	for i in range(count): world.simulate_tick(direction)

func walk_until(world: Node, direction: Vector2i, room: StringName, limit: int = 200) -> void:
	for i in range(limit):
		world.simulate_tick(direction)
		if world.room.id == room: return

func door(world: Node, id: StringName, kind: String) -> Resource:
	for candidate in world.rooms[id].doors:
		if candidate.kind == kind: return candidate
	return null

func run() -> void:
	if not ResourceLoader.exists("res://imported/world.tres"):
		print("Dungeon checks: SKIPPED (no local ROM import)")
		quit(0)
		return
	var temporary := "user://dungeon_tests_%d" % Time.get_ticks_usec()
	var world = Main.instantiate()
	world.scroll_transitions = false
	world.save_store = Saves.new(temporary)
	root.add_child(world)
	world.set_physics_process(false)
	check_structure(world)
	check_entrance_and_exit(world)
	check_doors(world)
	check_cellar(world)
	check_items(world)
	check_blocks_and_shutters(world)
	check_save(world)
	world.free()
	for name in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary.path_join(name))
	DirAccess.remove_absolute(temporary)
	print("Dungeon checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_structure(world: Node) -> void:
	var counts := {}
	var exits := 0
	for id in world.rooms:
		var definition: Resource = world.rooms[id]
		if definition.dungeon_level == 0: continue
		counts[definition.dungeon_level] = counts.get(definition.dungeon_level, 0) + 1
		check(definition.validation_errors().is_empty(), "Invalid level room " + String(id))
		for edge in definition.exits:
			var target: Resource = world.rooms[StringName(definition.exits[edge])]
			check(target.dungeon_level == definition.dungeon_level, "Level rooms must connect within their level: " + String(id))
		for portal in definition.portals:
			if world.rooms[portal.target_room].dungeon_level == 0: exits += 1
	check(counts.keys().size() == 9, "All nine first-quest levels must import")
	check(counts[1] == 18 and counts[9] == 65, "Level 1 must have 17 rooms and its cellar; level 9 its 57 rooms and 8 cellars")
	check(exits == 9, "Each level start room must lead back outdoors")
	check(world.rooms[&"l1_73"].exits == {"up": "l1_63", "left": "l1_72", "right": "l1_74"}, "Level 1 entrance room must open three ways")

func check_entrance_and_exit(world: Node) -> void:
	world.enter_room(world.rooms[&"ow_37"], Vector2i(112, 77), Vector2i.UP)
	walk_until(world, Vector2i.UP, &"l1_73", 40)
	check(world.room.id == &"l1_73" and world.state.current_level == 1 and world.audio.current_music == &"dungeon", "Level 1's overworld entrance must lead into its start room")
	ticks(world, 12)
	check(world.player.pixel_position() == Vector2i(120, 141), "Link must walk 16 pixels into the level")
	walk_until(world, Vector2i.DOWN, &"ow_37", 40)
	check(world.room.id == &"ow_37" and world.state.current_level == 0, "The start room's south doorway must lead outdoors")
	ticks(world, 64)
	check(world.player.pixel_position() == Vector2i(112, 61), "Leaving a level must rise into its entrance")

func check_doors(world: Node) -> void:
	world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 77), Vector2i.UP)
	ticks(world, 60, Vector2i.UP)
	check(world.room.id == &"l1_73" and world.player.pixel_position().y > 0, "A locked door must stop Link without a key")
	world.state.slots[&"keys"] = 1
	world.simulate_tick(Vector2i.UP)
	check(world.state.item_value(&"keys") == 0 and world.state.flags.get("door/l1_73/up", false) and world.state.flags.get("door/l1_63/down", false), "A key must open both sides of a locked door")
	walk_until(world, Vector2i.UP, &"l1_63", 40)
	check(world.room.id == &"l1_63", "An opened door must lead to the next room")
	world.enter_room(world.rooms[&"l1_73"], Vector2i(32, 77), Vector2i.LEFT)
	walk_until(world, Vector2i.LEFT, &"l1_72", 100)
	check(world.room.id == &"l1_72", "Open doorways must lead to neighboring rooms")
	world.state.slots[&"magic_key"] = 1
	world.enter_room(world.rooms[&"l1_35"], Vector2i(120, 77), Vector2i.UP)
	var locked: Resource = door(world, &"l1_35", "key")
	if locked != null:
		world.player.place(locked.bomb_hotspot() if locked.direction.y == 0 else Vector2i(120, 29 if locked.direction == Vector2i.UP else 125))
		world.try_doors(locked.direction)
		check(world.door_passable(world.room, locked), "The magical key must open locked doors without being spent")
	world.state.slots[&"magic_key"] = 0
	var bombable: Resource = door(world, &"l1_43", "bombable")
	world.enter_room(world.rooms[&"l1_43"], Vector2i(120, 77), Vector2i.UP)
	check(not world.door_passable(world.room, bombable), "Bombable walls start closed")
	var bomb = ItemObject.bomb(bombable.bomb_hotspot(), bombable.direction)
	world.item_objects.append(bomb)
	ticks(world, 50)
	check(world.door_passable(world.room, bombable), "A bomb blast must open a bombable wall")

func check_cellar(world: Node) -> void:
	world.enter_room(world.rooms[&"l1_22"], Vector2i(128, 93), Vector2i.UP)
	walk_until(world, Vector2i.UP, &"l1_c7f", 20)
	check(world.room.id == &"l1_c7f", "Stairs must lead into the level's cellar")
	ticks(world, 20)
	check(world.player.pixel_position() == Vector2i(48, 29), "Link must climb 28 pixels down the cellar ladder")
	var bow: Resource = world.room.pickups[0]
	world.player.place(bow.position)
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.item_value(&"bow") == 1 and world.lift_remaining == 128, "Cellar treasure must be lifted")
	world.lift_remaining = 0
	world.player.place(Vector2i(48, 29))
	walk_until(world, Vector2i.UP, &"l1_22", 40)
	check(world.room.id == &"l1_22" and world.player.pixel_position() == Vector2i(96, 109), "Climbing out must return to the cellar's attribute C position")

func check_items(world: Node) -> void:
	world.enter_room(world.rooms[&"l1_43"], Vector2i(120, 141), Vector2i.UP)
	world.player.place(world.room.pickups[0].position)
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.has_level_item(&"map", 1) and world.lift_remaining == 0, "Rooms give their item without lifting")
	world.enter_room(world.rooms[&"l1_36"], Vector2i(120, 141), Vector2i.UP)
	world.state.health = 2
	world.player.place(world.room.pickups[0].position)
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.has_level_item(&"triforce", 1) and world.state.health == world.state.max_health, "The triforce must be taken and refill health")
	ticks(world, 200)
	check(world.room.id == &"ow_37", "Taking the triforce must return Link to the level entrance")

func check_blocks_and_shutters(world: Node) -> void:
	world.enter_room(world.rooms[&"l1_42"], Vector2i(112, 93), Vector2i.UP)
	var shutter: Resource = door(world, &"l1_42", "shutter")
	check(not world.door_passable(world.room, shutter), "A push-block shutter starts closed")
	ticks(world, 15, Vector2i.UP)
	check(not world.secrets.pushed, "Blocks need 16 ticks of pushing")
	ticks(world, 2, Vector2i.UP)
	check(world.secrets.pushed, "Pushing a block for 16 ticks must move it")
	ticks(world, 40)
	check(world.secrets.revealed and world.door_passable(world.room, shutter), "A pushed block must open the room's shutters")

func check_save(world: Node) -> void:
	world.enter_room(world.rooms[&"l1_63"], world.rooms[&"l1_63"].spawn, Vector2i.UP)
	check(world.save_game(), "Saving inside a level must work: " + world.status_message)
	world.state.flags.clear()
	var loaded: bool = world.load_game()
	check(loaded and world.room.id == &"l1_63" and world.state.flags.get("door/l1_63/down", false), "Opened doors and the level must survive a save: " + world.status_message + " " + String(world.room.id))
