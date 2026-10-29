extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Fixture = preload("resident_fixture.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var pack := Fixture.sample()
	check(Pack.validate(pack).is_empty(),"Resident village validates")
	check(Pack.layout_warnings(pack).is_empty(),"Caves connect through stair links")
	check(Pack.validate(JSON.parse_string(JSON.stringify(pack))).is_empty(),"Resident data survives JSON")
	check(Solver.new().solve(pack).status == "unsupported","Resident transactions never receive an unsupported solvability claim")
	for malformed in [null,{}, {"mode":"hint","text":"X","wares":[null]}, {"mode":"gift","text":"X","wares":[null,null,null]}, {"mode":"shop","text":"X","wares":[null,null,null]}, {"mode":"hint","text":"X".repeat(25),"wares":[null,null,null]}, {"mode":"hint","text":"X\nX\nX\nX","wares":[null,null,null]}, {"mode":"gift","text":"X","wares":[null,{"item":"bow","price":1},null]}, {"mode":"shop","text":"X","wares":[null,{"item":"../../bad","price":1},null]}]:
		var broken := pack.duplicate(true);broken.rooms[1].resident = malformed
		check(not Pack.validate(broken).is_empty(),"Malformed resident is rejected")
	var broken := pack.duplicate(true);broken.rooms[1].pickups = [{"id":"taken","item":"key","position":[64,77]}]
	check(not Pack.validate(broken).is_empty(),"Cave transaction flag cannot alias a floor pickup")
	broken = pack.duplicate(true);broken.rooms[1].stairs[0].cell = [3,3]
	check(not Pack.validate(broken).is_empty(),"Resident barrier cannot hide a return stair above the reachable area")
	var example := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/resident_village.json"))
	check(example.errors.is_empty() and example.pack.rooms[0].pickups.size() >= 20,"Shipped cave example validates and funds a shop purchase")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Pack.fresh(),"",false)
	ui.apply_resident(Pack.resident("hint"))
	check(ui.pack.schema == 2 and ui.current().resident.mode == "hint" and ui.undo_stack.size() == 1,"Applying resident upgrades pack as one undo step")
	ui.undo();check(ui.pack.schema == 1 and not ui.current().has("resident"),"Undo restores legacy pack")
	ui.create_cellar({"id":"","cell":[6,5],"target":"","target_position":[120,125],"requires_secret":false},true)
	var target: String = ui.current().stairs[0].target
	check(ui.pack.rooms.size() == 2 and ui.find_room(target).kind == "cave" and ui.find_room(target).resident.mode == "hint","Linked cave creation creates resident and return link")
	ui.undo();check(ui.pack.rooms.size() == 1,"Undo removes linked cave and its source link")
	ui.replace_pack(JSON.parse_string(JSON.stringify(Fixture.sample())),"",false);ui.select_room("shop")
	ui.apply_resident(ui.current().resident.duplicate(true))
	check(not ui.dirty() and ui.undo_stack.is_empty(),"Unchanged resident Apply is JSON-safe")
	ui.resident_inspector.prices[1].value = 25;ui.resident_inspector.applied.emit(ui.resident_inspector.value())
	check(ui.current().resident.wares[1].price == 25 and ui.undo_stack.size() == 1,"Inspector updates shop price with undo")
	ui.undo();ui.apply_resident({});check(not ui.current().has("resident"),"None removes resident")
	ui.undo();check(ui.current().resident.mode == "shop","Undo restores resident")
	check(Pack.write("/tmp/zelda-resident-village.json",Fixture.sample()) == OK,"ROM-free example writes")
	ui.queue_free();await process_frame
	print("Resident editor checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
