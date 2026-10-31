extends Control
const Pack = preload("../shared/room_pack.gd")
const Canvas = preload("room_canvas.gd")
const DungeonMap = preload("dungeon_map.gd")
const AssetLibrary = preload("asset_library.gd")
const ImportDialog = preload("import_dialog.gd")
const DungeonTools = preload("dungeon_tools.gd")
const ArtBindings = preload("../shared/art_bindings.gd")
const Appearance = preload("../shared/appearance.gd")
const Bundle = preload("../shared/pack_bundle.gd")
var appearance: Dictionary = Appearance.fresh("lantern_vault")
var saved_appearance_text := ""
var appearance_load_warnings := PackedStringArray()
var stroke_appearance_before: Dictionary = {}
var art_brush: Dictionary = {}
var local_art: CheckBox
var collision_view: CheckBox
var tool_buttons: Dictionary = {}
var pack: Dictionary = Pack.sample()
var current_id := "entry"
var path := ""
var saved_text := ""
var undo_stack: Array = []
var redo_stack: Array = []
var stroke_before: Dictionary = {}
var selected_tool := "Select"
var placement_key: Dictionary = {}
var feature_buttons: Dictionary = {}
var feature_panels: Dictionary = {}
var placement_inspector: VBoxContainer
var stairs_inspector: VBoxContainer
const TemplateData = preload("../shared/dungeon_templates.gd")
const StairInspector = preload("stair_inspector.gd")
var resident_inspector: VBoxContainer
const ResidentInspector = preload("resident_inspector.gd")
var block_inspector: VBoxContainer
const BlockInspector = preload("block_inspector.gd")
const PlacementInspector = preload("placement_inspector.gd")
var syncing := false
var pending_action: Callable
var preview_pids: Array[int] = []
var game_root := ""
var dungeon_tools: AcceptDialog
var requirement_checks: Array[CheckBox] = []
var starting_checks: Array[CheckBox] = []
var goal_pickup: OptionButton
var goal_info: Label
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
var room_id_edit: LineEdit
var title_edit: LineEdit
var pack_id: LineEdit
## The pack ID last opened or saved; saving under a new ID remembers it.
var published_id := ""
var variant_id: LineEdit
var pack_title: LineEdit
var start_button: Button
var enemy_type: OptionButton
var item_type: OptionButton
var enemy_behavior: OptionButton
var health: SpinBox
var speed: SpinBox
var shooting: CheckBox
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
	var local := Appearance.read_local(game_root,pack)
	appearance = local.overlay
	appearance_load_warnings = local.warnings
	saved_appearance_text = JSON.stringify(appearance)
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
	button("Export game…",toolbar,show_export)
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
	label("S = spawn  •  E = enemy\nGold = pickup\nRight-click: erase entities",left)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	views = TabContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(views)
	var room_view := VBoxContainer.new()
	room_view.name = "Room"
	views.add_child(room_view)
	var tools := HFlowContainer.new()
	room_view.add_child(tools)
	var group := ButtonGroup.new()
	for name in ["Select","Block","Stairs","Floor","Wall","Water","Spawn","Enemy","Pickup","Erase","Art"]:
		var tool := button("Secret" if name == "Block" else name,tools,func(): set_tool(name))
		tool_buttons[name] = tool
		tool.toggle_mode = true
		tool.button_group = group
		tool.button_pressed = name == selected_tool
	var art_tools := HFlowContainer.new()
	room_view.add_child(art_tools)
	local_art = CheckBox.new()
	local_art.text = "Local ROM art"
	local_art.button_pressed = true
	local_art.toggled.connect(func(_value): refresh(); validate_pack())
	art_tools.add_child(local_art)
	collision_view = CheckBox.new()
	collision_view.text = "Show terrain collision"
	collision_view.toggled.connect(func(value): canvas.show_collision = value; canvas.queue_redraw())
	art_tools.add_child(collision_view)
	button("Choose art…",art_tools,func(): views.current_tab = 2)
	button("Clear room art",art_tools,func(): edit(func():
		appearance.room_tiles.erase(current_id)
		if pack.has("appearance"):
			pack.appearance.room_tiles.erase(current_id)
			pack.appearance.room_sprites.erase(current_id)))
	canvas = Canvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	room_view.add_child(canvas)
	canvas.stroke_started.connect(func(): stroke_before = pack.duplicate(true); stroke_appearance_before = appearance.duplicate(true))
	canvas.resident_chosen.connect(inspect_resident)
	canvas.stair_chosen.connect(inspect_stair)
	canvas.secret_chosen.connect(func():
		select_placement("","")
		set_feature("Secret")
		block_inspector.cell_x.get_line_edit().grab_focus())
	canvas.entity_chosen.connect(select_placement)
	canvas.entity_moved.connect(move_placement)
	canvas.entity_delete.connect(delete_placement)
	canvas.entity_duplicate.connect(duplicate_placement)
	canvas.cell_clicked.connect(paint)
	canvas.stroke_finished.connect(func(): commit(stroke_before,stroke_appearance_before); stroke_before = {}; stroke_appearance_before = {})
	label("Select: drag placements; arrows move 8 pixels, Shift moves 1. Paint: one drag is one undo step.",room_view)
	var map_view := VBoxContainer.new()
	map_view.name = "Dungeon"
	views.add_child(map_view)
	var map_tools := HFlowContainer.new()
	map_view.add_child(map_tools)
	button("Fit map",map_tools,func(): dungeon_map.fit_to_rooms())
	button("Generate…",map_tools,func(): open_dungeon_tools(0))
	button("Save template…",map_tools,func(): open_dungeon_tools(1))
	button("Check progression…",map_tools,func(): open_dungeon_tools(2))
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
		canvas.dragging = false
		if index == 1 and not dungeon_map.fitted: dungeon_map.call_deferred("fit_to_rooms"))
	label("Click to select; double-click to edit. Drag rooms. Wheel zooms; middle-drag pans.",map_view).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label("Green: open  •  Gold: key  •  Red: bombable  •  Purple: shutter  •  Dashed pink: misplaced",map_view).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	asset_library = AssetLibrary.new()
	asset_library.name = "Assets"
	views.add_child(asset_library)
	asset_library.load_catalog(game_root)
	asset_library.enemy_chosen.connect(apply_enemy_art)
	asset_library.preview_clip_chosen.connect(func(clip): canvas.enemy_preview_clip = clip;canvas.art_clock = 0.0;canvas.queue_redraw())
	asset_library.room_sprite_chosen.connect(apply_room_sprite)
	asset_library.room_sprite_cleared.connect(func(slot): edit(func():
		if pack.has("appearance") and pack.appearance.room_sprites.has(current_id): pack.appearance.room_sprites[current_id].erase(slot)))
	asset_library.library_changed.connect(func(): refresh();validate_pack())
	asset_library.tile_chosen.connect(choose_tile_brush)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 275
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 255
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
	placement_inspector = PlacementInspector.new()
	right.add_child(placement_inspector)
	placement_inspector.entity_chosen.connect(select_placement)
	placement_inspector.properties_applied.connect(apply_placement)
	placement_inspector.delete_requested.connect(delete_placement)
	placement_inspector.rename_requested.connect(rename_placement)
	placement_inspector.duplicate_requested.connect(duplicate_placement)
	placement_inspector.reset_requested.connect(refresh)
	placement_inspector.snap_requested.connect(func():
		var data := selected_placement()
		if not data.is_empty(): move_placement(current_id,[clampi(roundi(data.position[0]/8.0)*8,0,240),clampi(roundi((data.position[1]-5)/8.0)*8+5,5,157)]))
	var feature_tools := HBoxContainer.new();right.add_child(feature_tools)
	for name in ["Secret","Stairs","Resident"]:
		var toggle := Button.new();toggle.text = name;toggle.toggle_mode = true;toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL;feature_tools.add_child(toggle)
		feature_buttons[name] = toggle;toggle.toggled.connect(toggle_feature.bind(name))
	block_inspector = BlockInspector.new()
	right.add_child(block_inspector)
	block_inspector.applied.connect(apply_block)
	block_inspector.removed.connect(remove_block)
	stairs_inspector = StairInspector.new()
	right.add_child(stairs_inspector)
	stairs_inspector.applied.connect(apply_stair)
	stairs_inspector.removed.connect(remove_stair)
	stairs_inspector.cellar_requested.connect(create_cellar)
	stairs_inspector.cave_requested.connect(func(value): create_cellar(value,true))
	resident_inspector = ResidentInspector.new();right.add_child(resident_inspector)
	resident_inspector.applied.connect(apply_resident)
	resident_inspector.reset_requested.connect(refresh)
	feature_panels = {"Secret":block_inspector,"Stairs":stairs_inspector,"Resident":resident_inspector}
	set_feature("")
	section("ROOM",right)
	title_edit = LineEdit.new()
	right.add_child(title_edit)
	title_edit.text_submitted.connect(func(text): edit(func(): current().title = text))
	title_edit.focus_exited.connect(func():
		if not syncing and title_edit.text != current().title: edit(func(): current().title = title_edit.text))
	title_edit.tooltip_text = "Press Enter to apply the room title"
	var identity := HBoxContainer.new();right.add_child(identity);label("Room ID",identity)
	room_id_edit = LineEdit.new();room_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL;identity.add_child(room_id_edit)
	room_id_edit.tooltip_text = "Renaming updates references and reserves the old ID for save migration. Pack identity stays the same."
	room_id_edit.text_submitted.connect(func(text): rename_current_room(text.strip_edges()))
	button("Rename room ID",right,func(): rename_current_room(room_id_edit.text.strip_edges()))
	map_x = number("Map X",right,0,15)
	map_y = number("Map Y",right,-15,0)
	button("Apply map position",right,func(): move_room(current_id,Vector2i(int(map_x.value),int(map_y.value))))
	shutter = CheckBox.new()
	shutter.text = "Clear enemies opens shutters"
	right.add_child(shutter)
	shutter.toggled.connect(func(value):
		if not syncing and not (current().has("secret") and current().secret.reveal == "shutters"): edit(func(): current().shutter_trigger = 1 if value else 0))
	section("ENEMY BRUSH / VARIANT",right)
	enemy_type = options([],right)
	enemy_type.item_selected.connect(func(_index): refresh_enemy())
	enemy_behavior = options(Pack.BEHAVIORS,right)
	health = number("Health",right,1,255)
	speed = number("Speed / 256",right,0,2048)
	damage = number("Half-heart damage",right,0,16)
	shooting = CheckBox.new();shooting.text = "Walker shoots rocks";right.add_child(shooting)
	button("Apply variant settings",right,apply_enemy)
	button("Duplicate enemy variant",right,duplicate_enemy)
	var rename_row := HBoxContainer.new();right.add_child(rename_row)
	variant_id = LineEdit.new();variant_id.placeholder_text = "new variant ID";variant_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL;rename_row.add_child(variant_id)
	button("Rename variant",rename_row,func(): rename_variant(variant_id.text.strip_edges()))
	button("Clear variant art",right,func(): edit(func():
		appearance.enemy_sprites.erase(selected(enemy_type))
		if pack.has("appearance"): pack.appearance.enemy_sprites.erase(selected(enemy_type))))
	section("PICKUP BRUSH",right)
	item_type = options(Pack.ITEMS,right)
	section("CONNECT ROOMS",right)
	edge = options(Pack.EDGES,right)
	edge.item_selected.connect(func(_index): refresh_connection())
	destination = options([],right)
	door_kind = options(Pack.KINDS,right)
	label("Required items (apply to door)",right).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for item in Pack.REQUIRED_ITEMS:
		var check := CheckBox.new();check.text = item;right.add_child(check);requirement_checks.append(check)
	button("Connect both sides",right,connect_rooms)
	button("Remove connection",right,disconnect_room)
	label("Doors use the standard opening.\nMatching reverse doors and item gates\nare enforced in game previews.",right).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	section("OBJECTIVES",right)
	goal_info = label("",right)
	goal_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal_pickup = options([],right)
	button("Add selected pickup as objective",right,add_objective)
	button("Remove selected objective",right,remove_objective)
	section("STARTING EQUIPMENT",right)
	for item in Pack.REQUIRED_ITEMS + ["key","bombs"]:
		var check := CheckBox.new();check.text = item + (" (one)" if item == "key" else " (four)" if item == "bombs" else "");check.set_meta("item",item);right.add_child(check);starting_checks.append(check)
	button("Set checked starting equipment",right,apply_starting_items)
	status = RichTextLabel.new()
	status.custom_minimum_size.y = 85
	status.scroll_active = true
	layout.add_child(status)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; Dungeon packs"])
	file_dialog.file_selected.connect(file_selected)
	file_dialog.dir_selected.connect(export_game)
	add_child(file_dialog)
	confirmation = ConfirmationDialog.new()
	confirmation.confirmed.connect(func():
		var action := pending_action
		pending_action = Callable()
		if action.is_valid(): action.call())
	add_child(confirmation)
	dungeon_tools = DungeonTools.new()
	dungeon_tools.game_root = game_root
	add_child(dungeon_tools)
	dungeon_tools.generated.connect(func(value): request_action(func(): replace_pack(value,""); saved_text = ""; refresh(); views.current_tab = 1; dungeon_map.call_deferred("fit_to_rooms")))
	importer = ImportDialog.new()
	importer.game_root = game_root
	add_child(importer)
	importer.progress_changed.connect(message)
	importer.library_changed.connect(func(): asset_library.load_catalog(game_root); refresh(); views.current_tab = 2)

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
	var visual := effective_art()
	var enemy_selection := selected(enemy_type)
	var target_selection := selected(destination)
	rooms_list.clear()
	for r in pack.rooms:
		rooms_list.add_item(("★ " if r.id == pack.start_room else "") + r.title + (" ("+String(r.kind)+")" if r.get("kind") in ["cellar","cave"] else ""))
		if r.id == current_id: rooms_list.select(rooms_list.item_count-1)
	goal_pickup.clear()
	for pickup in room.pickups: goal_pickup.add_item(pickup.id)
	goal_info.text = str(pack.get("goals",[]).size()) + " objective pickups. Add one to use progression checking."
	for check in starting_checks: check.button_pressed = check.get_meta("item") in pack.get("starting_items",["wooden_sword"])
	title_edit.text = room.title
	room_id_edit.text = room.id
	pack_title.text = pack.title
	pack_id.text = pack.id
	map_x.value = room.map_position[0]
	map_y.value = room.map_position[1]
	shutter.button_pressed = room.shutter_trigger == 1
	shutter.disabled = room.shutter_trigger == 4
	shutter.tooltip_text = "Controlled by the room secret" if shutter.disabled else ""
	block_inspector.refresh(room)
	stairs_inspector.refresh(room,pack)
	resident_inspector.refresh(room)
	start_button.disabled = current_id == pack.start_room
	enemy_type.clear()
	for id in pack.enemy_types:
		var icon: Texture2D = asset_library.library.animation_texture(visual.enemy_sprites[id],"down","idle",0) if visual.enemy_sprites.has(id) else null
		if icon != null: enemy_type.add_icon_item(icon,id)
		else: enemy_type.add_item(id)
	pick(enemy_type,enemy_selection)
	destination.clear()
	for r in pack.rooms:
		if r.id != current_id: destination.add_item(r.id)
	pick(destination,target_selection)
	canvas.room = room
	canvas.selection = placement_key
	placement_inspector.visible = selected_tool == "Select"
	placement_inspector.refresh(room,pack,placement_key,selected_placement())
	refresh_appearance_canvas()
	dungeon_map.update_pack(pack,current_id)
	canvas.queue_redraw()
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()
	heading.text = "%s  /  %s [%s]%s" % [pack.title,room.title,room.id,("  • authored art" if Appearance.has_choices(pack.get("appearance",{})) else "")+("  • local ROM art" if local_art.button_pressed and Appearance.has_choices(appearance) else "") + ("  • unsaved" if dirty() else "")]
	get_window().title = "Dungeon Workshop — " + pack.title + (" *" if dirty() else "")
	refresh_enemy()
	refresh_connection()
	syncing = false
func refresh_enemy() -> void:
	if enemy_type.item_count == 0: return
	var enemy: Dictionary = pack.enemy_types[selected(enemy_type)]
	asset_library.enemy_apply.text = "Use sprite set for variant: " + selected(enemy_type)
	pick(enemy_behavior,enemy.behavior)
	health.value = enemy.health
	speed.value = enemy.speed_subpixels
	damage.value = enemy.contact_damage
	shooting.button_pressed = enemy.get("shooting_enabled",false)
func refresh_connection() -> void:
	var link: Dictionary = current().connections.get(selected(edge),{})
	for check in requirement_checks: check.button_pressed = check.text in link.get("requires",[])
	if link.is_empty(): return
	pick(destination,link.target)
	pick(door_kind,link.kind)
func dirty() -> bool: return JSON.stringify(pack) != saved_text or JSON.stringify(appearance) != saved_appearance_text
func document_snapshot() -> Dictionary: return {"pack":pack.duplicate(true),"appearance":appearance.duplicate(true),"current_id":current_id,"placement_key":placement_key.duplicate(true)}
func edit(action: Callable) -> void:
	var before := pack.duplicate(true)
	var before_art := appearance.duplicate(true)
	action.call()
	commit(before,before_art)
func commit(before: Dictionary, before_art = null) -> void:
	if before.is_empty(): return
	if before_art == null: before_art = appearance.duplicate(true)
	appearance.pack_id = pack.id
	ArtBindings.prune(pack)
	if JSON.stringify(before) == JSON.stringify(pack) and JSON.stringify(before_art) == JSON.stringify(appearance): return
	undo_stack.append({"pack":before,"appearance":before_art})
	if undo_stack.size() > 100: undo_stack.pop_front()
	redo_stack.clear()
	refresh()
	validate_pack()
func undo() -> void:
	canvas.dragging = false
	if undo_stack.is_empty(): return
	redo_stack.append(document_snapshot())
	var previous: Dictionary = undo_stack.pop_back()
	pack = previous.pack
	appearance = previous.appearance
	if previous.has("current_id"): current_id = previous.current_id;placement_key = previous.placement_key.duplicate(true);stairs_inspector.room_id = current_id
	refresh()
	validate_pack()
func redo() -> void:
	canvas.dragging = false
	if redo_stack.is_empty(): return
	undo_stack.append(document_snapshot())
	var following: Dictionary = redo_stack.pop_back()
	pack = following.pack
	appearance = following.appearance
	if following.has("current_id"): current_id = following.current_id;placement_key = following.placement_key.duplicate(true);stairs_inspector.room_id = current_id
	refresh()
	validate_pack()
func paint(cell: Vector2i, erase: bool) -> void:
	var room := current()
	if selected_tool == "Stairs":
		if erase:
			for stair in room.get("stairs",[]).duplicate():
				if Vector2i(int(stair.cell[0]),int(stair.cell[1])) == cell: remove_stair(stair.id)
		else:
			var stair: Dictionary = stairs_inspector.value()
			stair.cell = [cell.x,cell.y];apply_stair(stair)
		return
	if selected_tool == "Block":
		if erase: remove_block();return
		var secret: Dictionary = block_inspector.value()
		secret.cell = [cell.x,cell.y]
		apply_block(secret)
		return
	if selected_tool == "Art":
		paint_art(cell,erase)
		return
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
		if pack.schema == 2: pack.goals = pack.goals.filter(func(g): return g.room != current_id or room.pickups.any(func(p): return p.id == g.pickup))
	canvas.queue_redraw()
func placement_cell(at: Array) -> Vector2i: return Vector2i(int(at[0])/16,(int(at[1])+3)/16)
func unique_placement_id(entries: Array, prefix: String) -> String:
	var n := 1
	# Historical placement IDs stay reserved so old progress cannot attach to them.
	while entries.any(func(e): return e.id == prefix + "_" + str(n)) or Pack.ContentIds.FIELDS.any(func(field): return Pack.ContentIds.reserved_placement(pack,current_id,field,prefix + "_" + str(n))): n += 1
	return prefix + "_" + str(n)
func unique_room_id() -> String:
	var n := 1
	while Pack.RoomIds.reserved(pack,"room_"+str(n)): n += 1
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
		room.erase("stairs")
		if appearance.room_tiles.has(current_id): appearance.room_tiles[room.id] = appearance.room_tiles[current_id].duplicate(true)
		if pack.has("appearance"):
			for field in ["room_tiles","room_sprites"]:
				if pack.appearance[field].has(current_id): pack.appearance[field][room.id] = pack.appearance[field][current_id].duplicate(true)
		pack.rooms.append(room)
		current_id = room.id)
func delete_room() -> void:
	if pack.get("room_aliases",{}).size()>=1024: message("Room migration history limit reached");return
	edit(func():
		Pack.upgrade(pack)
		Pack.RoomIds.retire(pack,current_id)
		Pack.ContentIds.rekey_room(pack,current_id,"")
		var removed := current_id
		appearance.room_tiles.erase(removed)
		if pack.schema == 2: pack.goals = pack.goals.filter(func(g): return g.room != removed)
		pack.rooms = pack.rooms.filter(func(r): return r.id != removed)
		for room in pack.rooms:
			if room.has("stairs"): room.stairs = room.stairs.filter(func(stair): return stair.target != removed)
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
		enemy.contact_damage = int(damage.value)
		if enemy.behavior=="walker" and shooting.button_pressed:
			Pack.upgrade(pack);enemy.shooting_enabled = true
		else: enemy.erase("shooting_enabled"))
func duplicate_enemy() -> void:
	if pack.enemy_types.size() >= 128 or enemy_type.item_count == 0: return
	var id := "variant_1"
	var n := 1
	while pack.enemy_types.has(id): n += 1; id = "variant_" + str(n)
	edit(func():
		pack.enemy_types[id] = pack.enemy_types[selected(enemy_type)].duplicate(true)
		if appearance.enemy_sprites.has(selected(enemy_type)): appearance.enemy_sprites[id] = appearance.enemy_sprites[selected(enemy_type)]
		if pack.has("appearance") and pack.appearance.enemy_sprites.has(selected(enemy_type)): pack.appearance.enemy_sprites[id] = pack.appearance.enemy_sprites[selected(enemy_type)])
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
	var requirements := selected_requirements()
	edit(func():
		if not requirements.is_empty(): Pack.upgrade(pack)
		unlink(current(),direction)
		unlink(target,Pack.OPPOSITE[direction])
		current().connections[direction] = connection(target.id,kind,requirements)
		target.connections[Pack.OPPOSITE[direction]] = connection(current_id,kind,requirements))
func disconnect_room() -> void: edit(func(): unlink(current(),selected(edge)))
func validate_pack() -> void:
	var errors := Pack.validate(pack)
	if errors.is_empty():
		var warnings := Pack.layout_warnings(pack)
		warnings.append_array(appearance_load_warnings)
		warnings.append_array(asset_library.library.warnings)
		message("Valid pack: %d rooms. Structural check only; use Dungeon > Check progression for inventory and objectives." % pack.rooms.size() + ("\nLayout warnings:\n" + "\n".join(warnings) if not warnings.is_empty() else ""))
		return
	message("Valid pack: %d rooms. Progression and key solvability are not checked." % pack.rooms.size() if errors.is_empty() else "Fix before saving or playing:\n" + "\n".join(errors))
func message(text: String) -> void: status.text = text
func replace_pack(value: Dictionary, filename: String, load_local_art: bool = true) -> void:
	placement_key = {}
	canvas.dragging = false
	stairs_inspector.room_id = ""
	pack = value.duplicate(true)
	published_id = String(pack.id) if not filename.is_empty() else ""
	var local := Appearance.read_local(game_root,pack) if load_local_art else {"overlay":Appearance.fresh(pack.id),"warnings":PackedStringArray()}
	appearance = local.overlay
	appearance_load_warnings = local.warnings
	saved_appearance_text = JSON.stringify(appearance)
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
	appearance.pack_id = pack.id
	var art_errors := Appearance.validate(appearance,pack)
	if not art_errors.is_empty(): message("Invalid local appearance: " + "\n".join(art_errors)); return false
	if filename.get_extension().to_lower() != "json": filename += ".json"
	if forbidden_destination(filename): message("Save authored packs outside imported/, reference-inputs/ and editor caches."); return false
	var before_identity := pack.duplicate(true)
	Pack.ContentIds.record_identity(pack,published_id)
	var error := Pack.write(filename,pack)
	if error != OK: pack = before_identity;message("Save failed: " + error_string(error)); return false
	path = filename
	published_id = pack.id
	saved_text = JSON.stringify(pack)
	if JSON.stringify(appearance) != saved_appearance_text:
		var art_path := Appearance.local_path(game_root,pack.id)
		var directory_error := DirAccess.make_dir_recursive_absolute(art_path.get_base_dir())
		var art_error := Pack.write(art_path,appearance) if directory_error == OK else directory_error
		if art_error != OK: refresh(); message("Pack saved; local art could not save: " + error_string(art_error)); return false
		saved_appearance_text = JSON.stringify(appearance)
		appearance_load_warnings.clear()
	refresh()
	message("Saved " + filename + (" • ROM art saved separately in ignored reference-inputs/editor-overrides/" if Appearance.has_choices(appearance) else ""))
	return true
## A standalone bundle (pack and its shared art) for the game's packs/ folder.
func show_export() -> void:
	flush_text_edits()
	if not Pack.validate(pack).is_empty(): validate_pack(); return
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.title = "Choose a packs folder; the game is exported into " + pack.id + "/"
	file_dialog.popup_centered_ratio(0.7)
func export_game(folder: String) -> void:
	var destination := folder.path_join(pack.id)
	if forbidden_destination(destination.path_join(Bundle.PACK_FILE)): message("Export outside imported/, reference-inputs/ and editor caches."); return
	var errors := Bundle.write_bundle(pack,game_root,destination)
	if not errors.is_empty(): message("Export failed:\n" + "\n".join(errors)); return
	message("Exported " + destination + (" • local ROM art is not included" if Appearance.has_choices(appearance) else "") + ". Place it in packs/ beside the game, or in its user://packs.")
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
	if local_art.button_pressed:
		var art_snapshot := preview + ".appearance.json"
		if Pack.write(art_snapshot,appearance) != OK: message("Cannot write local appearance snapshot"); return
		args.append_array(PackedStringArray(["--appearance",art_snapshot]))
	else: args.append("--no-local-art")
	if from_room: args.append_array(PackedStringArray(["--room",current_id]))
	var pid := OS.create_process(OS.get_executable_path(),args)
	if pid < 0: message("Could not launch Godot playtest."); return
	preview_pids.append(pid)
	message("Playtest launched from an unsaved snapshot. Arrows/WASD move; Space attacks; X uses an item. Log: " + preview + ".log")
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if dungeon_tools != null and dungeon_tools.busy:
			dungeon_tools.popup_centered();message("Dungeon generation/progression is still running. Close after it finishes.")
		elif importer != null and importer.busy:
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
	placement_key = {}
	canvas.dragging = false
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
	var requirements := selected_requirements()
	edit(func():
		if not requirements.is_empty(): Pack.upgrade(pack)
		var room := Pack.room(unique_room_id())
		room.title = "Room " + str(pack.rooms.size()+1)
		room.map_position = [cell.x,cell.y]
		unlink(source,direction)
		source.connections[direction] = connection(room.id,kind,requirements)
		room.connections[Pack.OPPOSITE[direction]] = connection(source.id,kind,requirements)
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

func effective_art() -> Dictionary:
	return Appearance.effective(pack,appearance if local_art.button_pressed else {})
func public_art() -> Dictionary:
	Pack.upgrade(pack)
	if not pack.has("appearance"): pack.appearance = ArtBindings.fresh()
	return pack.appearance
func refresh_appearance_canvas() -> void:
	canvas.visual_texture = null
	canvas.enemy_sprite_clips.clear();canvas.enemy_layouts.clear();canvas.room_sprite_layouts.clear();canvas.enemy_textures.clear();canvas.enemy_sprite_frames.clear();canvas.enemy_sprite_ticks.clear();canvas.room_sprite_frames.clear();canvas.room_sprite_ticks.clear()
	asset_library.library.warnings.clear()
	var visual := effective_art()
	canvas.visual_texture = asset_library.library.room_texture(current(),visual)
	for id in visual.enemy_sprites:
		var texture: Texture2D = asset_library.library.animation_texture(visual.enemy_sprites[id],"down","idle",0)
		if texture != null:
			canvas.enemy_textures[id] = texture
			canvas.enemy_sprite_clips[id] = asset_library.library.groups.get(visual.enemy_sprites[id],{}).get("clips",{})
			canvas.enemy_layouts[id] = asset_library.library.sprite_layout(visual.enemy_sprites[id])
			canvas.enemy_sprite_frames[id] = asset_library.library.sprite_frames(visual.enemy_sprites[id])
			canvas.enemy_sprite_ticks[id] = int(asset_library.library.groups.get(visual.enemy_sprites[id],{}).get("frame_ticks",6))
	for slot in visual.get("room_sprites",{}).get(current_id,{}):
		var id: String = visual.room_sprites[current_id][slot]
		canvas.room_sprite_frames[slot] = asset_library.library.sprite_frames(id,"idle")
		canvas.room_sprite_layouts[slot] = asset_library.library.sprite_layout(id)
		canvas.room_sprite_ticks[slot] = asset_library.library.clip_ticks(id,"idle")
	canvas.queue_redraw()
func apply_enemy_art(group_id: String) -> void:
	if enemy_type.item_count == 0: message("Create an enemy variant first"); return
	if not asset_library.library.groups.has(group_id): message("Choose a supported sprite set"); return
	var id := selected(enemy_type)
	edit(func():
		if ArtBindings.asset_id(group_id):
			public_art().enemy_sprites[id] = group_id;appearance.enemy_sprites.erase(id)
		else: appearance.enemy_sprites[id] = group_id)
	views.current_tab = 0
	message("Applied art to variant " + id + ". Behavior and stats are unchanged.")
func apply_room_sprite(slot: String, group_id: String) -> void:
	if not ArtBindings.asset_id(group_id) or not asset_library.library.groups.has(group_id): message("Choose an authored sprite set for room objects.");return
	if (slot in ["secret","resident"] and not current().has(slot)) or (slot == "stairs" and current().get("stairs",[]).is_empty()): message("Add the room's "+slot+" before assigning its art.");return
	edit(func():
		var visual := public_art()
		if not visual.room_sprites.has(current_id): visual.room_sprites[current_id] = {}
		visual.room_sprites[current_id][slot] = group_id)
	views.current_tab = 0

func choose_tile_brush(atlas_id: String, index: int) -> void:
	art_brush = {"atlas":atlas_id,"index":index}
	set_tool("Art")
	tool_buttons.Art.button_pressed = true
	views.current_tab = 0
	message("Art brush: tile %d. Paint appearance; terrain collision is unchanged. Right-click erases art." % index)
func paint_art(cell: Vector2i, erase: bool) -> void:
	var authored: bool = ArtBindings.asset_id(art_brush.get("atlas",""))
	if not authored and not local_art.button_pressed: message("Enable Local ROM art before painting ROM assets"); return
	if not erase and art_brush.is_empty(): message("Choose an atlas tile in Assets first"); return
	var existing: Dictionary = pack.get("appearance",ArtBindings.fresh()) if authored else appearance
	if not erase and existing.room_tiles.has(current_id) and existing.room_tiles[current_id].atlas != art_brush.atlas:
		message("This room uses another atlas. Clear room art first, or choose that atlas.");return
	var visual: Dictionary = public_art() if authored else appearance
	if authored: appearance.room_tiles.erase(current_id)
	if erase:
		if visual.room_tiles.has(current_id):
			visual.room_tiles[current_id].indices[cell.y*16+cell.x] = -1
			if visual.room_tiles[current_id].indices.all(func(i): return i == -1): visual.room_tiles.erase(current_id)
	else:
		if visual.room_tiles.has(current_id) and visual.room_tiles[current_id].atlas != art_brush.atlas:
			message("This room uses another atlas. Clear room art first, or choose that atlas."); return
		if not visual.room_tiles.has(current_id):
			var indices: Array = [];indices.resize(176);indices.fill(-1)
			visual.room_tiles[current_id] = {"atlas":art_brush.atlas,"indices":indices}
		visual.room_tiles[current_id].indices[cell.y*16+cell.x] = art_brush.index
	refresh_appearance_canvas()

func selected_requirements() -> Array:
	var items: Array = []
	for check in requirement_checks:
		if check.button_pressed: items.append(check.text)
	return items
func connection(target: String, kind: String, requirements: Array) -> Dictionary:
	var link := {"target":target,"kind":kind}
	if pack.schema == 2: link.requires = requirements.duplicate()
	return link
func open_dungeon_tools(tab: int) -> void:
	flush_text_edits()
	dungeon_tools.open_for(pack,current_id,tab)
func add_objective() -> void:
	if goal_pickup.item_count == 0: message("Place a pickup in this room first.");return
	var goal := {"room":current_id,"pickup":selected(goal_pickup)}
	edit(func():
		Pack.upgrade(pack)
		if not pack.goals.has(goal): pack.goals.append(goal))
func remove_objective() -> void:
	if pack.schema != 2 or goal_pickup.item_count == 0: return
	var goal := {"room":current_id,"pickup":selected(goal_pickup)}
	edit(func(): pack.goals.erase(goal))
func apply_starting_items() -> void:
	var items: Array = []
	for check in starting_checks:
		if check.button_pressed: items.append(check.get_meta("item"))
	edit(func(): Pack.upgrade(pack);pack.starting_items = items)

func set_tool(value: String) -> void:
	selected_tool = value
	placement_key = {}
	canvas.dragging = false
	canvas.select_mode = value == "Select"
	tool_buttons[value].button_pressed = true
	set_feature("Secret" if value=="Block" else "Stairs" if value=="Stairs" else "")
	refresh()
	call_deferred("scroll_tool_settings",value)
func selected_placement() -> Dictionary:
	if placement_key.get("room") != current_id: return {}
	if placement_key.get("kind") == "spawn": return {"position":current().spawn}
	for entry in current().get(placement_key.get("kind",""),[]):
		if entry.id == placement_key.get("id"): return entry
	return {}
func select_placement(kind: String, id: String) -> void:
	placement_key = {} if kind.is_empty() else {"room":current_id,"kind":kind,"id":id}
	refresh()
func valid_placement(at: Array, secret_pickup: bool = false) -> bool:
	if not Pack.point(at,0,240,0,157) or not Pack.walkable(current().tiles,at): return false
	return secret_pickup or not current().has("secret") or not Pack.block_overlaps(current().secret,at,false)
func move_placement(room_id: String, at: Array) -> void:
	if room_id != current_id or selected_placement().is_empty(): return
	if same_position(selected_placement().position,at): return
	if not valid_placement(at,placement_key.kind == "pickups" and selected_placement().get("requires_secret",false)): message("Choose walkable ground outside the block, or mark this pickup to appear after the push.");return
	edit(func():
		if placement_key.kind == "spawn": current().spawn = at
		else: selected_placement().position = at)
func delete_placement() -> void:
	if selected_placement().is_empty() or placement_key.kind == "spawn": return
	edit(func():
		var entries: Array = current()[placement_key.kind]
		for i in entries.size():
			if entries[i].id == placement_key.id: entries.remove_at(i);break
		Pack.upgrade(pack)
		Pack.ContentIds.retire_placement(pack,current_id,placement_key.kind,placement_key.id)
		if placement_key.kind == "pickups" and pack.has("goals"):
			pack.goals = pack.goals.filter(func(g): return not (g.room == current_id and g.pickup == placement_key.id)))
func duplicate_placement() -> void:
	var source := selected_placement()
	if source.is_empty() or placement_key.kind == "spawn": return
	var entries: Array = current()[placement_key.kind]
	if entries.size() >= (10 if placement_key.kind == "enemies" else 32): message("This room has reached its placement limit.");return
	var candidates: Array = []
	for y in range(5,158,8):
		for x in range(0,241,8):
			var at := [x,y]
			if not valid_placement(at): continue
			var blocked := false
			for other in current().enemies+current().pickups+[{"position":current().spawn}]:
				if absi(x-int(other.position[0]))<16 and absi(y-int(other.position[1]))<16: blocked = true;break
			if not blocked: candidates.append(at)
	if candidates.is_empty(): message("No free walkable position for a duplicate.");return
	var origin := Vector2(source.position[0],source.position[1])
	candidates.sort_custom(func(a,b): return Vector2(a[0],a[1]).distance_squared_to(origin)<Vector2(b[0],b[1]).distance_squared_to(origin))
	edit(func():
		var copy := source.duplicate(true)
		copy.id = unique_placement_id(entries,"enemy" if placement_key.kind == "enemies" else "item")
		copy.position = candidates[0]
		entries.append(copy)
		placement_key.id = copy.id)
func apply_placement(properties: Dictionary) -> void:
	var data := selected_placement()
	if data.is_empty(): return
	if not valid_placement(properties.position,placement_key.kind == "pickups" and properties.get("requires_secret",false)): message("Choose walkable ground outside the block, or mark this pickup to appear after the push.");return
	if properties.get("requires_secret",false) and not current().has("secret"): message("Add a room secret first.");return
	var variant := String(properties.get("type",""))
	var changed := false
	var uses := 0
	if placement_key.kind == "enemies":
		if not pack.enemy_types.has(variant): return
		var original: Dictionary = pack.enemy_types[variant]
		for field in properties.settings:
			if field in ["health","speed_subpixels","contact_damage"]:
				if int(properties.settings[field]) != int(original[field]): changed = true
			elif properties.settings[field] != original.get(field,false): changed = true
		for room in pack.rooms:
			for enemy in room.enemies:
				if enemy.type == variant: uses += 1
		if changed and uses>1 and pack.enemy_types.size()>=128: message("Enemy variant limit reached.");return
	edit(func():
		if placement_key.kind == "spawn":
			if not same_position(current().spawn,properties.position): current().spawn = properties.position
			return
		if not same_position(data.position,properties.position): data.position = properties.position
		if placement_key.kind == "enemies":
			var target := variant
			if changed:
				if uses>1:
					var n := 1
					target = variant.left(40)+"_instance_"+str(n)
					while pack.enemy_types.has(target): n+=1;target = variant.left(40)+"_instance_"+str(n)
					if appearance.enemy_sprites.has(variant): appearance.enemy_sprites[target] = appearance.enemy_sprites[variant]
					if pack.has("appearance") and pack.appearance.enemy_sprites.has(variant): pack.appearance.enemy_sprites[target] = pack.appearance.enemy_sprites[variant]
				if properties.settings.get("shooting_enabled",false): Pack.upgrade(pack)
				pack.enemy_types[target] = properties.settings.duplicate(true)
			data.type = target
		else:
			data.item = properties.item
			if properties.get("requires_secret",false): Pack.upgrade(pack);data.requires_secret = true
			else: data.erase("requires_secret")
			if properties.requires_clear: Pack.upgrade(pack);data.requires_clear = true
			else: data.erase("requires_clear")
			if properties.objective: Pack.upgrade(pack)
			if pack.has("goals") and properties.objective != PlacementInspector.is_objective(pack,current_id,placement_key.id):
				pack.goals = pack.goals.filter(func(g): return not (g.room == current_id and g.pickup == placement_key.id))
				if properties.objective: pack.goals.append({"room":current_id,"pickup":placement_key.id}))

func same_position(a: Array, b: Array) -> bool:
	return int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])

func apply_block(secret: Dictionary) -> void:
	if current().has("resident"): message("Place secrets in the entrance room, outside the resident interior.");return
	var room := current().duplicate(true)
	room.secret = secret.duplicate(true)
	if Pack.secret_trigger(secret) in ["bomb","fire"] and Pack.point(secret.get("cell"),2,13,2,8):
		var x := int(secret.cell[0]);var y := int(secret.cell[1]);var row: String = room.tiles[y]
		if row[x] == "#": room.tiles[y] = row.left(x)+"."+row.substr(x+1)
	room.shutter_trigger = 4 if secret.reveal == "shutters" else (1 if room.shutter_trigger == 4 else room.shutter_trigger)
	var errors := PackedStringArray()
	Pack.validate_block(room,true,errors)
	var lookup: Dictionary = {}
	for entry in pack.rooms: lookup[entry.id] = room if entry.id == current_id else entry
	Pack.validate_stairs(lookup,errors)
	if not errors.is_empty(): message("\n".join(errors));return
	if current().has("secret") and same_position(current().secret.cell,secret.cell) and current().secret.direction == secret.direction and current().secret.reveal == secret.reveal and Pack.secret_trigger(current().secret) == Pack.secret_trigger(secret) and current().shutter_trigger == room.shutter_trigger and current().tiles == room.tiles: return
	var action := func():
		Pack.upgrade(pack)
		current().secret = secret.duplicate(true)
		current().tiles = room.tiles
		current().shutter_trigger = room.shutter_trigger
	if stroke_before.is_empty(): edit(action)
	else: action.call();canvas.queue_redraw()
func remove_block() -> void:
	if not current().has("secret"): return
	var action := func():
		current().erase("secret")
		if current().shutter_trigger == 4: current().shutter_trigger = 1
		for pickup in current().pickups: pickup.erase("requires_secret")
		for stair in current().get("stairs",[]): stair.erase("requires_secret")
	if stroke_before.is_empty(): edit(action)
	else: action.call();canvas.queue_redraw()

func apply_stair(value: Dictionary) -> void:
	var candidate := pack.duplicate(true);Pack.upgrade(candidate)
	var room: Dictionary
	for entry in candidate.rooms:
		if entry.id == current_id: room = entry;break
	var stair := value.duplicate(true)
	var entries: Array = room.get("stairs",[])
	if stair.id.is_empty(): stair.id = unique_placement_id(entries,"stairs")
	var replaced := false
	for i in entries.size():
		if entries[i].id == stair.id: entries[i] = stair;replaced = true;break
	if not replaced: entries.append(stair)
	room.stairs = entries
	var errors := Pack.validate(candidate)
	if not errors.is_empty(): message("\n".join(errors));return
	# Preserve numeric representation on a no-op loaded from JSON.
	if TemplateData.canonical(candidate) == TemplateData.canonical(pack): return
	stairs_inspector.selected_id = stair.id
	if stroke_before.is_empty(): edit(func(): pack = candidate)
	else: pack = candidate;canvas.room = current();canvas.queue_redraw()
func remove_stair(id: String) -> void:
	if not current().get("stairs",[]).any(func(stair): return stair.id == id): return
	var action := func(): current().stairs = current().stairs.filter(func(stair): return stair.id != id)
	if stroke_before.is_empty(): edit(action)
	else: action.call();canvas.queue_redraw()
func create_cellar(value: Dictionary, cave: bool = false) -> void:
	if pack.rooms.size() >= 256 or current().get("stairs",[]).size() >= 4: message("Room or stair limit reached.");return
	var candidate := pack.duplicate(true);Pack.upgrade(candidate)
	var source: Dictionary
	for room in candidate.rooms:
		if room.id == current_id: source = room;break
	var cellar := Pack.room(unique_room_id(),"Cave") if cave else Pack.cellar(unique_room_id())
	if cave: cellar.kind = "cave";cellar.resident = Pack.resident()
	cellar.map_position = unused_map_position()
	var stair := value.duplicate(true)
	var entries: Array = source.get("stairs",[])
	stair.id = unique_placement_id(entries,"stairs")
	stair.target = cellar.id;stair.target_position = [120,125] if cave else [48,61]
	entries.append(stair);source.stairs = entries
	cellar.stairs = [{"id":"return","cell":[3,7] if cave else [3,3],"target":current_id,"target_position":source.spawn.duplicate()}]
	candidate.rooms.append(cellar)
	var errors := Pack.validate(candidate)
	if not errors.is_empty(): message("\n".join(errors));return
	stairs_inspector.selected_id = stair.id
	edit(func(): pack = candidate)
	message("Created " + String(cellar.id) + " with a return stair. Select it in the room list to paint or place items.")

func inspect_stair(id: String) -> void:
	select_placement("","")
	set_feature("Stairs")
	stairs_inspector.choose(id)
	stairs_inspector.cell_x.get_line_edit().grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	stairs_inspector.get_parent().get_parent().scroll_vertical = int(stairs_inspector.position.y)

func apply_resident(data: Dictionary) -> void:
	var candidate := pack.duplicate(true)
	if not data.is_empty(): Pack.upgrade(candidate)
	for room in candidate.rooms:
		if room.id != current_id: continue
		if data.is_empty(): room.erase("resident")
		else: room.resident = data.duplicate(true)
	var errors := Pack.validate(candidate)
	if not errors.is_empty(): message("\n".join(errors));return
	if TemplateData.canonical(candidate) == TemplateData.canonical(pack): return
	edit(func(): pack = candidate)
func inspect_resident() -> void:
	select_placement("","")
	set_feature("Resident")
	await get_tree().process_frame
	await get_tree().process_frame
	resident_inspector.get_parent().get_parent().scroll_vertical = int(resident_inspector.position.y)

## Keep optional feature forms out of the basic room/brush editing path.
func toggle_feature(enabled: bool, name: String) -> void:
	set_feature(name if enabled else "")
func set_feature(name: String) -> void:
	for key in feature_panels:
		feature_panels[key].visible = key==name
		feature_buttons[key].set_pressed_no_signal(key==name)

func scroll_tool_settings(value: String) -> void:
	if value!=selected_tool: return
	var scroll: ScrollContainer = item_type.get_parent().get_parent()
	var target: Control = item_type if value=="Pickup" else enemy_type if value=="Enemy" else null
	scroll.scroll_vertical = maxi(0,int(target.position.y)-24) if target!=null else 0

func rename_current_room(id: String) -> bool:
	flush_text_edits()
	if id==current_id: message("Room ID already matches");return true
	var result := Pack.rename_room(pack,current_id,id,appearance)
	if not result.errors.is_empty(): message("Cannot rename room:\n"+"\n".join(result.errors));return false
	var old := current_id;var selection := placement_key.duplicate(true)
	edit(func():
		pack = result.pack;appearance = result.appearance;current_id = id;stairs_inspector.room_id = id
		if placement_key.get("room")==old: placement_key.room = id)
	undo_stack[-1].current_id = old;undo_stack[-1].placement_key = selection
	message("Renamed "+old+" to "+id+". References updated; save the pack to retain old-checkpoint compatibility.")
	return true

func rename_placement(id: String) -> void:
	flush_text_edits()
	if placement_key.get("kind","") not in Pack.ContentIds.FIELDS: return
	var result := Pack.ContentIds.rename_placement(pack,current_id,placement_key.kind,placement_key.id,id)
	if result.errors.is_empty(): result.errors = Pack.validate(result.pack)
	if not result.errors.is_empty(): message("Cannot rename placement:\n"+"\n".join(result.errors));return
	var old: String = placement_key.id;var selection := placement_key.duplicate(true)
	edit(func(): pack = result.pack;placement_key.id = id)
	undo_stack[-1].current_id = current_id;undo_stack[-1].placement_key = selection
	message("Renamed "+old+" to "+id+". Old checkpoints keep their progress; save the pack to retain the history.")
func rename_variant(id: String) -> void:
	flush_text_edits()
	if enemy_type.item_count == 0: return
	var old := selected(enemy_type)
	var result := Pack.ContentIds.rename_variant(pack,old,id,appearance)
	if result.errors.is_empty(): result.errors = Pack.validate(result.pack)
	if not result.errors.is_empty(): message("Cannot rename variant:\n"+"\n".join(result.errors));return
	edit(func(): pack = result.pack;appearance = result.appearance)
	pick(enemy_type,id);variant_id.text = ""
	message("Renamed variant "+old+" to "+id+".")
