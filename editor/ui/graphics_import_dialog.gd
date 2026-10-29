extends AcceptDialog
signal imported(id: String)
const Importer = preload("../shared/authored_library.gd")
var game_root := ""
var source: LineEdit
var library_id: LineEdit
var asset_id: LineEdit
var kind: OptionButton
var cell_size: OptionButton
var directions: LineEdit
var frames: SpinBox
var ticks: SpinBox
var result_text: Label
var picker: FileDialog
var content: VBoxContainer
func line(caption: String, value: String, parent: Node) -> LineEdit:
	var row := HBoxContainer.new();parent.add_child(row)
	var label := Label.new();label.text = caption;label.custom_minimum_size.x = 135;row.add_child(label)
	var field := LineEdit.new();field.text = value;field.size_flags_horizontal = Control.SIZE_EXPAND_FILL;row.add_child(field);return field
func _ready() -> void:
	title = "Import authored PNG graphics";wrap_controls = false;min_size = Vector2i(660,530);size = Vector2i(680,550);get_ok_button().text = "Close"
	content = VBoxContainer.new();add_child(content)
	var note := Label.new();note.text = "Copies authored PNG graphics into shared content/art/. ROM imports remain separate. Sprite columns are frames; rows are directions. Logical game sizes and collision stay unchanged.";note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(note)
	source = line("PNG file","",content)
	var browse := Button.new();browse.text = "Choose PNG…";content.add_child(browse)
	library_id = line("Library ID","custom_art",content);asset_id = line("Asset ID","",content)
	var row := HBoxContainer.new();content.add_child(row)
	kind = OptionButton.new();kind.add_item("tiles");kind.add_item("sprite");row.add_child(kind)
	var cell_label := Label.new();cell_label.text = "Source cell pixels";row.add_child(cell_label)
	cell_size = OptionButton.new()
	for value in [16,32,64]: cell_size.add_item(str(value))
	row.add_child(cell_size)
	directions = line("Direction rows","all",content)
	directions.tooltip_text = "Comma-separated all, or selected down/up/right/left rows in sheet order"
	var timing := HBoxContainer.new();content.add_child(timing)
	var label := Label.new();label.text = "Frame columns";timing.add_child(label)
	frames = SpinBox.new();frames.min_value = 1;frames.max_value = 16;timing.add_child(frames)
	label = Label.new();label.text = "Ticks per frame";timing.add_child(label)
	ticks = SpinBox.new();ticks.min_value = 1;ticks.max_value = 120;ticks.value = 6;timing.add_child(ticks)
	var apply := Button.new();apply.text = "Import into shared library";apply.pressed.connect(import_asset);content.add_child(apply)
	result_text = Label.new();result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(result_text)
	picker = FileDialog.new();picker.access = FileDialog.ACCESS_FILESYSTEM;picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE;picker.filters = PackedStringArray(["*.png ; PNG graphics"]);add_child(picker)
	browse.pressed.connect(func(): picker.popup_centered_ratio(0.7))
	picker.file_selected.connect(func(path):
		source.text = path
		if asset_id.text.is_empty():
			var name: String = String(path).get_file().get_basename().to_lower();var slug := ""
			for c in name: slug += c if c in "abcdefghijklmnopqrstuvwxyz0123456789_-" else "_"
			asset_id.text = slug.left(64))
	size_changed.connect(func(): call_deferred("layout_content"))
	visibility_changed.connect(func(): call_deferred("layout_content"))
	call_deferred("layout_content")
func layout_content() -> void:
	content.position = Vector2(8,8)
	content.size = Vector2(size.x-16,size.y-56)
func import_asset() -> void:
	var rows: Array = []
	for value in directions.text.split(","): rows.append(value.strip_edges())
	var result := Importer.import_png(game_root,source.text,library_id.text,asset_id.text,kind.get_item_text(kind.selected),int(cell_size.get_item_text(cell_size.selected)),rows,int(frames.value),int(ticks.value))
	if not result.errors.is_empty(): result_text.text = "\n".join(result.errors);return
	result_text.text = "Imported "+String(result.id)+"\n"+String(result.manifest)
	imported.emit(result.id)
