extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Fixture = preload("template_fixture.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("Multi-room template checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var legacy := Generator.new().generate(Templates.defaults(),42,8)
	check(legacy.errors.is_empty() and Templates.canonical(legacy.pack).sha256_text() == "bb718773940a65f36a70141eb3acb14499151a4c839d32f0e11035acb91d7d0f","Version-1 seed 42 recipe stays identical to the pre-unit generator")
	var source := Fixture.source()
	var original := source.duplicate(true)
	var catalog := Fixture.catalog()
	check(not catalog.has("capture_errors") and Templates.validate(catalog).is_empty(),"Linked-cellar catalog validates")
	if catalog.has("capture_errors"): quit(1);return
	var shipped := Templates.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/templates/cellar_templates.json"))
	check(shipped.errors.is_empty() and Templates.fingerprint(shipped.catalog) == Templates.fingerprint(catalog),"Shipped cellar library matches the tested authored units")
	check(catalog.format_version == 2 and catalog.enemy_types.crawler.health == 2,"Unit capture preserves older enemy definitions and upgrades library")
	check(source == original,"Capture never mutates source pack")
	var entry: Dictionary = catalog.templates[-1]
	check(entry.room.connections.is_empty() and entry.annexes.size() == 1,"Capture strips external doors and preserves linked cellar")
	check(entry.annexes[0].enemies[0].type != "crawler","Annex enemy definitions are namespaced")
	var a := Templates.instantiate(entry,"room_a")
	var b := Templates.instantiate(entry,"room_b")
	check(a.primary.stairs[0].target == "room_a_cellar_1" and a.annexes[0].stairs[0].target == "room_a","Every internal stair target remaps to its own instance")
	check(a.reward_room.id == "room_a_cellar_1" and b.reward_room.id == "room_b_cellar_1","Each occurrence has its own reward room")
	a.annexes[0].pickups.append({"id":"x"})
	check(b.annexes[0].pickups.is_empty() and entry.annexes[0].pickups.is_empty(),"Instantiated mutable rooms do not alias each other or library")
	for invalid_kind in ["missing_annex","external_link","bad_reward","bad_kind","disconnected"]:
		var broken := catalog.duplicate(true)
		var unit: Dictionary = broken.templates[-1]
		match invalid_kind:
			"missing_annex": unit.annexes = []
			"external_link": unit.annexes[0].stairs[0].target = "outside"
			"bad_reward": unit.reward.position = [64,64]
			"bad_kind": unit.annexes[0].kind = "dungeon"
			"disconnected": unit.room.stairs = []
		check(not Templates.validate(broken).is_empty(),"Reject invalid unit: "+invalid_kind)
	var external := Fixture.source();external.rooms[1].kind = "dungeon"
	check(not Templates.capture(Templates.defaults(),external,"entry","bad","key",Pack.EDGES,[],true).errors.is_empty(),"Capture refuses external main-room traversal")
	var first: Dictionary = {}
	for recipe in [[42,6],[7,8],[91,6]]:
		var generated := Generator.new().generate(catalog,recipe[0],recipe[1])
		check(generated.errors.is_empty(),"Unit recipe generates and verifies: "+str(recipe))
		if not generated.has("pack"): print(generated);continue
		if first.is_empty(): first = generated
		check(generated.pack.generation.version == 2 and generated.pack.generation.room_count == recipe[1],"Version 2 recipe records primary room count")
		check(generated.pack.rooms.size() == recipe[1]+2 and Pack.validate(generated.pack).is_empty(),"Two cellar units expand with unique map positions")
		check(generated.proof.events.filter(func(e): return e.type == "stairs").size() >= 3,"Progression must enter key cellar, return, and enter goal cellar")
		check(generated.pack.goals.any(func(goal): return goal.room.contains("_cellar_")),"Generated goal targets the actual cellar reward")
		for room in generated.pack.rooms:
			for stair in room.get("stairs",[]):
				check(stair.target.get_slice("_cellar_",0) == room.id.get_slice("_cellar_",0),"Stairs never cross between template occurrences")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(catalog))
	check(Templates.fingerprint(parsed) == Templates.fingerprint(catalog),"Mixed String/StringName keys have JSON-stable fingerprints")
	var repeated := Generator.new().generate(parsed,42,6)
	check(not first.is_empty() and repeated.errors.is_empty() and Templates.canonical(first.pack) == Templates.canonical(repeated.pack),"JSON library reproduces same expanded dungeon")
	var dead_end := catalog.duplicate(true)
	for unit in dead_end.templates:
		if unit.role == "key": unit.annexes[0].stairs = []
	check(not Generator.new().generate(dead_end,42,6).errors.is_empty(),"Cannot certify a key trapped in a cellar without a return route")
	var nested := Fixture.nested_catalog()
	check(not nested.has("capture_errors") and Templates.validate(nested).is_empty(),"Capture follows nested cellar links")
	var nested_generated := Generator.new().generate(nested,42,6)
	check(nested_generated.errors.is_empty() and nested_generated.pack.rooms.size() == 9,"Nested units expand and verify through the deepest reward")
	var capped := catalog.duplicate(true)
	var large_unit: Dictionary = capped.templates[-1].duplicate(true)
	for i in range(2):
		var annex: Dictionary = large_unit.annexes[0].duplicate(true)
		annex.id = "extra_"+str(i);annex.map_position = [i+2,0]
		large_unit.annexes.append(annex)
		large_unit.room.stairs.append({"id":"extra_"+str(i),"cell":[4+i*6,3],"target":annex.id,"target_position":[48,61]})
	capped.templates = []
	for role in Templates.ROLES:
		var unit := large_unit.duplicate(true);unit.id = "cap_"+role;unit.role = role;capped.templates.append(unit)
	check(Templates.validate(capped).is_empty(),"Three-annex units validate independently")
	var expanded := Templates.instantiate(capped.templates[0],"three")
	check(expanded.annexes.size() == 3 and expanded.primary.stairs.all(func(stair): return stair.target.begins_with("three_cellar_")),"All three annex destinations remap correctly")
	var oversized := Generator.new().generate(capped,42,16)
	check(not oversized.errors.is_empty() and "32-room" in " ".join(oversized.errors),"Expanded units cannot exceed solver's 32-room limit")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(Fixture.source(),"",false);ui.open_dungeon_tools(1)
	var dialog = ui.dungeon_tools
	check(dialog.include_linked.button_pressed and dialog.reward_room.item_count == 2,"Template GUI discovers linked cellar capture choices")
	dialog.custom_reward.button_pressed = true
	for i in dialog.reward_room.item_count:
		if dialog.reward_room.get_item_text(i) == "cellar": dialog.reward_room.select(i);dialog.reward_room.item_selected.emit(i)
	check(dialog.reward_y.value == 125,"Choosing cellar uses its walkable spawn as initial reward position")
	dialog.template_id.text = "gui_cellar";dialog.role.select(1)
	dialog.picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	var filename := "/tmp/zelda-unit-template-%d.json" % OS.get_process_id()
	dialog.file_selected(filename)
	var saved := Templates.read(filename)
	check(saved.errors.is_empty() and saved.catalog.templates[-1].reward.room == "cellar","GUI persists a reusable cellar unit and reward location")
	dialog.catalog_path.text = ui.game_root.path_join("content/templates/dungeon_templates.json")
	dialog.template_id.text = "gui_cellar_second"
	dialog.file_selected(filename.trim_suffix(".json"))
	var appended := Templates.read(filename)
	check(appended.errors.is_empty() and appended.catalog.templates.size() == saved.catalog.templates.size()+1,"Saving without extension appends to the existing target library")
	await process_frame;await process_frame;dialog.layout_content()
	check(dialog.content.position.y+dialog.content.size.y<=dialog.size.y-40,"Expanded capture controls reserve space for Close")
	DirAccess.remove_absolute(filename)
	dialog.size = dialog.min_size
	await process_frame;await process_frame;dialog.layout_content()
	check(dialog.content.position.y+dialog.content.size.y<=dialog.size.y-40,"Capture controls fit at minimum dialog size")
	check(Pack.write("/tmp/zelda-cellar-templates.json",catalog) == OK,"Example library writes")
	ui.queue_free();await process_frame
	print("Multi-room template checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
