extends SceneTree
const Pack = preload("../shared/room_pack.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; push_error(text)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Editor tests timed out"); quit(1))
	call_deferred("run")
func run() -> void:
	var sample := Pack.sample()
	check(Pack.validate(sample).is_empty(),"Authored sample must validate")
	var broken := sample.duplicate(true)
	broken.rooms[0].connections.up.target = "missing"
	check(not Pack.validate(broken).is_empty(),"Missing destinations must fail")
	broken = sample.duplicate(true)
	broken.rooms[1].connections.down.kind = "open"
	check(not Pack.validate(broken).is_empty(),"Mismatched reverse door must fail")
	broken = sample.duplicate(true)
	broken.rooms[0].tiles[8] = "################"
	check(not Pack.validate(broken).is_empty(),"Blocked spawn must fail")
	broken = sample.duplicate(true)
	broken.enemy_types.crawler.script = "res://anything.gd"
	check(not Pack.validate(broken).is_empty(),"Unknown executable/resource fields must fail")
	broken = sample.duplicate(true)
	broken.rooms[0].pickups[0].item = "../../imported/item"
	check(not Pack.validate(broken).is_empty(),"Pickup paths must not be accepted")
	broken = sample.duplicate(true)
	broken.rooms[1].map_position = [0,0]
	check(not Pack.validate(broken).is_empty(),"Map collisions must fail")
	for malformed in [null,[],{}, {"schema":1,"rooms":[{},null,42]}, {"schema":1,"rooms":[{"id":"x","connections":{"up":null}}]}]:
		check(not Pack.validate(malformed).is_empty(),"Malformed input must return errors")
	var filename := "/tmp/zelda-editor-test-roundtrip.json"
	check(Pack.write(filename,sample) == OK,"Atomic save must succeed")
	var loaded := Pack.read(filename)
	check(loaded.errors.is_empty() and loaded.pack == JSON.parse_string(JSON.stringify(sample)),"Save/load must preserve pack data")
	# Real UI methods: one stroke/undo, reciprocal rewire/undo, variant editing,
	# duplicate/delete, and a saved pack that is subsequently played by the game.
	var ui = preload("../ui/main.tscn").instantiate()
	root.add_child(ui)
	ui.replace_pack(sample,"",false)
	ui.importer.popup_centered()
	await process_frame
	await process_frame
	ui.importer.layout_content()
	check(ui.importer.content.position.y + ui.importer.content.size.y <= ui.importer.size.y - 40,"Import dialog reserves visible space for Close")
	ui.importer.hide()
	ui.selected_tool = "Water"
	var before: Dictionary = ui.pack.duplicate(true)
	ui.paint(Vector2i(3,3),false)
	ui.paint(Vector2i(4,3),false)
	ui.commit(before)
	check(ui.undo_stack.size() == 1 and ui.current().tiles[3][3] == "~","Brush stroke must be one undo action")
	ui.undo()
	check(ui.pack == sample,"Undo restores exact authored content")
	ui.redo()
	check(ui.current().tiles[3][4] == "~","Redo restores full stroke")
	ui.undo()
	ui.pick(ui.edge,"right")
	ui.pick(ui.destination,"vault")
	ui.pick(ui.door_kind,"bombable")
	ui.connect_rooms()
	check(ui.current().connections.right.target == "vault","Connection points to selected room")
	check(ui.find_room("vault").connections.left.target == "entry","Connection updates both sides")
	check(not ui.find_room("hall").connections.has("right"),"Rewiring removes old reciprocal side")
	check(Pack.validate(ui.pack).is_empty(),"Rewired dungeon validates")
	ui.undo()
	check(ui.pack == sample,"Undo restores displaced connections")
	ui.health.value = 4
	ui.apply_enemy()
	check(ui.pack.enemy_types.crawler.health == 4,"Enemy inspector changes variant")
	ui.undo()
	ui.duplicate_enemy()
	check(ui.pack.enemy_types.size() == 2,"Enemy variant duplication")
	ui.selected_tool = "Enemy"
	before = ui.pack.duplicate(true)
	ui.paint(Vector2i(6,5),false)
	ui.commit(before)
	check(ui.current().enemies[0].type == "variant_1","Enemy brush uses duplicated variant")
	ui.undo()
	ui.undo()
	ui.duplicate_room()
	check(ui.pack.rooms.size() == 4 and ui.current().connections.is_empty(),"Copied room has fresh identity and no links")
	ui.delete_room()
	check(ui.pack.rooms.size() == 3,"Delete removes copied room")
	ui.replace_pack(sample,"",false)
	ui.current_id = "hall"
	ui.refresh()
	ui.delete_room()
	check(Pack.validate(ui.pack).is_empty() and ui.find_room("entry").connections.is_empty(),"Delete removes incoming links")
	ui.undo()
	check(ui.pack == sample,"Undo delete restores all links")
	ui.replace_pack(sample,"",false)
	check(ui.forbidden_destination(ui.game_root.path_join("imported/test.json")),"ROM import directory cannot be a save destination")
	check(ui.save_to("/tmp/zelda-editor-playable.json"),"Editor saves playable pack")
	check(not ui.dirty(),"Saving clears dirty flag")
	ui.pack_title.text = "Edited title"
	ui.pack_id.text = "my_unique_pack"
	ui.flush_text_edits()
	check(ui.pack.title == "Edited title" and ui.pack.id == "my_unique_pack" and ui.dirty(),"Pending text edits are committed before saving or closing")

	ui.replace_pack(sample,"",false)
	check(Pack.layout_warnings(ui.pack).is_empty(),"Sample graph is adjacent and potentially connected")
	ui.dungeon_map.size = Vector2(800,600)
	ui.dungeon_map.fit_to_rooms()
	var hall_center: Vector2 = ui.dungeon_map.center(ui.find_room("hall"))
	check(ui.dungeon_map.cell_at(hall_center) == Vector2i(0,-1),"Map screen/cell transform preserves negative Y")
	var press := InputEventMouseButton.new()
	press.position = hall_center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	ui.dungeon_map._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = hall_center + ui.dungeon_map.cell_size * Vector2(2,0)
	ui.dungeon_map._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	ui.dungeon_map._input(release)
	check(ui.current_id == "hall" and ui.find_room("hall").map_position == [2,-1],"Map click selects and drag moves room")
	check(ui.undo_stack.size() == 1,"A map drag is one undo step")
	check(not Pack.layout_warnings(ui.pack).is_empty(),"Moved links generate layout warnings")
	ui.undo()
	check(ui.pack == sample,"Undo map drag restores exact graph")
	ui.redo()
	check(ui.find_room("hall").map_position == [2,-1],"Redo map drag restores position")
	ui.undo()
	ui.move_room("hall",Vector2i(0,0))
	check(ui.pack == sample and ui.undo_stack.is_empty(),"Occupied cells reject movement without losing content or adding history")
	ui.move_room("hall",Vector2i(-1,-1))
	check(ui.pack == sample,"Out-of-map drag rejected")
	ui.select_room("entry")
	ui.pick(ui.adjacent_edge,"right")
	ui.pick(ui.adjacent_kind,"bombable")
	ui.add_adjacent_room()
	var new_id: String = ui.current_id
	check(ui.pack.rooms.size() == 4 and ui.current().map_position == [1,0],"Adjacent room gets matching grid location")
	check(ui.find_room("entry").connections.right.target == new_id and ui.current().connections.left.kind == "bombable","Adjacent room makes matching reciprocal doors")
	check(Pack.validate(ui.pack).is_empty() and Pack.layout_warnings(ui.pack).is_empty(),"Adjacent-room layout validates with no warnings")
	ui.undo()
	check(ui.pack == sample,"Undo adjacent creation removes both room and connections")
	ui.select_room("entry")
	ui.pick(ui.edge,"up")
	ui.disconnect_room() # Removes the selected up connection to hall.
	check(not Pack.layout_warnings(ui.pack).is_empty(),"Disconnected branch is identified")
	ui.pick(ui.adjacent_edge,"up")
	ui.pick(ui.adjacent_kind,"key")
	ui.connect_neighbour()
	check(Pack.layout_warnings(ui.pack).is_empty() and ui.pack == sample,"Connect neighbour restores both door sides")
	ui.selected_map_cell = Vector2i(3,-3)
	ui.add_at_selected_cell()
	check(ui.current().map_position == [3,-3] and ui.current().connections.is_empty(),"Create at empty map cell keeps connections explicit")
	check(Pack.layout_warnings(ui.pack).size() == 1,"Isolated room produces a connectivity warning")
	ui.undo()
	ui.replace_pack(sample,"",false)
	ui.find_room("entry").connections.up.kind = "wall"
	ui.find_room("hall").connections.down.kind = "wall"
	check(Pack.layout_warnings(ui.pack).size() == 2,"Wall doors do not count as potential paths")
	ui.replace_pack(sample,"",false)
	var roundtrip := Pack.read(filename)
	check(Pack.layout_warnings(roundtrip.pack).is_empty(),"Layout checks accept JSON floating-point coordinates")

	var fixture := "/tmp/zelda-editor-image-library-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(fixture.path_join("imported"))
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	image.save_png(fixture.path_join("imported/test.png"))
	var catalog := {"format_version":1,"source":{"prg_sha1":"a12d74c73a0481599a5d832361d168f4737bbcf6"},"entries":[{"id":"rom/us_prg0/test","name":"Test monster","path":"test.png","category":"sprites","width":16,"height":16}]}
	Pack.write(fixture.path_join("imported/editor_catalog.json"),catalog)
	ui.asset_library.load_catalog(fixture)
	check(ui.asset_library.entries.size() == 1,"Optional image catalog loads without game resource scripts")
	ui.asset_library.select_image(0)
	check(ui.asset_library.preview.texture != null and ui.asset_library.preview.texture.get_width() == 16,"Browser decodes raw PNG thumbnails")
	ui.asset_library.search.text = "no match"
	ui.asset_library.populate()
	check(ui.asset_library.shown.is_empty(),"Image browser filter works")
	ui.asset_library.search.text = ""
	catalog.entries[0].path = "../outside.png"
	Pack.write(fixture.path_join("imported/editor_catalog.json"),catalog)
	ui.asset_library.load_catalog(fixture)
	check(ui.asset_library.entries.is_empty() and ui.asset_library.summary.text.contains("Invalid"),"Catalog path traversal rejected")
	DirAccess.remove_absolute(fixture.path_join("imported/editor_catalog.json"))
	ui.asset_library.load_catalog(fixture)
	check(ui.asset_library.entries.is_empty() and ui.asset_library.summary.text.contains("No graphics libraries"),"Missing import has a usable empty state")
	DirAccess.remove_absolute(fixture.path_join("imported/test.png"))
	DirAccess.remove_absolute(fixture.path_join("imported"))
	DirAccess.remove_absolute(fixture)
	var args := OS.get_cmdline_user_args()
	if "--write-sample" in args:
		var i := args.find("--write-sample")
		check(Pack.write(args[i+1],sample) == OK,"Write shared hand-authored fixture")
	ui.free()
	print("Editor checks: ","PASS" if failures == 0 else "FAIL", " (contract, persistence, undo, connections, variants)")
	quit(0 if failures == 0 else 1)
