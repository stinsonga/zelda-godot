extends SceneTree
## Replay recorded controller input through the real World simulation. Expected
## post-frame NES positions are never read to move or correct the native player.
var reference_path := ""
var output_path := ""
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--reference": reference_path = args[i+1]
		if args[i] == "--output": output_path = args[i+1]
	create_timer(60).timeout.connect(func() -> void: push_error("Movement capture timed out"); quit(2))
	call_deferred("run")
func direction(bits: int) -> Vector2i:
	match bits:
		1: return Vector2i.RIGHT
		2: return Vector2i.LEFT
		4: return Vector2i.DOWN
		8: return Vector2i.UP
	return Vector2i.ZERO
## ObjDir bits; jumpers face diagonals (Tektites' 5 is down-right, 10 up-left).
func bits(vector: Vector2i) -> int:
	return (1 if vector.x > 0 else 2 if vector.x < 0 else 0) | (4 if vector.y > 0 else 8 if vector.y < 0 else 0)
func input_direction(buttons: Array) -> Vector2i:
	var input := Vector2i.ZERO
	for button in buttons:
		match String(button):
			"right": input.x = 1
			"left": input.x = -1
			"down": input.y = 1
			"up": input.y = -1
	return input
func snapshot(world: Node) -> Dictionary:
	var at: Vector2i = world.player.pixel_position()
	var moving_between: bool = world.transition != null or world.entry_walk_remaining > 0
	var monsters: Array = []
	for actor in world.combat.enemies:
		if actor.alive() and not actor.waiting_spawn and actor.spawn_remaining == 0 and not actor.initializing and actor.slot >= 1:
			var p: Vector2i = actor.position()
			# The Zora's ObjDir holds its frame image instead of a direction.
			var dir: int = actor.family.zora_image if actor.definition.behavior == "zora" else bits(actor.facing)
			monsters.append([actor.slot, actor.definition.nes_type, p.x, p.y, dir])
	monsters.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# Shots by type and position, as the reference lists them ($53 flying rock).
	var shots: Array = []
	for rock in world.combat.rocks:
		if rock.kind == "rock":
			var p: Vector2i = rock.position()
			shots.append(["shot", 0x53, p.x, p.y])
	shots.sort()
	monsters.append_array(shots)
	return {"objects":monsters,"room":String(world.room.id),"x":at.x,"y":at.y,"direction":bits(world.player.facing),"phase":"transition" if moving_between else "play",
		"raw":{"subposition_x":world.player.subposition.x,"subposition_y":world.player.subposition.y,
		"entry_walk_remaining":world.entry_walk_remaining,"curtain":world.curtain,"random":Array(world.combat.source_random.bytes),"edge_timer":world.combat.edge_timer,"edge_cell":world.combat.edge_cursor,"frame_clock":world.combat.frame_clock}}
func fail(message: String) -> void:
	push_error(message)
	quit(2)
func run() -> void:
	if reference_path.is_empty() or output_path.is_empty(): fail("Need --reference and --output"); return
	var reference = JSON.parse_string(FileAccess.get_file_as_string(reference_path))
	if not reference is Dictionary or reference.get("schema") != 1: fail("Invalid movement reference"); return
	if not ResourceLoader.exists("res://imported/world.tres"): fail("Import the local ROM before native capture"); return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://imported/manifest.json"))
	if not manifest is Dictionary or manifest.get("prg_sha1") != reference.get("rom_prg_sha1"): fail("Imported content and reference ROM revisions differ"); return
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.audio.muted = true
	world.audio.apply_pause()
	world.menus_enabled = false
	var cases: Array = []
	for recorded in reference.cases:
		var initial: Dictionary = recorded.initial
		var room_id := StringName(initial.room)
		if not world.rooms.has(room_id): world.free(); fail("Movement room is unavailable"); return
		world.state = preload("res://scripts/game_state.gd").new()
		world.enter_room(world.rooms[room_id],Vector2i(int(initial.x),int(initial.y)),direction(int(initial.direction)),0,true)
		# The NES seed has already completed its curtain and entry walk.
		world.curtain = -1
		# A case with setup frames may start partway through Link's movement.
		var raw: Dictionary = initial.get("raw", {})
		world.player.fraction = int(raw.get("fraction", 0))
		var offset := int(raw.get("grid_offset", 0))
		world.player.grid_offset = offset - 256 if offset >= 128 else offset
		# Start from the reference's monster state, like its position: the random
		# bytes ($18-$24), the edge spawn cursor and timer, and the phase of the
		# ten-frame long-timer counter ($26 counts down; timers tick when it wraps).
		world.combat.source_random.bytes = PackedByteArray(recorded.initial.get("random", Array(world.combat.source_random.bytes)))
		# Zelda's NMI scrambles them before running the frame's logic, as Godot does.
		world.combat.edge_cursor = int(recorded.initial.get("edge_cell", world.combat.edge_cursor))
		world.combat.edge_timer = int(recorded.initial.get("edge_timer", world.combat.edge_timer))
		if recorded.initial.has("chase"):
			# ChaseTargetX/Y ($61/$62), ChaseOtherTarget ($60), ChaseLongTimer ($4A).
			var chase: Array = recorded.initial.chase
			world.combat.chase_target = Vector2i(int(chase[0]), int(chase[1]))
			world.combat.chase_other = int(chase[2]) != 0
			world.combat.chase_timer = int(chase[3])
		# SpawnCycle ($524): where spawn lists resume, carried across rooms.
		world.state.spawn_cycle = int(recorded.initial.get("spawn_cycle", 0))
		if recorded.initial.has("timer_cycle"):
			world.combat.frame_clock = posmod(-(int(recorded.initial.timer_cycle) + 1), 10)
		var seed := snapshot(world)
		var frames: Array = []
		for recorded_frame in recorded.frames:
			var buttons: Array = recorded_frame.buttons
			if buttons.size() > 2 or (not buttons.is_empty() and input_direction(buttons) == Vector2i.ZERO): world.free(); fail("Unsupported movement input"); return
			world.simulate_tick(input_direction(buttons))
			var row := snapshot(world)
			row["frame"] = recorded_frame.frame
			row["buttons"] = buttons
			frames.append(row)
		cases.append({"id":recorded.id,"initial":seed,"frames":frames})
	var result := {"schema":1,"engine":"godot","suite":reference.suite,"suite_sha256":reference.suite_sha256,
		"rom_prg_sha1":manifest.prg_sha1,"godot_version":Engine.get_version_info().string,
		"adapter":"World.simulate_tick; natural NES seed; completed entry curtain", "cases":cases}
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file == null: world.free(); fail("Cannot write native movement capture"); return
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	world.free()
	print("Native movement capture: ",output_path)
	quit(0)
