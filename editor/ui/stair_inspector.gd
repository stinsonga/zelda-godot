extends VBoxContainer
signal applied(stair: Dictionary)
signal removed(id: String)
signal cave_requested(stair: Dictionary)
signal cellar_requested(stair: Dictionary)
const Pack = preload("../shared/room_pack.gd")
var list: ItemList
var identity: LineEdit
var cell_x: SpinBox
var cell_y: SpinBox
var target: OptionButton
var arrival_x: SpinBox
var arrival_y: SpinBox
var secret_gate: CheckBox
var selected_id := ""
var room_id := ""
var room: Dictionary = {}
func caption(text: String) -> Label:
	var node := Label.new();node.text = text;node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;add_child(node);return node
func number(text: String, low: int, high: int, initial: int, step: int = 1) -> SpinBox:
	var row := HBoxContainer.new();add_child(row)
	var label := Label.new();label.text = text;label.size_flags_horizontal = Control.SIZE_EXPAND_FILL;row.add_child(label)
	var field := SpinBox.new();field.min_value = low;field.max_value = high;field.step = step;field.value = initial;field.custom_minimum_size.x = 110;row.add_child(field);return field
func button(text: String, action: Callable) -> void:
	var node := Button.new();node.text = text;node.pressed.connect(action);add_child(node)
func _ready() -> void:
	caption("STAIRS / CELLAR LINKS").add_theme_color_override("font_color",Color("86d1ad"))
	list = ItemList.new();list.custom_minimum_size.y = 85;list.allow_reselect = true;add_child(list)
	list.item_selected.connect(func(i): choose(list.get_item_metadata(i)))
	identity = LineEdit.new();identity.editable = false;add_child(identity)
	cell_x = number("Cell X",3,12,6);cell_y = number("Cell Y",3,7,5)
	secret_gate = CheckBox.new();secret_gate.text = "Hidden until block push";add_child(secret_gate)
	caption("Destination room")
	target = OptionButton.new();target.clip_text = true;add_child(target)
	target.item_selected.connect(func(_i):
		var pack: Dictionary = get_meta("pack",{})
		for destination in pack.get("rooms",[]):
			if destination.id == choice(): arrival_x.value = destination.spawn[0];arrival_y.value = destination.spawn[1])
	arrival_x = number("Arrival X (pixels)",0,240,48,8)
	arrival_y = number("Arrival Y (pixels)",5,157,61,8)
	button("New stair link",func(): selected_id = "";identity.text = "New link (ID assigned on Apply)";list.deselect_all())
	button("Apply stair link",func(): applied.emit(value()))
	button("Delete selected stair",func():
		if not selected_id.is_empty(): removed.emit(selected_id))
	button("Create linked cave",func(): cave_requested.emit(value()))
	button("Create linked cellar",func(): cellar_requested.emit(value()))
	caption("Stairs activate when stepped on. Cellars are editable rooms with a return stair. Arrival uses the dungeon grid; links can be one-way.")
func choice() -> String: return target.get_item_text(target.selected) if target.selected>=0 else ""
func value() -> Dictionary:
	return {"id":selected_id,"cell":[int(cell_x.value),int(cell_y.value)],"target":choice(),"target_position":[int(arrival_x.value),int(arrival_y.value)],"requires_secret":secret_gate.button_pressed}
func choose(id: String) -> void:
	selected_id = id
	for stair in room.get("stairs",[]):
		if stair.id != id: continue
		identity.text = id;cell_x.value = stair.cell[0];cell_y.value = stair.cell[1];secret_gate.button_pressed = stair.get("requires_secret",false)
		for i in target.item_count:
			if target.get_item_text(i) == stair.target: target.select(i)
		arrival_x.value = stair.target_position[0];arrival_y.value = stair.target_position[1]
		for i in list.item_count:
			if list.get_item_metadata(i) == id: list.select(i)
		return
	identity.text = "New link (ID assigned on Apply)"
func refresh(source: Dictionary, pack: Dictionary) -> void:
	if room_id != source.id: selected_id = ""
	room_id = source.id;room = source;set_meta("pack",pack)
	var old_target := choice();target.clear()
	for destination in pack.rooms:
		if destination.id != source.id: target.add_item(destination.id)
	for i in target.item_count:
		if target.get_item_text(i) == old_target: target.select(i)
	list.clear()
	for stair in source.get("stairs",[]):
		list.add_item(("Hidden: " if stair.get("requires_secret",false) else "")+String(stair.id)+" → "+String(stair.target));list.set_item_metadata(list.item_count-1,stair.id)
	choose(selected_id)
