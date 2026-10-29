extends VBoxContainer
signal applied(secret: Dictionary)
signal removed
var trigger: OptionButton
var hint: Label
var cell_x: SpinBox
var cell_y: SpinBox
var direction: OptionButton
var reveal: OptionButton
var summary: Label
const Pack = preload("../shared/room_pack.gd")
func _ready() -> void:
	var title := Label.new();title.text = "ROOM SECRET";title.add_theme_color_override("font_color",Color("86d1ad"));add_child(title)
	trigger = OptionButton.new()
	for kind in ["block","bomb","fire"]: trigger.add_item(kind)
	add_child(trigger)
	trigger.item_selected.connect(func(_i): refresh_trigger())
	summary = Label.new();summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;add_child(summary)
	var row := HBoxContainer.new();add_child(row)
	for axis in ["Cell X","Cell Y"]:
		var caption := Label.new();caption.text = axis;row.add_child(caption)
		var field := SpinBox.new();field.min_value = 2;field.max_value = 13 if axis == "Cell X" else 8;field.value = 6 if axis == "Cell X" else 5;row.add_child(field)
		if axis == "Cell X": cell_x = field
		else: cell_y = field
	direction = OptionButton.new()
	for edge in Pack.EDGES: direction.add_item(edge)
	direction.select(1);add_child(direction)
	direction.tooltip_text = "Allowed push direction; block moves one tile after all enemies are defeated."
	reveal = OptionButton.new();reveal.add_item("shutters");reveal.add_item("item");add_child(reveal)
	reveal.tooltip_text = "Shutters: push opens room shutters. Item: push reveals secret-gated pickups. Both allow secret-gated pickups."
	var apply_button := Button.new();apply_button.text = "Apply room secret";apply_button.pressed.connect(func(): applied.emit(value()));add_child(apply_button)
	var remove_button := Button.new();remove_button.text = "Remove room secret";remove_button.pressed.connect(func(): removed.emit());add_child(remove_button)
	hint = Label.new();hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;add_child(hint)
	refresh_trigger()
func value() -> Dictionary:
	var data := {"cell":[int(cell_x.value),int(cell_y.value)],"direction":direction.get_item_text(direction.selected),"reveal":reveal.get_item_text(reveal.selected)}
	if trigger.selected>0: data.trigger = trigger.get_item_text(trigger.selected)
	return data
func refresh(room: Dictionary) -> void:
	summary.text = "No secret in this room." if not room.has("secret") else "%s at (%d, %d), direction %s; reveals %s." % [Pack.secret_trigger(room.secret).capitalize(),room.secret.cell[0],room.secret.cell[1],room.secret.direction,room.secret.reveal]
	if not room.has("secret"): return
	for i in trigger.item_count:
		if trigger.get_item_text(i) == Pack.secret_trigger(room.secret): trigger.select(i)
	refresh_trigger()
	cell_x.value = room.secret.cell[0];cell_y.value = room.secret.cell[1]
	for i in direction.item_count:
		if direction.get_item_text(i) == room.secret.direction: direction.select(i)
	reveal.select(0 if room.secret.reveal == "shutters" else 1)

func refresh_trigger() -> void:
	if hint == null: return
	var kind := trigger.get_item_text(trigger.selected)
	hint.text = "One secret per room. Use Secret brush to place. " + ("Push one tile after clearing enemies; resets on re-entry. Approach is one tile behind direction." if kind == "block" else "Bomb: stand one tile behind direction. Costs one bomb; reveal persists." if kind == "bomb" else "Fire: stand two tiles behind direction. Requires candle; reveal persists.")
	direction.tooltip_text = "Push direction" if kind == "block" else "Facing from the validated item-use position toward the object"
