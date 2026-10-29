extends VBoxContainer
signal applied(data: Dictionary)
signal reset_requested
const Pack = preload("../shared/room_pack.gd")
var mode: OptionButton
var form: VBoxContainer
var dialogue: TextEdit
var items: Array[OptionButton] = []
var prices: Array[SpinBox] = []
func _ready() -> void:
	var title := Label.new();title.text = "CAVE / RESIDENT";title.add_theme_color_override("font_color",Color("86d1ad"));add_child(title)
	mode = OptionButton.new()
	for name in ["none","hint","gift","shop"]: mode.add_item(name)
	add_child(mode)
	form = VBoxContainer.new();add_child(form)
	dialogue = TextEdit.new();dialogue.custom_minimum_size.y = 90;dialogue.placeholder_text = "Up to 3 lines, 24 characters each";form.add_child(dialogue)
	for i in range(3):
		var row := HBoxContainer.new();form.add_child(row)
		var label := Label.new();label.text = ["Left","Middle","Right"][i];label.custom_minimum_size.x = 55;row.add_child(label)
		var choice := OptionButton.new();choice.clip_text = true;choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item in ["empty"]+Pack.ITEMS: choice.add_item(item)
		row.add_child(choice);items.append(choice)
		var price := SpinBox.new();price.min_value = 0;price.max_value = 255;price.custom_minimum_size.x = 85;row.add_child(price);prices.append(price)
	var note := Label.new();note.text = "Hint: text only. Gift: one free item, once per room. Shop: one purchase per visit; prices are rupees. Resident rooms have no enemies or blocks.";note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;form.add_child(note)
	var apply_button := Button.new();apply_button.text = "Apply resident / remove if none";apply_button.pressed.connect(func(): applied.emit(value()));add_child(apply_button)
	var reset_button := Button.new();reset_button.text = "Reset resident fields";reset_button.pressed.connect(func(): reset_requested.emit());add_child(reset_button)
	mode.item_selected.connect(func(_i):
		if choice() != "none":
			var preset := Pack.resident(choice())
			if dialogue.text.is_empty(): dialogue.text = preset.text
			set_wares(preset.wares)
		refresh_mode())
	refresh_mode()
func choice() -> String: return mode.get_item_text(mode.selected)
func set_wares(wares: Array) -> void:
	for i in range(3):
		items[i].select(0);prices[i].value = 0
		if wares[i] == null: continue
		for j in items[i].item_count:
			if items[i].get_item_text(j) == wares[i].item: items[i].select(j)
		prices[i].value = wares[i].price
func refresh_mode() -> void:
	form.visible = choice() != "none"
	for i in range(3):
		items[i].disabled = choice() == "hint"
		prices[i].editable = choice() == "shop"
func refresh(room: Dictionary) -> void:
	var data: Dictionary = room.get("resident",{})
	var kind := String(data.get("mode","none"))
	for i in mode.item_count:
		if mode.get_item_text(i) == kind: mode.select(i)
	dialogue.text = data.get("text","");set_wares(data.get("wares",[null,null,null]));refresh_mode()
func value() -> Dictionary:
	if choice() == "none": return {}
	var wares: Array = []
	for i in range(3): wares.append(null if items[i].selected == 0 else {"item":items[i].get_item_text(items[i].selected),"price":int(prices[i].value)})
	return {"mode":choice(),"text":dialogue.text,"wares":wares}
