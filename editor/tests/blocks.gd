extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Fixture = preload("block_fixture.gd")
const Solver = preload("../shared/progression_solver.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Templates = preload("../shared/dungeon_templates.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(40).timeout.connect(func(): push_error("Block editor checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	for direction in Pack.EDGES:
		for reveal in ["shutters","item"]:
			var pack := Fixture.sample(direction,reveal)
			check(Pack.validate(pack).is_empty(),"Block fixture validates "+direction+"/"+reveal)
			var result := Solver.new().solve(pack)
			check(result.status == "solved" and result.events.any(func(e): return e.type == "push"),"Solver includes real push event "+direction+"/"+reveal)
			check(Solver.new().solve(JSON.parse_string(JSON.stringify(pack))).status == "solved","Block geometry survives JSON round trip")
	var revisit := Solver.new().solve(Fixture.revisit())
	check(revisit.status == "solved" and revisit.events.filter(func(e): return e.type == "push").size() >= 2,"Returning for a required item must push the reset block again")
	var pack := Fixture.sample()
	pack.rooms[0].enemies = [{"id":"guard","type":"crawler","position":[176,61]}]
	pack.starting_items = []
	check(Solver.new().solve(pack).status == "blocked","Block cannot move while monsters live and no sword is available")
	pack.starting_items = ["wooden_sword"]
	check(Solver.new().solve(pack).status == "solved","Sword permits assumed combat victory then push")
	# Approach is floor but isolated from Link: the block forms a one-way deadlock.
	pack = Fixture.sample()
	for y in range(2,9): pack.rooms[0].tiles[y] = "##...#........##"
	pack.rooms[0].tiles[5] = "##............##"
	check(Pack.validate(pack).is_empty(),"Isolated-approach counterexample is structurally valid")
	check(Solver.new().solve(pack).status == "blocked","Solver rejects an unreachable side of a directional block")
	pack = Fixture.sample();pack.rooms[0].secret.direction = "left"
	for y in range(2,9): pack.rooms[0].tiles[y] = "##...#........##"
	pack.rooms[0].tiles[5] = "##............##"
	check(Solver.new().solve(pack).status == "solved","Pushable direction opens same divided geometry")
	for malformed in [null,{}, {"cell":[6,5],"direction":"diagonal","reveal":"item"},{"cell":[13,5],"direction":"right","reveal":"shutters"},{"cell":[6,5],"direction":"right","reveal":"stairs"}]:
		pack = Fixture.sample();pack.rooms[0].secret = malformed
		check(not Pack.validate(pack).is_empty(),"Malformed or unsupported block rejected")
	pack = Fixture.sample();pack.rooms[0].spawn = [96,77]
	check(not Pack.validate(pack).is_empty(),"Spawn inside initial block rejected")
	pack = Fixture.sample();pack.rooms[0].erase("secret")
	check(not Pack.validate(pack).is_empty(),"Secret pickups and shutter trigger cannot outlive their block")
	pack = Fixture.sample()
	var captured := Templates.capture(Templates.defaults(),pack,"entry","block_room","treasure",Pack.EDGES,[])
	check(captured.errors.is_empty() and captured.catalog.templates[-1].room.secret == pack.rooms[0].secret,"Template capture preserves block data")
	var catalog := Templates.defaults()
	for template in catalog.templates:
		if template.role == "key": template.room.secret = {"cell":[6,5],"direction":"left","reveal":"item"}
	var generated := Generator.new().generate(catalog,42,8)
	check(generated.errors.is_empty(),"Generator can use authored puzzle templates")
	if generated.has("proof"): check(generated.proof.events.any(func(e): return e.type == "push"),"Generated progression requires template block push")
	var solver = Solver.new();solver.solve(pack)
	var state := {"room":"entry","at":Vector2i(120,125),"items":1,"opened":0,"pushed":false}
	check(solver.blocked(pack.rooms[0],Vector2i(96,80),0,false) and not solver.blocked(pack.rooms[0],Vector2i(112,80),0,false),"Initial block collision matches original square")
	check(not solver.blocked(pack.rooms[0],Vector2i(96,80),0,true) and solver.blocked(pack.rooms[0],Vector2i(112,80),0,true),"Pushed block collision moves to landing square")
	check(solver.door_mask(state,true) == 0,"Room clear alone cannot open block shutter")
	state.pushed = true
	check(solver.door_mask(state,true) != 0,"Push opens block shutter")
	var example := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/block_vault.json"))
	check(example.errors.is_empty() and Solver.new().solve(example.pack).status == "solved","Shipped ROM-free block example validates and solves")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Pack.sample(),"",false)
	ui.apply_block({"cell":[6,5],"direction":"right","reveal":"shutters"})
	check(ui.pack.schema == 2 and ui.current().shutter_trigger == 4 and ui.undo_stack.size() == 1,"Block authoring upgrades pack with one undo")
	ui.apply_block({"cell":[6,5],"direction":"right","reveal":"shutters"})
	check(ui.undo_stack.size() == 1,"Unchanged block properties do not add history")
	ui.select_placement("pickups","entry_key")
	ui.placement_inspector.secret_reward.button_pressed = true;ui.placement_inspector.apply()
	check(ui.selected_placement().requires_secret,"Inspector can gate pickup on push")
	ui.select_placement("spawn","");ui.move_placement("entry",[96,77])
	check(ui.same_position(ui.current().spawn,[120,125]),"Spawn movement cannot overlap block")
	ui.select_placement("pickups","entry_key")
	ui.move_placement("entry",[96,77])
	check(ui.same_position(ui.selected_placement().position,[96,77]),"Hidden pickup may be placed under the block")
	ui.remove_block()
	check(not ui.current().has("secret") and not ui.current().pickups[0].has("requires_secret") and ui.current().shutter_trigger == 1,"Remove clears block dependencies")
	ui.undo()
	check(ui.current().has("secret") and ui.current().pickups[0].requires_secret,"Undo restores block and gated pickup")
	ui.replace_pack(Pack.fresh(),"",false);ui.set_tool("Block")
	ui.canvas.stroke_started.emit();ui.paint(Vector2i(6,5),false);ui.paint(Vector2i(8,5),false);ui.canvas.stroke_finished.emit()
	check(ui.undo_stack.size() == 1 and ui.current().secret.cell == [8,5],"Block brush stroke is one undo action")
	ui.undo();check(not ui.current().has("secret") and ui.pack.schema == 1,"Undo stroke removes block and schema upgrade")
	ui.apply_block({"cell":[13,5],"direction":"right","reveal":"shutters"})
	check(ui.undo_stack.is_empty(),"Invalid landing rejected without history")
	ui.replace_pack(JSON.parse_string(JSON.stringify(Fixture.sample())),"",false)
	ui.apply_block({"cell":[6,5],"direction":"right","reveal":"shutters"})
	check(not ui.dirty() and ui.undo_stack.is_empty(),"Unchanged JSON-loaded block properties do not dirty the document")
	check(Pack.write("/tmp/zelda-block-pack.json",Fixture.sample()) == OK,"Block pack saves")
	check(Pack.read("/tmp/zelda-block-pack.json").errors.is_empty(),"Block pack roundtrip validates")
	ui.queue_free();await process_frame
	print("Block editor checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
