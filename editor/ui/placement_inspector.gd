extends VBoxContainer
signal entity_chosen(kind: String, id: String)
signal properties_applied(properties: Dictionary)
signal duplicate_requested
signal delete_requested
signal rename_requested(id: String)
signal snap_requested
signal reset_requested
const Pack = preload("../shared/room_pack.gd")
var list: ItemList
var form: VBoxContainer
var identity: LineEdit
var x: SpinBox
var y: SpinBox
var enemy_fields: VBoxContainer
var pickup_fields: VBoxContainer
var variant: OptionButton
var enemy_title: LineEdit
var behavior: OptionButton
var health: SpinBox
var speed: SpinBox
var shooting: CheckBox
var damage: SpinBox
var item: OptionButton
var secret_reward: CheckBox
var clear_reward: CheckBox
var objective: CheckBox
var duplicate_button: Button
var delete_button: Button
var rename_button: Button
var hint: Label
var current_kind := ""
var definitions: Dictionary = {}
func label(text: String, parent: Node) -> Label:
	var node := Label.new();node.text = text;node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;parent.add_child(node);return node
func button(text: String, parent: Node, action: Callable) -> Button:
	var node := Button.new();node.text = text;node.pressed.connect(action);parent.add_child(node);return node
func number(text: String, parent: Node, minimum: int, maximum: int) -> SpinBox:
	var row := HBoxContainer.new();parent.add_child(row)
	var caption := Label.new();caption.text = text;caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL;row.add_child(caption)
	var field := SpinBox.new();field.min_value = minimum;field.max_value = maximum;field.custom_minimum_size.x = 105;row.add_child(field);return field
func options(values: Array, parent: Node) -> OptionButton:
	var field := OptionButton.new();field.clip_text = true
	for value in values: field.add_item(str(value))
	parent.add_child(field);return field
func choice(field: OptionButton) -> String: return field.get_item_text(field.selected) if field.selected>=0 else ""
func pick(field: OptionButton, value: String) -> void:
	for i in range(field.item_count):
		if field.get_item_text(i) == value: field.select(i);return
func _ready() -> void:
	var title := label("PLACEMENTS",self);title.add_theme_color_override("font_color",Color("86d1ad"))
	list = ItemList.new();list.custom_minimum_size.y = 110;list.allow_reselect = true;add_child(list)
	list.item_selected.connect(func(index):
		var key: Dictionary = list.get_item_metadata(index)
		entity_chosen.emit(key.kind,key.id))
	hint = label("Click a placement or choose it here. Alt-click cycles overlaps. Drag or use arrows to move.",self)
	form = VBoxContainer.new();add_child(form)
	var identity_row := HBoxContainer.new();form.add_child(identity_row)
	identity = LineEdit.new();identity.tooltip_text = "Placement ID. Renaming keeps old checkpoints' progress.";identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL;identity_row.add_child(identity)
	identity.text_submitted.connect(func(text): if current_kind != "spawn": rename_requested.emit(text.strip_edges()))
	rename_button = button("Rename ID",identity_row,func(): if current_kind != "spawn": rename_requested.emit(identity.text.strip_edges()))
	x = number("X (pixels)",form,0,240);y = number("Y (pixels)",form,0,157)
	button("Snap position to 8-pixel grid",form,func(): snap_requested.emit())
	enemy_fields = VBoxContainer.new();form.add_child(enemy_fields)
	label("Enemy variant",enemy_fields);variant = options([],enemy_fields)
	variant.item_selected.connect(func(_i): refresh_variant())
	enemy_title = LineEdit.new();enemy_title.tooltip_text = "Display title; this does not rename the placement ID.";enemy_fields.add_child(enemy_title)
	behavior = options(Pack.BEHAVIORS,enemy_fields)
	health = number("Health",enemy_fields,1,255)
	speed = number("Speed / 256",enemy_fields,0,2048)
	damage = number("Half-heart damage",enemy_fields,0,16)
	shooting = CheckBox.new();shooting.text = "Walker shoots rocks";enemy_fields.add_child(shooting)
	label("Stat edits affect this placement. A shared variant is copied automatically; other enemies keep their settings.",enemy_fields)
	pickup_fields = VBoxContainer.new();form.add_child(pickup_fields)
	item = options(Pack.ITEMS,pickup_fields)
	clear_reward = CheckBox.new();clear_reward.text = "Appears after room clear";pickup_fields.add_child(clear_reward)
	secret_reward = CheckBox.new();secret_reward.text = "Appears after room secret";pickup_fields.add_child(secret_reward)
	objective = CheckBox.new();objective.text = "Required objective";pickup_fields.add_child(objective)
	button("Apply selected changes",form,apply)
	button("Reset fields",form,func(): reset_requested.emit())
	var actions := HBoxContainer.new();form.add_child(actions)
	duplicate_button = button("Duplicate",actions,func(): duplicate_requested.emit())
	delete_button = button("Delete",actions,func(): delete_requested.emit())
	form.visible = false
func refresh(room: Dictionary, pack: Dictionary, key: Dictionary, data: Dictionary) -> void:
	definitions = pack.enemy_types
	list.clear()
	var entries: Array = [{"kind":"spawn","id":"","name":"Player spawn"}]
	for e in room.enemies: entries.append({"kind":"enemies","id":e.id,"name":"Enemy: "+String(e.id)+" ("+String(e.type)+")"})
	for p in room.pickups: entries.append({"kind":"pickups","id":p.id,"name":("★ " if is_objective(pack,room.id,p.id) else "")+"Pickup: "+String(p.id)+" ("+String(p.item)+")"})
	for entry in entries:
		list.add_item(entry.name);list.set_item_metadata(list.item_count-1,{"kind":entry.kind,"id":entry.id});list.set_item_tooltip(list.item_count-1,entry.name)
		if key.get("room") == room.id and key.get("kind") == entry.kind and key.get("id") == entry.id: list.select(list.item_count-1)
	form.visible = not data.is_empty()
	if data.is_empty(): current_kind = "";return
	current_kind = key.kind
	identity.text = "Player spawn (fixed)" if current_kind == "spawn" else String(key.id)
	x.value = data.position[0];y.value = data.position[1]
	enemy_fields.visible = current_kind == "enemies";pickup_fields.visible = current_kind == "pickups"
	duplicate_button.disabled = current_kind == "spawn";delete_button.disabled = current_kind == "spawn"
	identity.editable = current_kind != "spawn";rename_button.disabled = current_kind == "spawn"
	if current_kind == "enemies":
		variant.clear()
		for id in definitions: variant.add_item(id);variant.set_item_tooltip(variant.item_count-1,definitions[id].title+" ["+id+"]")
		pick(variant,data.type);refresh_variant()
	if current_kind == "pickups":
		pick(item,data.item);clear_reward.button_pressed = data.get("requires_clear",false)
		secret_reward.button_pressed = data.get("requires_secret",false)
		objective.button_pressed = is_objective(pack,room.id,key.id)
func refresh_variant() -> void:
	if variant.selected<0 or not definitions.has(choice(variant)): return
	var source: Dictionary = definitions[choice(variant)]
	enemy_title.text = source.title;pick(behavior,source.behavior)
	health.value = source.health;speed.value = source.speed_subpixels;damage.value = source.contact_damage
	shooting.button_pressed = source.get("shooting_enabled",false)
func apply() -> void:
	if current_kind.is_empty(): return
	var properties := {"position":[int(x.value),int(y.value)]}
	if current_kind == "enemies": properties.merge({"type":choice(variant),"settings":{"title":enemy_title.text,"behavior":choice(behavior),"health":int(health.value),"speed_subpixels":int(speed.value),"contact_damage":int(damage.value)}})
	if current_kind=="enemies" and (shooting.button_pressed or definitions[choice(variant)].has("shooting_enabled")): properties.settings.shooting_enabled = shooting.button_pressed and choice(behavior)=="walker"
	if current_kind == "pickups": properties.merge({"item":choice(item),"requires_clear":clear_reward.button_pressed,"requires_secret":secret_reward.button_pressed,"objective":objective.button_pressed})
	properties_applied.emit(properties)
static func is_objective(pack: Dictionary, room: String, id: String) -> bool:
	return pack.get("goals",[]).any(func(goal): return goal.room == room and goal.pickup == id)
