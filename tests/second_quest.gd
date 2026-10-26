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
	second_quest.enter_room(second_quest.rooms[&"l2_2e"], Vector2i(120, 77), Vector2i.UP)
	rope = first(second_quest, &"rope_q2")
	check(rope != null and rope.health == 4 and rope.definition.sprite_palette_cycle, "Second-quest Ropes have $40 HP and cycle palettes")
	check(second_quest.visual_theme.sprites.has(&"l2_rope_down_0_p3"), "Each palette has its sprites")
	second_quest.enter_room(second_quest.rooms[&"l1_33"], Vector2i(120, 77), Vector2i.UP)
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
