extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Solver = preload("../shared/progression_solver.gd")
const Fixture = preload("stairs_fixture.gd")
const Templates = preload("../shared/dungeon_templates.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Stair editor checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	for arrival_on_return in [false,true]:
		var pack := Fixture.sample(arrival_on_return)
		check(Pack.validate(pack).is_empty(),"Hidden-stair fixture validates")
		var proof := Solver.new().solve(pack)
		check(proof.status == "solved" and proof.events.filter(func(e): return e.type == "stairs").size() >= 2,"Progression goes through cellar and back")
		check(Pack.layout_warnings(pack).is_empty(),"Stair-linked cellar is connected in map review")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(pack))
		check(Pack.validate(parsed).is_empty() and Solver.new().solve(parsed).status == "solved","Stair JSON roundtrip preserves progression")
	for arrival_root in [false,true]:
		var trap := Fixture.trap(arrival_root)
		check(Pack.validate(trap).is_empty(),"Forced-stair trap is structurally valid")
		check(Solver.new().solve(trap).status == "blocked","Cannot walk through active stair or reuse suppressed arrival after moving away")
	var split := Fixture.trap(true)
	split.starting_items = ["wooden_sword"]
	split.rooms[1].enemies.append({"id":"other_guard","type":"crawler","position":[112,125]})
	split.rooms[1].pickups[0].position = [112,77]
	check(Solver.new().solve(split).status == "blocked","Combat cannot merge opposite sides of a suppressed arrival stair")
	var pack := Fixture.sample()
	for broken in [null,{}, {"id":"bad","cell":[6,5],"target":"missing","target_position":[120,125]}, {"id":"bad","cell":[6,5],"target":"cellar","target_position":[49,61]}, {"id":"bad","cell":[2,5],"target":"cellar","target_position":[48,61]}, {"id":"bad","cell":[7,5],"target":"cellar","target_position":[48,61]}]:
		var invalid := pack.duplicate(true);invalid.rooms[0].stairs = [broken]
		check(not Pack.validate(invalid).is_empty(),"Malformed, blocked or off-grid stair rejected")
	var example := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/stair_vault.json"))
	check(example.errors.is_empty() and Solver.new().solve(example.pack).status == "solved","Shipped stair example validates and solves")
	var captured := Templates.capture(Templates.defaults(),pack,"entry","linked","treasure",Pack.EDGES,[])
	check(not captured.errors.is_empty(),"Single-room template capture must reject linked stairs")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Pack.fresh(),"",false)
	ui.create_cellar({"id":"","cell":[6,5],"target":"","target_position":[48,61],"requires_secret":false})
	check(ui.pack.rooms.size() == 2 and ui.current().stairs.size() == 1 and ui.undo_stack.size() == 1,"Create cellar and reciprocal links in one undo")
	check(Pack.validate(ui.pack).is_empty() and Pack.layout_warnings(ui.pack).is_empty(),"Created cellar is valid and connected")
	var cellar_id: String = ui.current().stairs[0].target
	check(ui.find_room(cellar_id).kind == "cellar" and ui.find_room(cellar_id).stairs[0].target == "entry","Created cellar has return link")
	ui.undo();check(ui.pack.schema == 1 and ui.pack.rooms.size() == 1,"Undo removes cellar, links and schema upgrade")
	ui.redo();check(ui.pack.rooms.size() == 2,"Redo restores cellar")
	ui.select_room(cellar_id);ui.delete_room()
	check(ui.pack.rooms.size() == 1 and ui.current().stairs.is_empty(),"Deleting cellar removes incoming stairs")
	ui.undo();check(ui.current().stairs.size() == 1,"Undo restores incoming stair")
	ui.replace_pack(Fixture.sample(),"",false);ui.duplicate_room()
	check(not ui.current().has("stairs"),"Room copy has no outgoing stair links")
	ui.undo();ui.select_room("entry");ui.remove_block()
	check(not ui.current().stairs[0].get("requires_secret",false),"Removing block clears dependent stair secret gate")
	ui.undo();check(ui.current().stairs[0].requires_secret,"Undo restores hidden stair gate")
	ui.replace_pack(JSON.parse_string(JSON.stringify(Fixture.sample())),"",false)
	ui.apply_stair(ui.current().stairs[0].duplicate(true))
	check(not ui.dirty() and ui.undo_stack.is_empty(),"Unchanged stair apply is a JSON-safe no-op")
	var stair: Dictionary = ui.current().stairs[0].duplicate(true);stair.target_position = [48,69]
	ui.apply_stair(stair)
	check(ui.current().stairs[0].id == "hidden_stairs" and ui.undo_stack.size() == 1,"Editing stair preserves stable ID with one undo")
	ui.undo();ui.remove_stair("hidden_stairs")
	check(ui.current().stairs.is_empty(),"Stair delete removes only its link")
	ui.undo();check(ui.current().stairs.size() == 1,"Undo restores stair")
	ui.replace_pack(Fixture.sample(),"",false);ui.set_tool("Stairs");ui.stairs_inspector.choose("hidden_stairs")
	ui.canvas.stroke_started.emit();ui.paint(Vector2i(6,4),false);ui.paint(Vector2i(6,3),false);ui.canvas.stroke_finished.emit()
	check(ui.undo_stack.size() == 1 and ui.current().stairs[0].cell == [6,3],"Moving stairs with a brush stroke is one undo")
	ui.undo();check(ui.current().stairs[0].cell == [6,5],"Undo restores stair source cell")
	var before: Dictionary = ui.pack.duplicate(true)
	ui.apply_block({"cell":[5,5],"direction":"right","reveal":"item"})
	check(ui.pack == before,"Block cannot move its landing onto existing stairs")
	check(Pack.write("/tmp/zelda-stair-vault.json",Fixture.sample()) == OK,"Stair example writes")
	ui.queue_free();await process_frame
	print("Stair editor checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
