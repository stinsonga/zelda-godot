extends SceneTree
## Authoring preview: no ROM required; optional local art, no front end/save file.
const Contract = preload("res://editor/shared/room_pack.gd")
const Appearance = preload("res://editor/shared/appearance.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var room_id := ""
	var appearance_path := ""
	var check_only := "--check" in args
	for i in range(args.size()-1):
		if args[i] == "--pack": path = args[i+1]
		if args[i] == "--room": room_id = args[i+1]
		if args[i] == "--appearance": appearance_path = args[i+1]
	if path.is_empty(): fail("Need --pack /path/to/pack.json"); return
	var loaded := Contract.read(path)
	if not loaded.errors.is_empty(): fail("\n".join(loaded.errors)); return
	var overlay: Dictionary = {}
	if "--no-local-art" not in args:
		if not appearance_path.is_empty():
			var data = JSON.parse_string(FileAccess.get_file_as_string(appearance_path))
			if data is Dictionary: overlay = data
			else: push_warning("Cannot read appearance snapshot; using placeholders")
		else:
			var local := Appearance.read_local(ProjectSettings.globalize_path("res://"),loaded.pack)
			overlay = local.overlay
			for warning in local.warnings: push_warning(warning)
	var result := Adapter.compile(loaded.pack,overlay)
	for warning in result.get("appearance_warnings",[]): push_warning(warning)
	if not result.errors.is_empty(): fail("\n".join(result.errors)); return
	var world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false
	world.world_definition = result.world
	if not room_id.is_empty():
		if not loaded.pack.rooms.any(func(r): return r.id == room_id): world.free(); fail("Unknown preview room"); return
		result.world.start_room = StringName(room_id)
	world.tree_exiting.connect(func(): world.combat.encounter_room = null)
	var title: String = loaded.pack.title.replace("\n"," ").replace("\r"," ").strip_edges().left(120)
	root.title = "Dungeon playtest"+(" — "+title if not title.is_empty() else "")
	root.add_child(world)
	if check_only:
		world.set_physics_process(false)
		for i in range(120): world.simulate_tick(Vector2i.ZERO)
		print("Authored pack playtest: PASS (",world.rooms.size()," rooms)")
	if "--screenshot" in args:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[args.find("--screenshot")+1])
		world.free()
		result.clear()
		quit(0)
		return
	if check_only:
		world.free()
		result.clear()
		quit(0)
func fail(message: String) -> void:
	push_error(message)
	quit(2)
