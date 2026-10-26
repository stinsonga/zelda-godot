extends SceneTree
## The second quest's foundation: a world per quest chosen by the file, the
## quest-wide monster rules (Z_04 InitRope/UpdateRope, UpdateStalfos), and the
## file menu. The variant mechanism runs without a ROM; the rest needs an import.
var failures := 0
var temporary := ""

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Second quest suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	check_variants()
	if ResourceLoader.exists("res://imported/world_q2.tres"):
		check_imported_worlds()
		check_overworld()
		check_front_end()
	print("Second quest checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

## A world's variants replace room monsters by ID when the room fills.
func check_variants() -> void:
	var lab = preload("res://scenes/dungeon_lab.tscn").instantiate()
	root.add_child(lab)
	lab.set_physics_process(false)
	var variant: Resource = load("res://content/enemies/lab_skeleton.tres").duplicate()
	variant.id = &"lab_skeleton_q2"
	variant.health = 9
	lab.combat.enemy_variants = {&"lab_skeleton": variant}
	lab.enter_room(lab.rooms[&"lab_dungeon_hall"], Vector2i(120, 77), Vector2i.UP)
	var skeletons: Array = lab.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_skeleton_q2")
	check(not skeletons.is_empty() and skeletons.all(func(a: RefCounted) -> bool: return a.health == 9), "Variants replace their monsters with their own health")
	check(lab.combat.enemies.all(func(a: RefCounted) -> bool: return a.definition.id != &"lab_skeleton"), "No original remains")
	lab.free()

func world_for(path: String) -> Node:
	var world = preload("res://scenes/main.tscn").instantiate()
	if path != "": world.world_definition = load(path)
	root.add_child(world)
	world.set_physics_process(false)
	return world

## The first dungeon room whose spawns include a monster.
func room_with(world: Node, id: StringName) -> Resource:
	var ids: Array = world.rooms.keys()
	ids.sort()
	for room_id in ids:
		var definition: Resource = world.rooms[room_id]
		if definition.dungeon_level > 0 and definition.enemies.any(func(spawn: Resource) -> bool: return spawn.enemy.id == id): return definition
	return null

func first(world: Node, id: StringName) -> RefCounted:
	for actor in world.combat.enemies:
		if actor.definition.id == id: return actor
	return null

func check_imported_worlds() -> void:
	var first_quest := world_for("")
	check(first_quest.quest == 1 and first_quest.world_id == "original_quest_1", "The imported world is the first quest")
	first_quest.enter_room(first_quest.rooms[&"l2_2e"], Vector2i(120, 77), Vector2i.UP)
	var rope: RefCounted = first(first_quest, &"rope")
	check(rope != null and rope.health == 1, "First-quest Ropes have $10 HP")
	first_quest.free()
	var second_quest := world_for("res://imported/world_q2.tres")
	check(second_quest.quest == 2 and second_quest.world_id == "original_quest_2", "The second quest is its own world, saved apart")
	second_quest.enter_room(room_with(second_quest, &"rope"), Vector2i(120, 77), Vector2i.UP)
	rope = first(second_quest, &"rope_q2")
	check(rope != null and rope.health == 4 and rope.definition.sprite_palette_cycle, "Second-quest Ropes have $40 HP and cycle palettes")
	check(second_quest.visual_theme.sprites.has(StringName("l%d_rope_down_0_p3" % second_quest.room.dungeon_level)), "Each palette has its sprites")
	second_quest.enter_room(room_with(second_quest, &"stalfos"), Vector2i(120, 77), Vector2i.UP)
	var stalfos: RefCounted = first(second_quest, &"stalfos_q2")
	check(stalfos != null and stalfos.definition.shooting_enabled and stalfos.definition.projectile_kind == "sword" and stalfos.definition.shooting_threshold == 0xF8,
		"Second-quest Stalfos throw swords when Random >= $F8")
	# Over a while, a Stalfos shoots.
	var shot := false
	for i in range(1200):
		second_quest.simulate_tick(Vector2i.ZERO)
		if second_quest.combat.rocks.any(func(r: RefCounted) -> bool: return r.kind == "sword"): shot = true
		if second_quest.state.health < 6: second_quest.state.health = 6
	check(shot, "and do throw them")
	second_quest.free()

func portal_to(definition: Resource, prefix: String) -> Resource:
	for portal in definition.portals:
		if String(portal.target_room).begins_with(prefix): return portal
	return null

## Z_06 UpdateMode2Load_Full's patches and Z_04 IsQuestSecretMismatch.
func check_overworld() -> void:
	var one := world_for("")
	var two := world_for("res://imported/world_q2.tres")
	# Level 2: an open entrance in the first quest, a recorder pond in the second.
	var first_two: Resource = one.rooms[&"ow_3c"]
	var second_two: Resource = two.rooms[&"ow_3c"]
	check(first_two.secret == null and portal_to(first_two, "l2_") != null and not portal_to(first_two, "l2_").requires_secret, "First quest: level 2 stands open")
	check(second_two.secret != null and second_two.secret.trigger == "recorder" and portal_to(second_two, "l2_").requires_secret, "Second quest: a recorder pond hides it")
	check(second_two.tile_indices != first_two.tile_indices, "and the room's layout is patched")
	# The first quest's pond is only water in the second, so the recorder summons the whirlwind.
	check(one.rooms[&"ow_42"].secret != null and two.rooms[&"ow_42"].secret == null, "Level 7's pond is first-quest only")
	# Level 5 under a rock; level 6's old two-square entrance is now a cave.
	check(two.rooms[&"ow_1b"].secret != null and two.rooms[&"ow_1b"].secret.trigger == "bracelet_push" and portal_to(two.rooms[&"ow_1b"], "l5_") != null, "Second quest: level 5 is under a rock")
	var cave: Resource = portal_to(two.rooms[&"ow_22"], "cave_")
	check(cave != null and cave.area.size.x == 17 and portal_to(one.rooms[&"ow_22"], "l6_") != null, "Level 6's wide entrance becomes a wide cave mouth")
	# Second-quest-only secrets exist only there; first-quest-only ones only in the first.
	check(two.rooms[&"ow_00"].secret != null and one.rooms[&"ow_00"].secret == null, "A second-quest wall to level 9")
	check(one.rooms[&"ow_05"].secret != null and two.rooms[&"ow_05"].secret == null, "The first quest's level 9 wall is gone")
	# Z_06 LevelBlockAddrsQ2 and LevelInfoUWQ2Replacements: other rooms, starts, and maps.
	var entrance: Resource = portal_to(two.rooms[&"ow_37"], "l1_")
	check(entrance != null and entrance.target_room == &"l1_77" and portal_to(one.rooms[&"ow_37"], "l1_").target_room == &"l1_73", "Level 1 starts in room $77 rather than $73")
	var start: Resource = two.rooms[&"l1_77"]
	check(portal_to(start, "ow_") != null and portal_to(start, "ow_").target_room == &"ow_37", "and leads back out to its entrance")
	check(portal_to(two.rooms[&"l2_75"], "ow_").target_room == &"ow_3c", "Level 2 leads out to its pond")
	check(two.submenu_layout.map_masks != one.submenu_layout.map_masks, "The submenu maps are the second quest's")
	var levels := {}
	for definition in two.rooms.values():
		if definition.dungeon_level > 0: levels[definition.dungeon_level] = true
	check(levels.size() == 9, "All nine levels are there")
	# Playing the recorder at the pond drains it to the stairs.
	two.enter_room(two.rooms[&"ow_3c"], Vector2i(96, 120), Vector2i.UP)
	two.state.take_item(load("res://content/items/recorder.tres"))
	two.play_recorder()
	for i in range(400): two.simulate_tick(Vector2i.ZERO)
	check(two.secrets.revealed, "The recorder drains the second quest's pond")
	one.free()
	two.free()

func check_front_end() -> void:
	temporary = OS.get_temp_dir().path_join("zelda-second-quest-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var front = preload("res://scenes/front_end.tscn").instantiate()
	front.files_directory = temporary
	root.add_child(front)
	front.set_physics_process(false)
	front.files.create(0, [0x15, 0x12, 0x17, 0x14, 0x24, 0x24, 0x24, 0x24])
	front.files.create(1, [0x23, 0x0E, 0x15, 0x0D, 0x0A, 0x24, 0x24, 0x24])
	front.show_files()
	front.play(1)
	check(front.world.quest == 2 and front.world.visible and front.mode == "playing", "A ZELDA file plays the second quest")
	front.world.menu_choice.emit("retry")
	front.play(0)
	check(front.world.quest == 1, "A first-quest file switches back")
	# The ending's switch: the file keeps its deaths and starts the second quest afresh.
	front.files.meta[0].deaths = 5
	front.world.state.max_health = 16
	front.world.menu_choice.emit("second_quest")
	var meta: Dictionary = front.files.meta[0]
	check(meta.quest == 2 and meta.deaths == 5 and meta.max_health == 6 and front.files.read_state(0, "original_quest_2").is_empty(), "Beating the game moves the file to a fresh second quest")
	check(front.mode == "files", "and back to the file menu")
	front.play(0)
	check(front.world.quest == 2 and front.world.state.max_health == 6, "where it then plays the second quest")
	front.free()
	var base := ProjectSettings.globalize_path(temporary)
	for folder in DirAccess.get_directories_at(base):
		for file in DirAccess.get_files_at(base.path_join(folder)): DirAccess.remove_absolute(base.path_join(folder).path_join(file))
		DirAccess.remove_absolute(base.path_join(folder))
	for file in DirAccess.get_files_at(base): DirAccess.remove_absolute(base.path_join(file))
	DirAccess.remove_absolute(base)
