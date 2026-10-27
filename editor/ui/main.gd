extends Control
const Pack = preload("../shared/room_pack.gd")
const Canvas = preload("room_canvas.gd")
const DungeonMap = preload("dungeon_map.gd")
const AssetLibrary = preload("asset_library.gd")
const ImportDialog = preload("import_dialog.gd")
var pack: Dictionary = Pack.sample()
var current_id := "entry"
var path := ""
var saved_text := ""
var undo_stack: Array = []
var redo_stack: Array = []
var stroke_before: Dictionary = {}
var selected_tool := "Floor"
var syncing := false
var pending_action: Callable
var preview_pids: Array[int] = []
var game_root := ""
var importer: AcceptDialog
var asset_library: Control
var rooms_list: ItemList
var canvas: Control
var dungeon_map: Control
var views: TabContainer
var adjacent_kind: OptionButton
var adjacent_edge: OptionButton
var selected_map_cell := Vector2i(-1,1)
var status: RichTextLabel
var title_edit: LineEdit
var pack_id: LineEdit
var pack_title: LineEdit
var start_button: Button
var enemy_type: OptionButton
var item_type: OptionButton
var enemy_behavior: OptionButton
var health: SpinBox
var speed: SpinBox
var damage: SpinBox
var edge: OptionButton
var destination: OptionButton
var door_kind: OptionButton
var shutter: CheckBox
var map_x: SpinBox
var map_y: SpinBox
var undo_button: Button
var redo_button: Button
var file_dialog: FileDialog
var confirmation: ConfirmationDialog
var heading: Label

func _ready() -> void:
	game_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	get_tree().auto_accept_quit = false
	build_ui()
	saved_text = JSON.stringify(pack)
	refresh()
	validate_pack()
	# Used by integration checks and visual QA; normal launch stays interactive.
	var args := OS.get_cmdline_user_args()
	if "--screenshot" in args:
		if "--assets" in args: views.current_tab = 2
		if "--import-dialog" in args: importer.popup_centered()
		if "--map" in args:
			views.current_tab = 1
			dungeon_map.fit_to_rooms()
		await RenderingServer.frame_post_draw
		var i := args.find("--screenshot")
		get_viewport().get_texture().get_image().save_png(args[i+1])
		get_tree().quit()

func label(text: String, parent: Node) -> Label:
	var node := Label.new()
	node.text = text
	parent.add_child(node)
	return node
func button(text: String, parent: Node, action: Callable) -> Button:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	parent.add_child(node)
	return node
func options(values: Array, parent: Node) -> OptionButton:
	var node := OptionButton.new()
	for value in values: node.add_item(str(value))
	parent.add_child(node)
	return node
func number(text: String, parent: Node, low: int, high: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var caption := label(text,row)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var node := SpinBox.new()
	node.min_value = low
	node.max_value = high
	node.custom_minimum_size.x = 115
	row.add_child(node)
	return node
func section(text: String, parent: Node) -> void:
	var separator := HSeparator.new()
	parent.add_child(separator)
	var node := label(text,parent)
	node.add_theme_color_override("font_color",Color("86d1ad"))
func build_ui() -> void:
	var theme := Theme.new()
	theme.default_font_size = 15
	self.theme = theme
	var background := ColorRect.new()
	background.color = Color("18232e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side,14)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",10)
	margin.add_child(layout)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	button("Import ROM…",toolbar,func(): importer.popup_centered())
	button("New",toolbar,func(): request_action(func(): replace_pack(Pack.fresh(),"")))
	button("Example",toolbar,func(): request_action(func(): replace_pack(Pack.sample(),"")))
	button("Open…",toolbar,func(): request_action(show_open))
	button("Save",toolbar,save)
	button("Save as…",toolbar,show_save)
	undo_button = button("Undo",toolbar,undo)
	redo_button = button("Redo",toolbar,redo)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	button("Validate",toolbar,validate_pack)
	button("Play room",toolbar,func(): playtest(true))
	button("Play dungeon",toolbar,func(): playtest(false))
	heading = label("",layout)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",14)
	layout.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 190
	body.add_child(left)
	label("DUNGEON",left)
	pack_title = LineEdit.new()
	left.add_child(pack_title)
	pack_title.text_submitted.connect(func(text): edit(func(): pack.title = text))
	pack_title.focus_exited.connect(func():
		if not syncing and pack_title.text != pack.title: edit(func(): pack.title = pack_title.text))
	pack_title.tooltip_text = "Press Enter to apply the dungeon title"
	label("Pack ID (stable identity)",left)
	pack_id = LineEdit.new()
	left.add_child(pack_id)
	pack_id.text_submitted.connect(func(text): edit(func(): pack.id = text))
	pack_id.focus_exited.connect(func():
		if not syncing and pack_id.text != pack.id: edit(func(): pack.id = pack_id.text))
	pack_id.tooltip_text = "Lowercase letters, numbers, underscores and hyphens. Changing this creates a new world identity."
	rooms_list = ItemList.new()
	rooms_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(rooms_list)
	rooms_list.item_selected.connect(func(index): select_room(pack.rooms[index].id))
	var room_buttons := HBoxContainer.new()
	left.add_child(room_buttons)
	button("+ Room",room_buttons,add_room)
	button("Copy",room_buttons,duplicate_room)
	button("Delete room",left,func():
		if pack.rooms.size() <= 1: message("Keep at least one room."); return
		confirmation.dialog_text = "Delete this room and its incoming connections? Undo will restore it."
		pending_action = delete_room
		confirmation.popup_centered())
	start_button = button("Make starting room",left,func(): edit(func(): pack.start_room = current_id))
	label("S = spawn  •  E = enemy\nGold = pickup\nRight-click erases entities",left)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	views = TabContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(views)
	var room_view := VBoxContainer.new()
	room_view.name = "Room"
	views.add_child(room_view)
	var tools := HBoxContainer.new()
	room_view.add_child(tools)
	var group := ButtonGroup.new()
	for name in ["Floor","Wall","Water","Spawn","Enemy","Pickup","Erase"]:
		var tool := button(name,tools,func(): selected_tool = name)
		tool.toggle_mode = true
		tool.button_group = group
		tool.button_pressed = name == selected_tool
	canvas = Canvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_view.add_child(canvas)
	canvas.stroke_started.connect(func(): stroke_before = pack.duplicate(true))
	canvas.cell_clicked.connect(paint)
	canvas.stroke_finished.connect(func(): commit(stroke_before); stroke_before = {})
	label("Paint with the left mouse button. One drag is one undo step.",room_view)
	var map_view := VBoxContainer.new()
	map_view.name = "Dungeon"
	views.add_child(map_view)
	var map_tools := HFlowContainer.new()
	map_view.add_child(map_tools)
	button("Fit map",map_tools,func(): dungeon_map.fit_to_rooms())
	adjacent_edge = options(Pack.EDGES,map_tools)
	adjacent_kind = options(Pack.KINDS,map_tools)
	button("Add adjacent room",map_tools,add_adjacent_room)
	button("Connect neighbour",map_tools,connect_neighbour)
	button("Add at empty cell",map_tools,add_at_selected_cell)
	dungeon_map = DungeonMap.new()
	dungeon_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.add_child(dungeon_map)
	dungeon_map.room_selected.connect(select_room)
	dungeon_map.room_activated.connect(func(id): select_room(id); views.current_tab = 0)
	dungeon_map.room_moved.connect(move_room)
	dungeon_map.empty_cell_selected.connect(func(cell): selected_map_cell = cell; message("Empty map cell (%d,%d) selected. Use Add at empty cell, or Add adjacent room to create and connect a neighbour." % [cell.x,cell.y]))
	views.tab_changed.connect(func(index):
		if index == 1 and not dungeon_map.fitted: dungeon_map.call_deferred("fit_to_rooms"))
	label("Click to select; double-click to edit. Drag rooms. Wheel zooms; middle-drag pans.",map_view).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label("Green: open  •  Gold: key  •  Red: bombable  •  Purple: shutter  •  Dashed pink: misplaced",map_view).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	asset_library = AssetLibrary.new()
	asset_library.name = "Assets"
	views.add_child(asset_library)
	asset_library.load_catalog(game_root)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 275
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 255
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
	section("ROOM",right)
	title_edit = LineEdit.new()
	right.add_child(title_edit)
	title_edit.text_submitted.connect(func(text): edit(func(): current().title = text))
	title_edit.focus_exited.connect(func():
		if not syncing and title_edit.text != current().title: edit(func(): current().title = title_edit.text))
	title_edit.tooltip_text = "Press Enter to apply the room title"
	map_x = number("Map X",right,0,15)
	map_y = number("Map Y",right,-15,0)
	button("Apply map position",right,func(): move_room(current_id,Vector2i(int(map_x.value),int(map_y.value))))
	shutter = CheckBox.new()
	shutter.text = "Clear enemies opens shutters"
	right.add_child(shutter)
	shutter.toggled.connect(func(value):
		if not syncing: edit(func(): current().shutter_trigger = 1 if value else 0))
	section("ENEMY BRUSH / VARIANT",right)
	enemy_type = options([],right)
	enemy_type.item_selected.connect(func(_index): refresh_enemy())
	enemy_behavior = options(Pack.BEHAVIORS,right)
	health = number("Health",right,1,255)
	speed = number("Speed / 256",right,0,2048)
	damage = number("Half-heart damage",right,0,16)
	button("Apply variant settings",right,apply_enemy)
	button("Duplicate enemy variant",right,duplicate_enemy)
	section("PICKUP BRUSH",right)
	item_type = options(Pack.ITEMS,right)
	section("CONNECT ROOMS",right)
	edge = options(Pack.EDGES,right)
	edge.item_selected.connect(func(_index): refresh_connection())
	destination = options([],right)
	door_kind = options(Pack.KINDS,right)
	button("Connect both sides",right,connect_rooms)
	button("Remove connection",right,disconnect_room)
	label("Doors use the standard opening.\nMatching reverse doors are automatic.\nThis is not a solvability checker.",right)
	status = RichTextLabel.new()
	status.custom_minimum_size.y = 85
	status.scroll_active = true
	layout.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Dungeon packs"])
	file_dialog.file_selected.connect(file_selected)
	add_child(file_dialog)
	confirmation = ConfirmationDialog.new()
	confirmation.confirmed.connect(func():
		var action := pending_action
		pending_action = Callable()
		if action.is_valid(): action.call())
	add_child(confirmation)
	importer = ImportDialog.new()
	importer.game_root = game_root
	add_child(importer)
	importer.progress_changed.connect(message)
	importer.library_changed.connect(func(): asset_library.load_catalog(game_root); views.current_tab = 2)

func current() -> Dictionary:
	for room in pack.rooms:
		if room.id == current_id: return room
	current_id = pack.rooms[0].id
	return pack.rooms[0]
func selected(option: OptionButton) -> String:
	return option.get_item_text(option.selected) if option.selected >= 0 else ""
func pick(option: OptionButton, text: String) -> void:
	for i in range(option.item_count):
		if option.get_item_text(i) == text: option.select(i); return
func refresh() -> void:
	syncing = true
	var room := current()
	var enemy_selection := selected(enemy_type)
	var target_selection := selected(destination)
	rooms_list.clear()
	for r in pack.rooms:
		rooms_list.add_item(("★ " if r.id == pack.start_room else "") + r.title)
		if r.id == current_id: rooms_list.select(rooms_list.item_count-1)
	title_edit.text = room.title
	pack_title.text = pack.title
	pack_id.text = pack.id
	map_x.value = room.map_position[0]
	map_y.value = room.map_position[1]
	shutter.button_pressed = room.shutter_trigger == 1
	start_button.disabled = current_id == pack.start_room
	enemy_type.clear()
	for id in pack.enemy_types: enemy_type.add_item(id)
	pick(enemy_type,enemy_selection)
	destination.clear()
	for r in pack.rooms:
		if r.id != current_id: destination.add_item(r.id)
	pick(destination,target_selection)
	canvas.room = room
	dungeon_map.update_pack(pack,current_id)
	canvas.queue_redraw()
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	heading.text = "%s  /  %s [%s]%s" % [pack.title,room.title,room.id,"  • unsaved" if dirty() else ""]
	get_window().title = "Dungeon Workshop — " + pack.title + (" *" if dirty() else "")
	refresh_enemy()
	refresh_connection()
	syncing = false
func refresh_enemy() -> void:
	if enemy_type.item_count == 0: return
	var enemy: Dictionary = pack.enemy_types[selected(enemy_type)]
	pick(enemy_behavior,enemy.behavior)
	health.value = enemy.health
	speed.value = enemy.speed_subpixels
	damage.value = enemy.contact_damage
func refresh_connection() -> void:
	var link: Dictionary = current().connections.get(selected(edge),{})
	if link.is_empty(): return
	pick(destination,link.target)
	pick(door_kind,link.kind)
func dirty() -> bool: return JSON.stringify(pack) != saved_text
func edit(action: Callable) -> void:
	var before := pack.duplicate(true)
	action.call()
	commit(before)
func commit(before: Dictionary) -> void:
	if before.is_empty() or JSON.stringify(before) == JSON.stringify(pack): return
	undo_stack.append(before)
	if undo_stack.size() > 100: undo_stack.pop_front()
	redo_stack.clear()
	refresh()
	validate_pack()
func undo() -> void:
	if undo_stack.is_empty(): return
	redo_stack.append(pack.duplicate(true))
	pack = undo_stack.pop_back()
	refresh()
	validate_pack()
func redo() -> void:
	if redo_stack.is_empty(): return
	undo_stack.append(pack.duplicate(true))
	pack = redo_stack.pop_back()
	refresh()
	validate_pack()
func paint(cell: Vector2i, erase: bool) -> void:
	var room := current()
	var tool := "Erase" if erase else selected_tool
	if tool in ["Floor","Wall","Water"]:
		var row: String = room.tiles[cell.y]
		room.tiles[cell.y] = row.left(cell.x) + {"Floor":".","Wall":"#","Water":"~"}[tool] + row.substr(cell.x+1)
	elif tool == "Spawn": room.spawn = [cell.x*16,cell.y*16-3]
	elif tool in ["Enemy","Pickup"]:
		var field := "enemies" if tool == "Enemy" else "pickups"
		if (tool == "Enemy" and enemy_type.item_count == 0) or room[field].any(func(e): return placement_cell(e.position) == cell): return
		var entry := {"id":unique_placement_id(room[field],"enemy" if tool == "Enemy" else "item"),"position":[cell.x*16,cell.y*16-3]}
		entry["type" if tool == "Enemy" else "item"] = selected(enemy_type if tool == "Enemy" else item_type)
		room[field].append(entry)
	elif tool == "Erase":
		for field in ["enemies","pickups"]: room[field] = room[field].filter(func(e): return placement_cell(e.position) != cell)
	canvas.queue_redraw()
func placement_cell(at: Array) -> Vector2i: return Vector2i(int(at[0])/16,(int(at[1])+3)/16)
func unique_placement_id(entries: Array, prefix: String) -> String:
	var n := 1
	while entries.any(func(e): return e.id == prefix + "_" + str(n)): n += 1
	return prefix + "_" + str(n)
func unique_room_id() -> String:
	var n := 1
	while pack.rooms.any(func(r): return r.id == "room_" + str(n)): n += 1
	return "room_" + str(n)
func unused_map_position() -> Array:
	for y in range(16):
		for x in range(16):
			if not pack.rooms.any(func(r): return int(r.map_position[0]) == x and int(r.map_position[1]) == -y): return [x,-y]
	return [0,0]
func add_room() -> void:
	if pack.rooms.size() >= 256: message("At most 256 rooms."); return
	edit(func():
		var room := Pack.room(unique_room_id())
		room.map_position = unused_map_position()
		pack.rooms.append(room)
		current_id = room.id)
func duplicate_room() -> void:
	if pack.rooms.size() >= 256: message("At most 256 rooms."); return
	edit(func():
		var room := current().duplicate(true)
		room.id = unique_room_id()
		room.title += " copy"
		room.map_position = unused_map_position()
		room.connections = {}
		pack.rooms.append(room)
		current_id = room.id)
func delete_room() -> void:
	edit(func():
		var removed := current_id
		pack.rooms = pack.rooms.filter(func(r): return r.id != removed)
		for room in pack.rooms:
			for direction in room.connections.keys():
				if room.connections[direction].target == removed: room.connections.erase(direction)
		current_id = pack.rooms[0].id
		if pack.start_room == removed: pack.start_room = current_id)
func apply_enemy() -> void:
	if enemy_type.item_count == 0: return
	edit(func():
		var enemy: Dictionary = pack.enemy_types[selected(enemy_type)]
		enemy.behavior = selected(enemy_behavior)
		enemy.health = int(health.value)
		enemy.speed_subpixels = int(speed.value)
		enemy.contact_damage = int(damage.value))
func duplicate_enemy() -> void:
	if pack.enemy_types.size() >= 128 or enemy_type.item_count == 0: return
	var id := "variant_1"
	var n := 1
	while pack.enemy_types.has(id): n += 1; id = "variant_" + str(n)
	edit(func(): pack.enemy_types[id] = pack.enemy_types[selected(enemy_type)].duplicate(true))
	pick(enemy_type,id)
	refresh_enemy()
func find_room(id: String) -> Dictionary:
	for room in pack.rooms:
		if room.id == id: return room
	return {}
func unlink(room: Dictionary, direction: String) -> void:
	if not room.connections.has(direction): return
	var link: Dictionary = room.connections[direction]
	var target := find_room(link.target)
	var back: String = Pack.OPPOSITE[direction]
	if not target.is_empty() and target.connections.has(back) and target.connections[back].target == room.id:
		target.connections.erase(back)
	room.connections.erase(direction)
func connect_rooms() -> void:
	if destination.item_count == 0: message("Add another room first."); return
	var direction := selected(edge)
	var target := find_room(selected(destination))
	var kind := selected(door_kind)
	edit(func():
		unlink(current(),direction)
		unlink(target,Pack.OPPOSITE[direction])
		current().connections[direction] = {"target":target.id,"kind":kind}
		target.connections[Pack.OPPOSITE[direction]] = {"target":current_id,"kind":kind})
func disconnect_room() -> void: edit(func(): unlink(current(),selected(edge)))
func validate_pack() -> void:
	var errors := Pack.validate(pack)
	if errors.is_empty():
		var warnings := Pack.layout_warnings(pack)
		message("Valid pack: %d rooms. Potential paths only; keys, bombs and combat are not solved." % pack.rooms.size() + ("\nLayout warnings:\n" + "\n".join(warnings) if not warnings.is_empty() else ""))
		return
	message("Valid pack: %d rooms. Progression and key solvability are not checked." % pack.rooms.size() if errors.is_empty() else "Fix before saving or playing:\n" + "\n".join(errors))
func message(text: String) -> void: status.text = text
func replace_pack(value: Dictionary, filename: String) -> void:
	pack = value.duplicate(true)
	path = filename
	current_id = pack.start_room
	undo_stack.clear()
	redo_stack.clear()
	saved_text = JSON.stringify(pack)
	refresh()
	dungeon_map.fitted = false
	dungeon_map.call_deferred("fit_to_rooms")
	validate_pack()
func flush_text_edits() -> void:
	if pack_title.text == pack.title and pack_id.text == pack.id and title_edit.text == current().title: return
	var before := pack.duplicate(true)
	pack.title = pack_title.text
	pack.id = pack_id.text
	current().title = title_edit.text
	commit(before)
func request_action(action: Callable) -> void:
	flush_text_edits()
	if not dirty(): action.call(); return
	pending_action = action
	confirmation.dialog_text = "Discard unsaved changes?"
	confirmation.popup_centered()
func show_open() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Open authored dungeon pack"
	file_dialog.current_dir = game_root.path_join("content/packs")
	file_dialog.popup_centered_ratio(0.7)
func show_save() -> void:
	flush_text_edits()
	if not Pack.validate(pack).is_empty(): validate_pack(); return
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Save authored dungeon pack"
	file_dialog.current_dir = game_root.path_join("content/packs")
	file_dialog.current_file = pack.id + ".json"
	file_dialog.popup_centered_ratio(0.7)
func save() -> void:
	flush_text_edits()
	if path.is_empty(): show_save(); return
	save_to(path)
func file_selected(filename: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		var loaded := Pack.read(filename)
		if not loaded.errors.is_empty(): message("Open failed:\n" + "\n".join(loaded.errors)); return
		replace_pack(loaded.pack,filename)
	else: save_to(filename)
func save_to(filename: String) -> bool:
	if not Pack.validate(pack).is_empty(): validate_pack(); return false
	if filename.get_extension().to_lower() != "json": filename += ".json"
	if forbidden_destination(filename): message("Save authored packs outside imported/, reference-inputs/ and editor caches."); return false
	var error := Pack.write(filename,pack)
	if error != OK: message("Save failed: " + error_string(error)); return false
	path = filename
	saved_text = JSON.stringify(pack)
	refresh()
	message("Saved " + filename)
	return true
func forbidden_destination(filename: String) -> bool:
	var absolute := filename.simplify_path()
	for folder in ["imported","reference-inputs",".godot","editor/.godot"]:
		if absolute.begins_with(game_root.path_join(folder) + "/"): return true
	return false
func playtest(from_room: bool) -> void:
	flush_text_edits()
	var errors := Pack.validate(pack)
	if not errors.is_empty(): validate_pack(); return
	if not FileAccess.file_exists(game_root.path_join("project.godot")) or not FileAccess.file_exists(game_root.path_join("tools/play_authored_pack.gd")):
		message("Game project not found beside editor/. Keep both projects in this repository."); return
	var preview_dir := ProjectSettings.globalize_path("user://previews")
	DirAccess.make_dir_recursive_absolute(preview_dir)
	var preview := preview_dir.path_join("pack_%d.json" % Time.get_ticks_usec())
	var error := Pack.write(preview,pack)
	if error != OK: message("Cannot write playtest snapshot: " + error_string(error)); return
	var args := PackedStringArray(["--path",game_root,"--script","res://tools/play_authored_pack.gd","--log-file",preview + ".log","--","--pack",preview])
	if from_room: args.append_array(PackedStringArray(["--room",current_id]))
	var pid := OS.create_process(OS.get_executable_path(),args)
	if pid < 0: message("Could not launch Godot playtest."); return
	preview_pids.append(pid)
	message("Playtest launched from an unsaved snapshot. Arrows/WASD move; Space attacks; X uses an item. Log: " + preview + ".log")
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if importer != null and importer.busy:
			importer.popup_centered()
			message("Import is still running. Close the editor after it finishes; the dialog can be hidden while you edit.")
		else: request_action(func(): get_tree().quit())
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var command: bool = event.ctrl_pressed or event.meta_pressed
	if command and event.keycode == KEY_S: save(); get_viewport().set_input_as_handled()
	if command and event.keycode == KEY_Z:
		if event.shift_pressed: redo()
		else: undo()
		get_viewport().set_input_as_handled()

func select_room(id: String) -> void:
	flush_text_edits()
	current_id = id
	refresh()
	validate_pack()
func map_position(room: Dictionary) -> Vector2i:
	return Vector2i(int(room.map_position[0]),int(room.map_position[1]))
func room_at_map(cell: Vector2i) -> Dictionary:
	for room in pack.rooms:
		if map_position(room) == cell: return room
	return {}
func move_room(id: String, cell: Vector2i) -> void:
	if not dungeon_map.valid_cell(cell): message("Map positions must stay inside X 0..15 and Y -15..0."); return
	var occupant := room_at_map(cell)
	if not occupant.is_empty() and occupant.id != id: message("That map cell belongs to " + String(occupant.id) + ". Move it first."); return
	var room := find_room(id)
	if room.is_empty() or map_position(room) == cell: return
	edit(func(): room.map_position = [cell.x,cell.y])
func adjacent_cell() -> Vector2i:
	return map_position(current()) + DungeonMap.DIRECTIONS[selected(adjacent_edge)]
func add_adjacent_room() -> void:
	flush_text_edits()
	var cell := adjacent_cell()
	if not dungeon_map.valid_cell(cell): message("That neighbour is outside the dungeon map."); return
	if not room_at_map(cell).is_empty(): message("A room already occupies that cell. Use Connect neighbour."); return
	if pack.rooms.size() >= 256: message("At most 256 rooms."); return
	var source := current()
	var direction := selected(adjacent_edge)
	var kind := selected(adjacent_kind)
	edit(func():
		var room := Pack.room(unique_room_id())
		room.title = "Room " + str(pack.rooms.size()+1)
		room.map_position = [cell.x,cell.y]
		unlink(source,direction)
		source.connections[direction] = {"target":room.id,"kind":kind}
		room.connections[Pack.OPPOSITE[direction]] = {"target":source.id,"kind":kind}
		pack.rooms.append(room)
		current_id = room.id)
func connect_neighbour() -> void:
	flush_text_edits()
	var neighbour := room_at_map(adjacent_cell())
	if neighbour.is_empty(): message("No room in that direction. Use Add adjacent room."); return
	pick(edge,selected(adjacent_edge))
	pick(destination,neighbour.id)
	pick(door_kind,selected(adjacent_kind))
	connect_rooms()
func add_at_selected_cell() -> void:
	flush_text_edits()
	if not dungeon_map.valid_cell(selected_map_cell): message("Click an empty cell in the map first."); return
	if not room_at_map(selected_map_cell).is_empty(): message("That map cell is occupied."); return
	if pack.rooms.size() >= 256: message("At most 256 rooms."); return
	edit(func():
		var room := Pack.room(unique_room_id())
		room.map_position = [selected_map_cell.x,selected_map_cell.y]
		pack.rooms.append(room)
		current_id = room.id)
