extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Fixture = preload("destructible_fixture.gd")
const Solver = preload("../shared/progression_solver.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for trigger in ["bomb","fire"]:
		for direction in Pack.EDGES:
			for reveal in ["item","shutters"]:
				var pack := Fixture.sample(trigger,direction,reveal)
				check(Pack.validate(pack).is_empty(),"Secret validates "+trigger+"/"+direction+"/"+reveal)
				var result := Solver.new().solve(pack)
				check(result.status == "solved" and result.events.any(func(e): return e.type == "reveal" and e.trigger == trigger),"Witness uses the correct secret trigger")
		var pack := Fixture.revisit(trigger)
		var result := Solver.new().solve(pack)
		check(result.status == "solved" and result.events.filter(func(e): return e.type == "reveal").size() == 1,"Return route reuses persistent reveal")
		check(Solver.new().solve(Fixture.doorway_revisit(trigger)).status == "solved","Forced re-entry crosses a remembered cleared object")
		pack = Fixture.sample(trigger);pack.starting_items = ["wooden_sword"]
		check(Solver.new().solve(pack).status == "blocked","Missing bomb/candle cannot reveal")
		pack.rooms[0].pickups[0].item = "bombs" if trigger == "bomb" else "blue_candle"
		check(Solver.new().solve(pack).status == "blocked","Required item hidden behind its own secret cannot solve")
		pack = Fixture.sample(trigger)
		pack.rooms[0].stairs = [{"id":"hidden","cell":[6,5],"target":"cellar","target_position":[48,61],"requires_secret":true}]
		var cellar := Pack.cellar("cellar");cellar.map_position = [1,0]
		cellar.stairs = [{"id":"return","cell":[3,3],"target":"entry","target_position":[120,125]}]
		pack.rooms.append(cellar)
		check(Pack.validate(pack).is_empty(),"Hidden entrance can replace destroyed object")
	for pack in [Fixture.gifted_candle(),Fixture.purchased_bombs()]:
		var result := Solver.new().solve(pack)
		check(result.status == "solved" and result.events.any(func(e): return e.type == "resident") and result.events.any(func(e): return e.type == "reveal"),"Resident-provided items fund a secret route")
	for malformed in [null,[],{},42]:
		var invalid := Fixture.sample();invalid.rooms[0].secret.trigger = malformed
		check(not Pack.validate(invalid).is_empty(),"Malformed trigger returns validation errors")
	var bad := Fixture.sample();bad.rooms[0].secret.trigger = "recorder"
	check(not Pack.validate(bad).is_empty(),"Unsupported trigger rejected")
	var isolated := Fixture.sample()
	for cell in [Vector2i(4,5),Vector2i(5,4),Vector2i(5,6)]:
		var row: String = isolated.rooms[0].tiles[cell.y];isolated.rooms[0].tiles[cell.y] = row.left(cell.x)+"#"+row.substr(cell.x+1)
	check(Pack.validate(isolated).is_empty() and Solver.new().solve(isolated).status == "blocked","A disconnected configured approach is not a proof")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(Fixture.revisit()))
	check(Solver.new().solve(roundtrip).status == "solved","Persistent reveals survive JSON")
	for name in ["bomb","fire"]:
		var example := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/"+name+"_route.json"))
		check(example.errors.is_empty() and Solver.new().solve(example.pack).status == "solved","Shipped secret example certifies: "+name)
	var shipped := Templates.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/templates/destructible_templates.json"))
	check(shipped.errors.is_empty() and Templates.fingerprint(shipped.catalog) == Templates.fingerprint(Fixture.catalog()),"Shipped template library matches tested geometry")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Pack.fresh(),"",false)
	ui.apply_block(Fixture.sample().rooms[0].secret)
	check(ui.pack.schema == 2 and Pack.secret_trigger(ui.current().secret) == "bomb" and ui.undo_stack.size() == 1,"Secret inspector applies trigger with undo")
	ui.undo();check(not ui.current().has("secret") and ui.pack.schema == 1,"Undo restores legacy document")
	ui.block_inspector.trigger.select(2);ui.set_tool("Block")
	ui.canvas.stroke_started.emit();ui.paint(Vector2i(6,5),false);ui.paint(Vector2i(8,5),false);ui.canvas.stroke_finished.emit()
	check(Pack.secret_trigger(ui.current().secret) == "fire" and ui.undo_stack.size() == 1,"Secret brush paints selected trigger as one stroke")
	ui.undo()
	var wall: String = ui.current().tiles[5];ui.current().tiles[5] = wall.left(6)+"#"+wall.substr(7)
	ui.apply_block(Fixture.sample().rooms[0].secret)
	check(ui.current().tiles[5][6] == "." and ui.undo_stack.size() == 1,"Destructible wall placement creates floor under its solid overlay")
	ui.undo();check(ui.current().tiles[5][6] == "#","Undo restores the original painted wall")
	ui.replace_pack(JSON.parse_string(JSON.stringify(Fixture.sample())),"",false)
	ui.apply_block(ui.current().secret.duplicate(true));check(not ui.dirty() and ui.undo_stack.is_empty(),"Unchanged secret Apply is JSON-safe")
	var catalog := Fixture.catalog()
	# Capture preserves new trigger data; generation uses a distinct identity.
	var captured := Templates.capture(Templates.defaults(),Fixture.sample(),"entry","bomb_room","key",Pack.EDGES,[])
	check(captured.errors.is_empty() and captured.catalog.templates[-1].room.secret.trigger == "bomb","Template capture retains destructible secrets")

	var generated := Generator.new().generate(catalog,42,6)
	check(generated.errors.is_empty() and generated.pack.generation.version == 4 and generated.pack.id.begins_with("generated_v4_"),"Destructible libraries get versioned recipes and identities")
	check(Pack.write("/tmp/zelda-destructible-templates.json",catalog) == OK,"Template example writes")
	check(Pack.write("/tmp/zelda-fire-route.json",Fixture.gifted_candle()) == OK,"Fire example writes")
	check(Pack.write("/tmp/zelda-bomb-route.json",Fixture.revisit()) == OK,"Example writes")
	ui.queue_free();await process_frame
	print("Destructible secret editor checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
