extends AcceptDialog
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Solver = preload("../shared/progression_solver.gd")
signal generated(pack: Dictionary)
var game_root := ""
var source_pack: Dictionary = {}
var room_id := ""
var candidate: Dictionary = {}
var busy := false
var worker: Thread
var job_kind := ""
var content: VBoxContainer
var tabs: TabContainer
var catalog_path: LineEdit
var seed_input: LineEdit
var count: SpinBox
var custom_layout: CheckBox
var branch_rooms: SpinBox
var loop_count: SpinBox
var required_item: OptionButton
var report: TextEdit
var generate_button: Button
var use_button: Button
var solve_button: Button
var save_button: Button
var template_id: LineEdit
var role: OptionButton
var port_checks: Array[CheckBox] = []
var requirement_checks: Array[CheckBox] = []
var include_linked: CheckBox
var custom_reward: CheckBox
var reward_room: OptionButton
var reward_x: SpinBox
var reward_y: SpinBox
var capture_info: Label
var random_seed_button: Button
var browse_button: Button
var picker: FileDialog
func label(text: String, parent: Node) -> void:
	var node := Label.new();node.text = text;node.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HBoxContainer or parent is HFlowContainer else TextServer.AUTOWRAP_WORD_SMART;parent.add_child(node)
func button(text: String, parent: Node, action: Callable) -> Button:
	var node := Button.new();node.text = text;node.pressed.connect(action);parent.add_child(node);return node
func _ready() -> void:
	title = "Dungeon templates, generation and progression"
	wrap_controls = false
	min_size = Vector2i(870,700)
	size = Vector2i(950,740)
	get_ok_button().text = "Close"
	content = VBoxContainer.new();add_child(content)
	label("Authored templates → deterministic dungeon → inventory and collision search.\nCombat is assumed winnable with a sword; unsupported mechanics and limits are reported explicitly.",content)
	var library_row := HBoxContainer.new();content.add_child(library_row)
	catalog_path = LineEdit.new();catalog_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_path.text = game_root.path_join("content/templates/dungeon_templates.json")
	library_row.add_child(catalog_path)
	browse_button = button("Browse templates…",library_row,func(): picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE;picker.popup_centered_ratio(0.7))
	tabs = TabContainer.new();content.add_child(tabs)
	var generate := VBoxContainer.new();generate.name = "Generate";tabs.add_child(generate)
	var recipe := HBoxContainer.new();generate.add_child(recipe)
	label("Seed",recipe);seed_input = LineEdit.new();seed_input.text = "42";seed_input.custom_minimum_size.x = 145;recipe.add_child(seed_input)
	seed_input.text_changed.connect(func(_value): invalidate_recipe())
	random_seed_button = button("Random seed",recipe,func(): seed_input.text = str(Time.get_ticks_usec()%2147483648);invalidate_recipe())
	label("Primary rooms",recipe);count = SpinBox.new();count.min_value = 6;count.max_value = 16;count.value = 8;recipe.add_child(count)
	count.value_changed.connect(func(_value): update_layout_controls();invalidate_recipe())
	required_item = OptionButton.new()
	for item in ["blue_candle","bow","ladder","recorder","magic_key"]: required_item.add_item(item)
	recipe.add_child(required_item)
	required_item.item_selected.connect(func(_value): invalidate_recipe())
	catalog_path.text_changed.connect(func(_value): invalidate_recipe())
	var layout_row := HBoxContainer.new();generate.add_child(layout_row)
	custom_layout = CheckBox.new();custom_layout.text = "Custom layout";custom_layout.tooltip_text = "Off preserves classic recipes and seed results";layout_row.add_child(custom_layout)
	label("Branch rooms",layout_row);branch_rooms = SpinBox.new();branch_rooms.min_value = 0;branch_rooms.max_value = 2;branch_rooms.value = 2;branch_rooms.tooltip_text = "Rooms off the main route, not a count of separate branches";layout_row.add_child(branch_rooms)
	label("Extra loops",layout_row);loop_count = SpinBox.new();loop_count.min_value = 0;loop_count.max_value = 8;loop_count.tooltip_text = "Exact extra connections between adjacent primary rooms; cellar stairs are separate";layout_row.add_child(loop_count)
	custom_layout.toggled.connect(func(_value): update_layout_controls();invalidate_recipe())
	branch_rooms.value_changed.connect(func(_value): invalidate_recipe())
	loop_count.value_changed.connect(func(_value): invalidate_recipe())
	update_layout_controls()
	var actions := HBoxContainer.new();generate.add_child(actions)
	generate_button = button("Generate and verify",actions,start_generation)
	use_button = button("Use generated dungeon",actions,use_candidate)
	use_button.disabled = true
	label("The required item is placed before its gate. Two key locks and optional bomb branches are checked.\nCustom layouts keep at least six main-path rooms and require the exact loop count. Loops preserve crossed gates.\nUsing a result replaces the document after any unsaved-change confirmation. No ROM assets are generated.",generate)
	var capture := VBoxContainer.new();capture.name = "Templates";tabs.add_child(capture)
	label("Capture a primary room, optionally with linked cellars. Authored graphics are preserved; external doors and private ROM choices are omitted. Enemy definitions and generated stair destinations are namespaced.",capture)
	var identity := HBoxContainer.new();capture.add_child(identity)
	template_id = LineEdit.new();template_id.placeholder_text = "unique_template_id";template_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL;identity.add_child(template_id)
	role = OptionButton.new()
	for value in Templates.ROLES: role.add_item(value)
	identity.add_child(role)
	var ports := HBoxContainer.new();capture.add_child(ports);label("Available door ports",ports)
	for edge in Pack.EDGES:
		var check := CheckBox.new();check.text = edge;check.button_pressed = true;ports.add_child(check);port_checks.append(check)
	var requirements := HFlowContainer.new();capture.add_child(requirements);label("Incoming item requirements",requirements)
	for item in Pack.REQUIRED_ITEMS:
		var check := CheckBox.new();check.text = item;requirements.add_child(check);requirement_checks.append(check)
	include_linked = CheckBox.new();include_linked.text = "Include linked cellar rooms (up to three)";capture.add_child(include_linked)
	include_linked.toggled.connect(func(_value): refresh_capture_rooms())
	custom_reward = CheckBox.new();custom_reward.text = "Choose generated reward location";capture.add_child(custom_reward)
	custom_reward.toggled.connect(func(_value): refresh_reward_controls())
	var reward_row := HBoxContainer.new();capture.add_child(reward_row)
	label("Reward room",reward_row);reward_room = OptionButton.new();reward_room.clip_text = true;reward_room.custom_minimum_size.x = 180;reward_row.add_child(reward_room)
	reward_room.item_selected.connect(func(_i):
		for room in source_pack.rooms:
			if room.id == reward_room.get_item_text(reward_room.selected): reward_x.value = room.spawn[0];reward_y.value = room.spawn[1])
	label("X",reward_row);reward_x = SpinBox.new();reward_x.min_value = 0;reward_x.max_value = 240;reward_x.value = 120;reward_row.add_child(reward_x)
	label("Y",reward_row);reward_y = SpinBox.new();reward_y.min_value = 0;reward_y.max_value = 157;reward_y.value = 77;reward_row.add_child(reward_y)
	capture_info = Label.new();capture_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;capture.add_child(capture_info)
	save_button = button("Save selection as new template…",capture,func(): picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE;picker.current_file = "custom_templates.json";picker.popup_centered_ratio(0.7))
	var solve := VBoxContainer.new();solve.name = "Progression";tabs.add_child(solve)
	label("Checks a snapshot of the current pack, starting equipment and objective pickups. Keys, bombs and rupees are finite; gifts persist and shops reset per visit. Opened doors remain open. The report states movement and transaction limits.",solve)
	solve_button = button("Check current dungeon",solve,start_solver)
	report = TextEdit.new();report.editable = false;report.add_theme_color_override("font_readonly_color",Color("dce5ed"));report.size_flags_vertical = Control.SIZE_EXPAND_FILL;report.custom_minimum_size = Vector2(820,200);content.add_child(report)
	picker = FileDialog.new();picker.access = FileDialog.ACCESS_FILESYSTEM;picker.filters = PackedStringArray(["*.json ; Template library"]);picker.current_dir = game_root.path_join("content/templates");picker.file_selected.connect(file_selected);add_child(picker)
	size_changed.connect(func(): call_deferred("layout_content"));visibility_changed.connect(func(): call_deferred("layout_content"));call_deferred("layout_content")
func layout_content() -> void:
	content.position = Vector2(8,8);content.size = Vector2(size.x-16,size.y-56)
func open_for(pack: Dictionary, selected_room: String, tab: int = 0) -> void:
	if not busy:
		source_pack = pack.duplicate(true);room_id = selected_room
		template_id.text = selected_room.left(40)+"_template"
		include_linked.button_pressed = source_pack.rooms.any(func(room): return room.id == room_id and not room.get("stairs",[]).is_empty())
		custom_reward.button_pressed = false
		reward_x.value = 120;reward_y.value = 77
		refresh_capture_rooms()
		tabs.current_tab = tab
		report.text = "Ready. Results refer to this document snapshot. Recheck after editing."
	popup_centered()
func load_catalog() -> Dictionary:
	var result := Templates.read(catalog_path.text)
	if not result.errors.is_empty(): report.text = "Template library error:\n"+"\n".join(result.errors)
	return result
func set_busy(value: bool) -> void:
	busy = value
	for node in [generate_button,solve_button,save_button]: node.disabled = value
	catalog_path.editable = not value
	seed_input.editable = not value
	count.editable = not value
	custom_layout.disabled = value
	update_layout_controls()
	required_item.disabled = value
	browse_button.disabled = value
	random_seed_button.disabled = value
	include_linked.disabled = value;custom_reward.disabled = value
	refresh_reward_controls()
	use_button.disabled = value or candidate.is_empty()
func start_generation() -> void:
	if busy: return
	if not seed_input.text.is_valid_int() or int(seed_input.text)<0 or int(seed_input.text)>2147483647: report.text = "Seed must be an integer in 0..2147483647";return
	var loaded := load_catalog()
	if not loaded.errors.is_empty(): return
	var catalog: Dictionary = loaded.catalog.duplicate(true)
	var seed_value := int(seed_input.text)
	var room_count := int(count.value)
	var item := required_item.get_item_text(required_item.selected)
	var layout := {"branch_rooms":int(branch_rooms.value),"loop_count":int(loop_count.value)} if custom_layout.button_pressed else {}
	candidate = {};job_kind = "generate";set_busy(true)
	report.text = "Generating and checking progression… The editor stays responsive."
	worker = Thread.new()
	var error := worker.start(func(): return Generator.new().generate(catalog,seed_value,room_count,item,6000,layout))
	if error != OK: set_busy(false);report.text = "Could not start generation: "+error_string(error)
func start_solver() -> void:
	if busy: return
	var snapshot := source_pack.duplicate(true)
	job_kind = "solve";set_busy(true);report.text = "Checking inventory choices and room geometry…"
	worker = Thread.new()
	var error := worker.start(func(): return Solver.new().solve(snapshot))
	if error != OK: set_busy(false);report.text = "Could not start solver: "+error_string(error)
func _process(_delta: float) -> void:
	if not busy or worker == null or worker.is_alive(): return
	var result: Dictionary = worker.wait_to_finish()
	worker = null
	if job_kind == "generate":
		if result.errors.is_empty():
			candidate = result.pack
			report.text = ("Layout: %d branch rooms, %d extra loops\n" % [candidate.generation.branch_rooms,candidate.generation.loop_count] if candidate.generation.algorithm=="authored_graph" else "Layout: classic tree\n")+"Seed %d • %d primary / %d total rooms • attempt %d\nTemplate SHA256: %s\n\n%s" % [candidate.generation.seed,candidate.generation.room_count,candidate.rooms.size(),result.attempts,candidate.generation.template_sha256,Solver.format_report(result.proof)]
		else: report.text = "Generation failed:\n"+"\n".join(result.errors)+("\n\n"+Solver.format_report(result.proof) if result.has("proof") and not result.proof.is_empty() else "")
	else: report.text = Solver.format_report(result)
	set_busy(false)
func file_selected(path: String) -> void:
	if picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE: catalog_path.text = path;invalidate_recipe();return
	if busy: return
	if path.get_extension().to_lower() != "json": path += ".json"
	var absolute := path.simplify_path()
	for folder in ["imported","reference-inputs",".godot","editor/.godot"]:
		if absolute.begins_with(game_root.path_join(folder)+"/"): report.text = "Save authored templates outside generated/local folders.";return
	var loaded: Dictionary = Templates.read(path) if FileAccess.file_exists(path) else load_catalog()
	if not loaded.errors.is_empty(): return
	var ports: Array = [];var requirements: Array = []
	for check in port_checks:
		if check.button_pressed: ports.append(check.text)
	for check in requirement_checks:
		if check.button_pressed: requirements.append(check.text)
	var result := Templates.capture(loaded.catalog,source_pack,room_id,template_id.text,role.get_item_text(role.selected),ports,requirements,include_linked.button_pressed,reward_room.get_item_text(reward_room.selected) if custom_reward.button_pressed and reward_room.selected>=0 else "",[int(reward_x.value),int(reward_y.value)])
	if not result.errors.is_empty(): report.text = "Cannot save template:\n"+"\n".join(result.errors);return
	var error := Pack.write(path,result.catalog)
	if error != OK: report.text = "Template save failed: "+error_string(error);return
	catalog_path.text = path;invalidate_recipe();report.text = "Saved new authored template to "+path+"\nFingerprint: "+Templates.fingerprint(result.catalog)

func invalidate_recipe() -> void:
	if busy: return
	candidate = {}
	if use_button != null: use_button.disabled = true

func use_candidate() -> void:
	if busy or candidate.is_empty(): return
	generated.emit(candidate.duplicate(true))
	hide()

func refresh_capture_rooms() -> void:
	if reward_room == null or source_pack.is_empty(): return
	var old := reward_room.get_item_text(reward_room.selected) if reward_room.selected>=0 else ""
	reward_room.clear()
	var rooms: Array = source_pack.rooms.filter(func(room): return room.id == room_id)
	if include_linked.button_pressed:
		var group := Templates.linked_rooms(source_pack,room_id)
		if group.errors.is_empty(): rooms = group.rooms;capture_info.text = "Capturing %d rooms. Generated rewards use the selected location, or the primary room's default (120,77)." % rooms.size()
		else: capture_info.text = "\n".join(group.errors)
	else: capture_info.text = "Single-room capture. Enable linked cellars to preserve stair destinations."
	for room in rooms: reward_room.add_item(room.id)
	for i in reward_room.item_count:
		if reward_room.get_item_text(i) == old: reward_room.select(i)
	refresh_reward_controls()
func refresh_reward_controls() -> void:
	if reward_room == null: return
	var enabled := not busy and custom_reward.button_pressed
	reward_room.disabled = not enabled
	reward_x.editable = enabled;reward_y.editable = enabled

func update_layout_controls() -> void:
	if branch_rooms==null: return
	branch_rooms.max_value = int(count.value)-6
	if not custom_layout.button_pressed: branch_rooms.value = int(count.value)/4 if count.value>=8 else 0
	branch_rooms.editable = not busy and custom_layout.button_pressed
	loop_count.editable = not busy and custom_layout.button_pressed
