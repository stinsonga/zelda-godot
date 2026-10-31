extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1;push_error(message)
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Generation checks timed out");quit(1))
	call_deferred("run")
func pair(kind: String = "key") -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack)
	var end := Pack.room("end","End");end.map_position = [0,-1]
	pack.rooms[0].connections = {"up":{"target":"end","kind":kind}}
	end.connections = {"down":{"target":"entry","kind":kind}}
	end.pickups = [{"id":"prize","item":"rupee","position":[120,77]}]
	pack.rooms.append(end);pack.goals = [{"room":"end","pickup":"prize"}]
	return pack
func key_at(pack: Dictionary, room_index: int = 0, position: Array = [64,77]) -> void:
	pack.rooms[room_index].pickups.append({"id":"key","item":"key","position":position})
func solved(pack: Dictionary) -> bool: return Solver.new().solve(pack).status == "solved"
func run() -> void:
	var pack := pair();key_at(pack)
	check(solved(pack),"Reachable key opens lock")
	pack = pair();key_at(pack,1)
	check(not solved(pack),"Key behind its own lock cannot solve dungeon")
	pack = pair();pack.starting_items.append("magic_key")
	check(solved(pack),"Magical key opens key doors without consuming a small key")
	pack = pair("open")
	pack.rooms[0].connections.up.requires = ["blue_candle"]
	pack.rooms[1].connections.down.requires = ["blue_candle"]
	check(not solved(pack),"Missing required item blocks otherwise open door")
	pack.rooms[0].pickups.append({"id":"tool","item":"blue_candle","position":[64,77]})
	check(solved(pack),"Reachable required item opens capability gate")
	pack.rooms[0].pickups = [];pack.rooms[1].pickups.append({"id":"tool","item":"blue_candle","position":[64,77]})
	check(not solved(pack),"Required item cannot be behind its own gate")
	pack = pair();key_at(pack,0,[176,77])
	for y in range(2,9):
		var row: String = pack.rooms[0].tiles[y]
		pack.rooms[0].tiles[y] = row.left(9)+"#"+row.substr(10)
	var isolated := Solver.new().solve(pack)
	check(isolated.status == "blocked" and "walkable region" in "\n".join(isolated.blockers),"Isolated key in a connected room graph is detected")
	pack = pair();key_at(pack)
	pack.rooms[0].tiles[3] = "################"
	check(not solved(pack),"Interior wall blocks access to a nominally connected exit")
	pack = pair("shutter");pack.starting_items = []
	pack.rooms[0].enemies = [{"id":"guard","type":"crawler","position":[80,77]}]
	check(not solved(pack),"Cannot clear sword encounter with no sword")
	pack.starting_items = ["wooden_sword"]
	check(solved(pack),"Sword makes reachable vulnerable encounter clearable under model")
	pack.rooms[0].shutter_trigger = 0
	check(not solved(pack),"One-way closed shutter does not become passable from monster assumptions")
	# One key must pay only once when returning through the paired door.
	pack = pair();pack.starting_items = [];key_at(pack)
	pack.rooms[0].enemies = [{"id":"guard","type":"crawler","position":[80,77]}]
	pack.rooms[0].pickups.append({"id":"prize","item":"rupee","position":[120,77],"requires_clear":true})
	pack.rooms[1].pickups = [{"id":"sword","item":"wooden_sword","position":[120,77]}]
	pack.goals = [{"room":"entry","pickup":"prize"}]
	var returning := Solver.new().solve(pack)
	check(returning.status == "solved" and returning.events.any(func(e): return e.type == "travel" and e.room == "end"),"Both sides of an opened door stay open on return with zero keys")
	# Two successive key locks, only one pickup: revisiting it must not farm keys.
	pack = pair();key_at(pack)
	var third := Pack.room("third");third.map_position = [1,-1]
	pack.rooms[1].connections.right = {"target":"third","kind":"key"}
	third.connections.left = {"target":"end","kind":"key"}
	third.pickups = [{"id":"goal","item":"rupee","position":[120,77]}]
	pack.rooms.append(third);pack.goals = [{"room":"third","pickup":"goal"}]
	check(not solved(pack),"A collected key cannot respawn by revisiting the room")
	pack = pair("bombable")
	check(not solved(pack),"Bombable lock requires a finite bomb")
	pack.rooms[0].pickups = [{"id":"bombs","item":"bombs","position":[64,77]}]
	check(solved(pack),"Bomb supply opens bombable connection")
	pack.starting_items.append_array(["bombs","bombs"])
	check(Solver.new().solve(pack).status == "solved" and Solver.new().solve(pack).assumptions.contains("taken immediately"),"Bomb supplies beyond the bag are solved under immediate pickups")
	pack = pair("open")
	check(Solver.new().solve(pack,1).status == "limit","Search exhaustion is inconclusive")
	check(Solver.new().solve(pack,20000,-1).get("limit_kind") == "time","Wall-clock exhaustion is distinguished from state limits")
	pack.goals = []
	check(Solver.new().solve(pack).status == "unsupported","Empty goals are not automatic success")
	pack = pair("open");pack.rooms[0].tiles[3] = "##..~.........##"
	check(Solver.new().solve(pack).status == "solved","Water is solid scenery that a route may pass around")
	pack = pair("open");pack.rooms[0].connections.up.requires = ["bow"]
	check(not Pack.validate(pack).is_empty(),"Mismatched reverse item requirements rejected")
	pack = pair("open");pack.goals[0].pickup = "missing"
	check(Solver.new().solve(pack).status == "invalid","Missing goal pickup is invalid")
	var catalog := Templates.defaults()
	check(Templates.validate(catalog).is_empty(),"Default authored templates validate")
	var first := Generator.new().generate(catalog,42,8)
	var second := Generator.new().generate(catalog,42,8)
	var timed := Generator.new().generate(catalog,42,8,"blue_candle",0)
	check(not timed.errors.is_empty() and timed.get("proof",{}).get("limit_kind") == "time","Time budget failure never publishes a different candidate")
	check(first.errors.is_empty() and Templates.canonical(first.pack) == Templates.canonical(second.pack),"Same seed and recipe give identical packs")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(catalog))
	check(Templates.fingerprint(roundtrip) == Templates.fingerprint(catalog),"Template fingerprint survives JSON numeric conversion")
	var parsed := Generator.new().generate(roundtrip,42,8)
	check(Templates.canonical(parsed.pack) == Templates.canonical(first.pack),"Saved and built-in libraries reproduce the same dungeon")
	check(Templates.canonical(Generator.new().generate(catalog,43,8).pack) != Templates.canonical(first.pack),"Different seed varies dungeon")
	var runs := 0
	for seed_value in [0,1,42,314159]:
		for size in [6,8,12,16]:
			var result := Generator.new().generate(catalog,seed_value,size)
			check(result.errors.is_empty(),"Seed %d size %d finds verified candidate" % [seed_value,size])
			if not result.has("pack"): continue
			check(Pack.validate(result.pack).is_empty() and result.pack.rooms.size() == size,"Generated schema, dimensions and goal references validate")
			check(result.proof.status == "solved" and result.proof.events.size() == result.proof.steps.size(),"Published result includes structured witness")
			check(result.proof.reached_rooms.size() == size,"All generated rooms occur in search for mandatory objectives")
			runs += 1
	for item in Pack.REQUIRED_ITEMS:
		var result := Generator.new().generate(catalog,77,8,item)
		check(result.errors.is_empty(),"Supported required item can be placed before gate: "+item)
	var impossible := catalog.duplicate(true)
	for template in impossible.templates:
		if template.role == "key": template.requires = ["bow"]
	check(not Generator.new().generate(impossible,42,8,"blue_candle").errors.is_empty(),"Generator rejects libraries whose required items cannot be reached")
	var source := Pack.sample();source.enemy_types.crawler.health = 7
	var capture := Templates.capture(catalog,source,"hall","new_hall","combat",Pack.EDGES,[])
	check(capture.errors.is_empty() and capture.catalog.templates.size() == catalog.templates.size()+1,"Capture creates a reusable room template")
	check(capture.catalog.enemy_types.crawler.health == 2,"Capturing edited enemy preserves existing templates' definitions")
	var long_a := Templates.capture(catalog,source,"hall","shared_long_template_prefix_a","combat",Pack.EDGES,[])
	var long_b := Templates.capture(long_a.catalog,source,"hall","shared_long_template_prefix_b","combat",Pack.EDGES,[])
	check(long_a.errors.is_empty() and long_b.errors.is_empty() and long_b.catalog.templates[-1].room.enemies[0].type != long_b.catalog.templates[-2].room.enemies[0].type,"Long template IDs cannot alias their enemy variants")
	check(capture.catalog.templates.back().room.connections.is_empty(),"Captured connections do not leak into generated topology")
	check(not JSON.stringify(capture.catalog).contains("rom/us_prg0"),"Captured library is ROM-free")
	check(not Templates.capture(catalog,source,"hall","combat_plain","combat",Pack.EDGES,[]).errors.is_empty(),"Duplicate template IDs do not overwrite authored content")
	# Real threaded dialog and document controls.
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Pack.sample(),"",false)
	ui.select_room("hall");ui.add_objective()
	check(ui.pack.schema == 1 and ui.pack.get("goals",[]).is_empty(),"Room without pickup does not add a false objective")
	ui.select_room("vault");ui.add_objective()
	check(ui.pack.schema == 2 and ui.pack.goals.size() == 1,"Objective control upgrades legacy pack with starting sword")
	ui.undo();check(ui.pack.schema == 1,"Undo objective upgrade restores original version")
	ui.open_dungeon_tools(0)
	ui.dungeon_tools.seed_input.text = "42"
	ui.dungeon_tools.start_generation()
	while ui.dungeon_tools.busy: await process_frame
	check(not ui.dungeon_tools.candidate.is_empty() and not ui.dungeon_tools.use_button.disabled,"Threaded generation presents a verified candidate")
	ui.dungeon_tools.source_pack = ui.dungeon_tools.candidate.duplicate(true)
	ui.dungeon_tools.start_solver()
	while ui.dungeon_tools.busy: await process_frame
	check(ui.dungeon_tools.report.text.begins_with("SOLVED"),"Threaded progression report shows witness")
	ui.dungeon_tools.seed_input.text = "43"
	ui.dungeon_tools.seed_input.text_changed.emit("43")
	check(ui.dungeon_tools.candidate.is_empty() and ui.dungeon_tools.use_button.disabled,"Editing recipe invalidates prior candidate")
	ui.open_dungeon_tools(1)
	ui.dungeon_tools.template_id.text = "captured_vault"
	ui.dungeon_tools.role.select(4)
	ui.dungeon_tools.picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	var library_path := OS.get_temp_dir().path_join("zelda-captured-library-%d.json" % OS.get_process_id())
	if FileAccess.file_exists(library_path): DirAccess.remove_absolute(library_path)
	ui.dungeon_tools.file_selected(library_path)
	var saved := Templates.read(library_path)
	check(saved.errors.is_empty() and saved.catalog.templates.any(func(t): return t.id == "captured_vault"),"Template dialog saves a usable derived library")
	DirAccess.remove_absolute(library_path)
	ui.free()
	Pack.write("/tmp/zelda-generation-fixture.json",first.pack)
	print("Generation checks: ","PASS" if failures == 0 else "FAIL"," (",runs," seed/size cases plus item and counterexample cases)")
	quit(0 if failures == 0 else 1)
