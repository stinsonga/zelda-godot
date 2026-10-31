extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Fixture = preload("door_group_fixture.gd")
const Bindings = preload("../shared/art_bindings.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(100).timeout.connect(func(): push_error("Door-group checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var source := Fixture.source();var before := source.duplicate(true)
	var catalog := Fixture.catalog()
	if catalog.has("errors"): push_error(str(catalog.errors));quit(1);return
	check(catalog.format_version==3 and Templates.validate(catalog).is_empty(),"Door-connected library validates as format 3")
	var capture := Templates.capture(Templates.defaults(),source,"entry","suite","key",["up","down","left"],[],false,"side",[120,77],["side"])
	check(capture.errors.is_empty() and source==before,"Capture preserves source and explicit internal doors")
	var entry: Dictionary = capture.catalog.templates[-1]
	var a := Templates.instantiate(entry,"a");var b := Templates.instantiate(entry,"b")
	check(a.primary.connections.right.target=="a_part_1" and a.annexes[0].connections.left.target=="a","Reciprocal internal targets use per-occurrence IDs")
	check(a.reward_room.id=="a_part_1" and b.reward_room.id=="b_part_1","Rewards target their own companion")
	a.annexes[0].pickups.append({"id":"changed"})
	check(b.annexes[0].pickups.is_empty() and entry.annexes[0].pickups.is_empty(),"Occurrences are independent mutable copies")
	for mode in ["port","dangling","nonadjacent","disconnected","overlap","old_format","malformed_ports"]:
		var bad: Dictionary = capture.catalog.duplicate(true);var unit: Dictionary = bad.templates[-1]
		match mode:
			"port": unit.ports.append("right")
			"dangling": unit.annexes[0].connections.left.target = "missing"
			"nonadjacent": unit.annexes[0].map_position = [3,0]
			"disconnected": unit.room.connections = {};unit.annexes[0].connections = {}
			"overlap": unit.annexes[0].map_position = unit.room.map_position.duplicate()
			"old_format": bad.format_version = 2
			"malformed_ports": unit.ports = null
		check(not Templates.validate(bad).is_empty(),"Reject unsafe group: "+mode)
	check(not Templates.capture(Templates.defaults(),source,"entry","duplicate","key",["up"],[],false,"",[120,77],["side","side"]).errors.is_empty(),"Duplicate explicit membership fails clearly")
	var art_source := Fixture.source();art_source.appearance = Bindings.fresh()
	var indices: Array = [];indices.resize(176);indices.fill(-1)
	art_source.appearance.room_tiles.side = {"atlas":"art/test_art/tiles","indices":indices}
	art_source.appearance.enemy_sprites.crawler = "art/test_art/beast"
	var skinned := Templates.capture(Templates.defaults(),art_source,"entry","skin_suite","key",["up","down","left"],[],false,"side",[120,77],["side"])
	check(skinned.errors.is_empty() and skinned.catalog.format_version==3,"Capturing authored art does not downgrade door-group format")
	if skinned.errors.is_empty():
		var skin := Templates.instantiate(skinned.catalog.templates[-1],"skin")
		check(skin.appearance.room_tiles.has("skin_part_1") and skin.appearance.enemy_sprites.has(skin.annexes[0].enemies[0].type),"Companion artwork and scoped enemy skins follow instance IDs")
	var outside := Pack.room("outside");outside.map_position = [6,-7];source.rooms.append(outside)
	source.rooms[0].connections.left = {"target":"outside","kind":"open"};outside.connections.right = {"target":"entry","kind":"open"}
	var bounded := Templates.capture(Templates.defaults(),source,"entry","bounded","key",["up","down","left"],[],false,"side",[120,77],["side"])
	check(bounded.errors.is_empty() and not bounded.catalog.templates[-1].room.connections.has("left"),"Explicit capture strips outside doors instead of following the whole dungeon")
	var mixed := Fixture.source();var cellar := Pack.cellar("cellar");cellar.map_position = [9,-7]
	mixed.rooms[1].stairs = [{"id":"down","cell":[7,4],"target":"cellar","target_position":[120,125]}]
	cellar.stairs = [{"id":"back","cell":[3,3],"target":"side","target_position":[120,125]}];mixed.rooms.append(cellar)
	check(not Templates.capture(Templates.defaults(),mixed,"entry","mixed_bad","key",["up","down","left"],[],false,"cellar",[120,125],["side"]).errors.is_empty(),"Stair closure cannot be silently omitted")
	var group := Templates.capture(Templates.defaults(),mixed,"entry","mixed","key",["up","down","left"],[],true,"cellar",[120,125],["side"])
	check(group.errors.is_empty() and group.catalog.templates[-1].annexes.size()==2,"Door groups may include linked cellar closure")
	if group.errors.is_empty():
		var unit := Templates.instantiate(group.catalog.templates[-1],"mixed")
		check(unit.primary.connections.right.target.begins_with("mixed_part_") and unit.reward_room.id.begins_with("mixed_cellar_"),"Mixed doors, stairs and rewards remap together")
	var shipped := Templates.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/templates/door_templates.json"))
	check(shipped.errors.is_empty() and Templates.fingerprint(shipped.catalog)==Templates.fingerprint(catalog),"Shipped door library matches the checked fixtures")
	var square := Fixture.source()
	var top := Pack.room("top");top.map_position = [7,-8]
	var corner := Pack.room("corner");corner.map_position = [8,-8]
	square.rooms.append(top);square.rooms.append(corner)
	for pair in [[square.rooms[0],top,"up"],[top,corner,"right"],[corner,square.rooms[1],"down"]]:
		pair[0].connections[pair[2]] = {"target":pair[1].id,"kind":"open"}
		pair[1].connections[Pack.OPPOSITE[pair[2]]] = {"target":pair[0].id,"kind":"open"}
	var full := Templates.capture(Templates.defaults(),square,"entry","square","key",["down","left"],[],false,"corner",[120,77],["side","top","corner"])
	check(full.errors.is_empty() and full.catalog.templates[-1].annexes.size()==3,"Four-room units preserve cyclic internal door networks")
	var extra := Pack.room("extra");extra.map_position = [9,-8];square.rooms.append(extra)
	check(not Templates.capture(Templates.defaults(),square,"entry","too_many","key",["down"],[],false,"",[120,77],["side","top","corner","extra"]).errors.is_empty(),"Capture enforces the four-room bound")
	var first: Dictionary = {}
	for recipe in [[42,6,{}],[7,8,{}],[42,8,{"branch_rooms":2,"loop_count":1}]]:
		var generated := Generator.new().generate(catalog,recipe[0],recipe[1],"blue_candle",6000,recipe[2])
		check(generated.errors.is_empty(),"Door-group recipe verifies: "+str(recipe)+" "+str(generated.errors))
		if not generated.has("pack"): continue
		if first.is_empty(): first = generated
		check(generated.pack.generation.version==6 and generated.pack.rooms.size()==recipe[1]+2,"New recipes isolate identity and expand both groups")
		check(Pack.validate(JSON.parse_string(JSON.stringify(generated.pack))).is_empty(),"Generated version-6 recipe survives JSON number conversion")
		check(Pack.validate(generated.pack).is_empty() and Pack.layout_warnings(generated.pack).is_empty(),"Footprints stay adjacent, in bounds and collision-free")
		check(generated.pack.goals.any(func(goal): return goal.room.contains("_part_")),"Objective belongs to actual reward companion")
		check(generated.proof.events.any(func(e): return e.type=="door" and generated.pack.rooms.filter(func(room): return room.id==e.room)[0].connections[e.edge].target.contains("_part_")),"Proof includes internal key spending")
	if not first.is_empty():
		var replayed := Generator.new().generate(JSON.parse_string(JSON.stringify(catalog)),42,6)
		check(replayed.errors.is_empty() and Templates.canonical(replayed.pack)==Templates.canonical(first.pack),"JSON reload reproduces identical expanded content and identity")
	var trapped := catalog.duplicate(true)
	for unit in trapped.templates:
		if unit.role=="goal": unit.annexes[0].connections.values()[0].requires = ["recorder"];unit.room.connections.values()[0].requires = ["recorder"]
	check(not Generator.new().generate(trapped,42,6).errors.is_empty(),"Solver rejects internal dependencies with no available item")
	var gen := Generator.new()
	check(not gen.footprint_fits(entry,Vector2i(15,0),[]) and not gen.footprint_fits(entry,Vector2i(7,-7),[Vector2i(8,-7)]),"Footprint selection rejects bounds and occupied cells")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui);ui.replace_pack(Fixture.source(),"",false);ui.open_dungeon_tools(1)
	var dialog = ui.dungeon_tools
	dialog.companion_rooms.select(0);dialog.companion_rooms.multi_selected.emit(0,true)
	check(dialog.selected_companions()==["side"] and dialog.reward_room.item_count==2,"GUI exposes explicit membership and reward choices")
	check(dialog.capture_preview.rooms.size()==2 and dialog.capture_preview.primary=="entry" and "right" not in dialog.capture_preview.ports,"Preview shows captured membership and only available external ports")
	dialog.port_checks[0].button_pressed = false
	check("up" not in dialog.capture_preview.ports,"Preview responds to external port changes")
	dialog.port_checks[0].button_pressed = true
	check(dialog.port_checks[1].disabled and not dialog.port_checks[1].button_pressed,"GUI prevents external port from overwriting internal door")
	dialog.custom_reward.button_pressed = true
	for i in dialog.reward_room.item_count:
		if dialog.reward_room.get_item_text(i)=="side": dialog.reward_room.select(i);dialog.reward_room.item_selected.emit(i)
	check(dialog.capture_preview.reward=="side","Preview marks the chosen reward room")
	dialog.capture_preview.size = Vector2(600,190)
	var cells: Dictionary = dialog.capture_preview.cells()
	check(cells.size()==2 and not cells.entry.intersects(cells.side) and Rect2(Vector2.ZERO,dialog.capture_preview.size).encloses(cells.side),"Preview lays out distinct rooms inside its bounds")
	check(dialog.capture_preview._get_tooltip(cells.entry.get_center()).contains("right → side"),"Preview exposes full IDs and internal connection details")
	dialog.companion_ports_edit.text = "side: up, down";dialog.companion_ports_edit.text_changed.emit(dialog.companion_ports_edit.text)
	check(dialog.capture_preview.companion_ports == {"side":["up","down"]},"Preview shows companion ports as typed")
	dialog.mirror_checks[0].button_pressed = true
	dialog.stair_check.button_pressed = true;dialog.stair_x.value = 6
	dialog.template_id.text = "gui_suite";dialog.role.select(1);dialog.picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	var filename := "/tmp/zelda-door-template-%d.json" % OS.get_process_id();dialog.file_selected(filename)
	var saved := Templates.read(filename)
	check(saved.errors.is_empty() and saved.catalog.format_version==3 and saved.catalog.templates[-1].reward.room=="side","GUI saves a reusable door-connected template")
	check(saved.errors.is_empty() and saved.catalog.templates[-1].companion_ports == {"side":["up","down"]} and saved.catalog.templates[-1].mirrors == ["horizontal"] and saved.catalog.templates[-1].stair_cell.map(func(v): return int(v)) == [6,4],"GUI saves companion ports, mirrors and the stair cell")
	DirAccess.remove_absolute(filename)
	dialog.size = dialog.min_size;await process_frame;await process_frame;dialog.layout_content()
	check(dialog.content.position.y+dialog.content.size.y<=dialog.size.y-40,"Capture remains usable at minimum dialog size")
	check(Pack.write("/tmp/zelda-door-templates.json",catalog)==OK,"ROM-free demonstration library writes")
	ui.queue_free();await process_frame
	print("Door-connected template checks: ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)
