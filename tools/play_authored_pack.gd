extends SceneTree
## Standalone entry point for authoring previews. No ROM, front end or save file.
const Contract = preload("res://editor/shared/room_pack.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var room_id := ""
	var check_only := "--check" in args
	for i in range(args.size()-1):
		if args[i] == "--pack": path = args[i+1]
		if args[i] == "--room": room_id = args[i+1]
	if path.is_empty(): fail("Need --pack /path/to/pack.json"); return
	var loaded := Contract.read(path)
	if not loaded.errors.is_empty(): fail("\n".join(loaded.errors)); return
	var result := Adapter.compile(loaded.pack)
	if not result.errors.is_empty(): fail("\n".join(result.errors)); return
	var world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false
	world.world_definition = result.world
	if not room_id.is_empty():
		if not loaded.pack.rooms.any(func(r): return r.id == room_id): world.free(); fail("Unknown preview room"); return
		result.world.start_room = StringName(room_id)
	root.add_child(world)
	world.state.take_item(load("res://content/items/wooden_sword.tres"))
	if "--screenshot" in args:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[args.find("--screenshot")+1])
		world.free()
		quit(0)
		return
	if check_only:
		world.set_physics_process(false)
		for i in range(120): world.simulate_tick(Vector2i.ZERO)
		print("Authored pack playtest: PASS (",world.rooms.size()," rooms; no ROM)")
		world.free()
		quit(0)
func fail(message: String) -> void:
	push_error(message)
	quit(2)
