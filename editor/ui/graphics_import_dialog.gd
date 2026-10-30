extends AcceptDialog
signal imported(id: String)
const Importer = preload("../shared/authored_library.gd")
var game_root := ""
var edit_id := ""
var original_asset: Dictionary = {}
var display_name: LineEdit
var browse: Button
var apply_button: Button
var note: Label
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
var frame_width: SpinBox
var frame_height: SpinBox
var draw_width: SpinBox
var draw_height: SpinBox
var offset_x: SpinBox
var offset_y: SpinBox
var clip_controls: Dictionary = {}
var scroller: ScrollContainer
var content: VBoxContainer
func line(caption: String, value: String, parent: Node) -> LineEdit:
	var row := HBoxContainer.new();parent.add_child(row)
	var label := Label.new();label.text = caption;label.custom_minimum_size.x = 135;row.add_child(label)
	var field := LineEdit.new();field.text = value;field.size_flags_horizontal = Control.SIZE_EXPAND_FILL;row.add_child(field);return field
func _ready() -> void:
	title = "Import authored PNG graphics";wrap_controls = false;min_size = Vector2i(680,650);size = Vector2i(700,670);get_ok_button().text = "Close"
	scroller = ScrollContainer.new();scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroller)
	content = VBoxContainer.new();content.size_flags_horizontal = Control.SIZE_EXPAND_FILL;scroller.add_child(content)
	note = Label.new();note.text = "Copies authored PNG graphics into shared content/art/. ROM imports remain separate. Sprite columns are frames; rows are directions. Logical game sizes and collision stay unchanged.";note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(note)
	source = line("PNG file","",content)
	browse = Button.new();browse.text = "Choose PNG…";content.add_child(browse)
	library_id = line("Library ID","custom_art",content);asset_id = line("Asset ID","",content)
	display_name = line("Display name","",content);display_name.get_parent().visible = false
	var row := HBoxContainer.new();content.add_child(row)
	kind = OptionButton.new();kind.add_item("tiles");kind.add_item("sprite");row.add_child(kind)
	var cell_label := Label.new();cell_label.text = "Source cell pixels";row.add_child(cell_label)
	cell_size = OptionButton.new()
	for value in [16,32,64]: cell_size.add_item(str(value))
	row.add_child(cell_size)
	var source_fields := pair("Frame W", "H (source pixels)",1,256,16)
	frame_width = source_fields[0];frame_height = source_fields[1]
	var draw_fields := pair("Draw W", "H (logical pixels)",1,128,16)
	draw_width = draw_fields[0];draw_height = draw_fields[1]
	var offset_fields := pair("Offset X", "Y (logical pixels)",-128,128,0)
	offset_x = offset_fields[0];offset_y = offset_fields[1]
	offset_x.tooltip_text = "Drawing offset from the unchanged object's top-left; negative Y draws above it"
	offset_y.tooltip_text = offset_x.tooltip_text
	directions = line("Direction rows","all",content)
	directions.tooltip_text = "Comma-separated all, or selected down/up/right/left rows in sheet order"
	var timing := HBoxContainer.new();content.add_child(timing)
	var label := Label.new();label.text = "Frame columns";timing.add_child(label)
	frames = SpinBox.new();frames.min_value = 1;frames.max_value = 16;timing.add_child(frames)
	label = Label.new();label.text = "Ticks per frame";timing.add_child(label)
	ticks = SpinBox.new();ticks.min_value = 1;ticks.max_value = 120;ticks.value = 6;timing.add_child(ticks)
	var hint := Label.new();hint.text = "Optional clips: zero-based frame columns. Idle/walk loop; attack plays once.";hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(hint)
	for name in ["idle","walk","attack"]:
		var clip_row := HBoxContainer.new();content.add_child(clip_row)
		var enabled := CheckBox.new();enabled.text = name;enabled.custom_minimum_size.x = 90;clip_row.add_child(enabled)
		var indices := LineEdit.new();indices.text = "0,1" if name=="walk" else "0";indices.placeholder_text = "Frame columns: 0,1,2";indices.size_flags_horizontal = Control.SIZE_EXPAND_FILL;clip_row.add_child(indices)
		var label_ticks := Label.new();label_ticks.text = "Ticks/frame";clip_row.add_child(label_ticks)
		var clip_ticks := SpinBox.new();clip_ticks.min_value = 1;clip_ticks.max_value = 120;clip_ticks.value = 6;clip_row.add_child(clip_ticks)
		clip_controls[name] = {"enabled":enabled,"frames":indices,"ticks":clip_ticks}
	apply_button = Button.new();apply_button.text = "Import into shared library";apply_button.pressed.connect(import_asset);content.add_child(apply_button)
	result_text = Label.new();result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;content.add_child(result_text)
	picker = FileDialog.new();picker.access = FileDialog.ACCESS_FILESYSTEM;picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE;picker.filters = PackedStringArray(["*.png ; PNG graphics"]);add_child(picker)
	browse.pressed.connect(func(): picker.popup_centered_ratio(0.7))
	picker.file_selected.connect(func(path):
		source.text = path
		if asset_id.text.is_empty():
			var name: String = String(path).get_file().get_basename().to_lower();var slug := ""
			for c in name: slug += c if c in "abcdefghijklmnopqrstuvwxyz0123456789_-" else "_"
			asset_id.text = slug.left(64))
	kind.item_selected.connect(func(_index): refresh_inputs())
	refresh_inputs()
	size_changed.connect(func(): call_deferred("layout_content"))
	visibility_changed.connect(func(): call_deferred("layout_content"))
	call_deferred("layout_content")
func pair(first: String, second: String, low: int, high: int, initial: int) -> Array:
	var row := HBoxContainer.new();content.add_child(row)
	var result: Array = []
	for caption in [first,second]:
		var label := Label.new();label.text = caption;row.add_child(label)
		var field := SpinBox.new();field.min_value = low;field.max_value = high;field.value = initial;row.add_child(field);result.append(field)
	return result
func refresh_inputs() -> void:
	var sprite := kind.selected == 1
	cell_size.disabled = sprite
	for field in [frame_width,frame_height,draw_width,draw_height,offset_x,offset_y,frames,ticks]: field.editable = sprite
	directions.editable = sprite
	for controls in clip_controls.values():
		controls.enabled.disabled = not sprite;controls.frames.editable = sprite;controls.ticks.editable = sprite
func layout_content() -> void:
	scroller.position = Vector2(8,8)
	scroller.size = Vector2(size.x-16,size.y-56)
func import_asset() -> void:
	var rows: Array = []
	for value in directions.text.split(","): rows.append(value.strip_edges())
	var clips: Dictionary = {}
	if kind.selected==1:
		for name in clip_controls:
			var controls: Dictionary = clip_controls[name]
			if not controls.enabled.button_pressed: continue
			var indices: Array = []
			for value in controls.frames.text.split(","):
				if not value.strip_edges().is_valid_int(): result_text.text = "Clip frames need comma-separated integer columns";return
				indices.append(value.strip_edges().to_int())
			clips[name] = {"frames":indices,"frame_ticks":int(controls.ticks.value),"loop":name!="attack"}
	if not edit_id.is_empty():
		var settings := {"name":display_name.text}
		if kind.selected==0: settings.cell_size = int(cell_size.get_item_text(cell_size.selected))
		else:
			settings.merge({"frame_size":[int(frame_width.value),int(frame_height.value)],"draw_size":[int(draw_width.value),int(draw_height.value)],"draw_offset":[int(offset_x.value),int(offset_y.value)],"directions":rows,"frames":int(frames.value),"frame_ticks":int(ticks.value),"clips":clips})
		var saved := Importer.update_asset(game_root,edit_id,settings,original_asset)
		if not saved.errors.is_empty(): result_text.text = "\n".join(saved.errors);return
		var reloaded := Importer.asset_record(game_root,edit_id)
		if reloaded.errors.is_empty(): original_asset = reloaded.asset
		result_text.text = "Saved "+edit_id+". Library changes are separate from pack undo."
		imported.emit(edit_id)
		return
	var result := Importer.import_png(game_root,source.text,library_id.text,asset_id.text,kind.get_item_text(kind.selected),int(cell_size.get_item_text(cell_size.selected)),rows,int(frames.value),int(ticks.value),[int(frame_width.value),int(frame_height.value)],[int(draw_width.value),int(draw_height.value)],[int(offset_x.value),int(offset_y.value)],clips)
	if not result.errors.is_empty(): result_text.text = "\n".join(result.errors);return
	result_text.text = "Imported "+String(result.id)+"\n"+String(result.manifest)
	imported.emit(result.id)

func open_import(root: String) -> void:
	game_root = root;edit_id = "";original_asset = {};apply_button.disabled = false
	title = "Import authored PNG graphics"
	note.text = "Copies authored PNG graphics into shared content/art/. ROM imports remain separate. Sprite columns are frames; rows are directions. Logical game sizes and collision stay unchanged."
	source.editable = true;library_id.editable = true;asset_id.editable = true;kind.disabled = false;browse.disabled = false
	display_name.get_parent().visible = false;apply_button.text = "Import into shared library";result_text.text = ""
	source.text = "";library_id.text = "custom_art";asset_id.text = ""
	refresh_inputs();popup_centered()
func open_asset(root: String, id: String) -> void:
	var loaded := Importer.asset_record(root,id)
	if not loaded.errors.is_empty():
		edit_id = "";original_asset = {};apply_button.disabled = true;result_text.text = "\n".join(loaded.errors);popup_centered();return
	game_root = root;edit_id = id;original_asset = loaded.asset;apply_button.disabled = false
	title = "Edit authored asset settings"
	note.text = "Changes affect every use of this asset. PNGs and IDs stay fixed. Library edits are separate from pack undo. Changing a tile grid reinterprets existing tile indices."
	source.text = loaded.image;source.editable = false;browse.disabled = true
	library_id.text = id.get_slice("/",1);asset_id.text = id.get_slice("/",2);library_id.editable = false;asset_id.editable = false
	var asset: Dictionary = loaded.asset
	display_name.get_parent().visible = true;display_name.text = asset.name
	kind.select(0 if asset.kind=="tiles" else 1);kind.disabled = true
	for i in cell_size.item_count:
		if int(cell_size.get_item_text(i))==int(asset.get("cell_size",16)): cell_size.select(i)
	var frame: Array = asset.get("frame_size",[16,16]);frame_width.value = frame[0];frame_height.value = frame[1]
	var draw: Array = asset.get("draw_size",[16,16]);draw_width.value = draw[0];draw_height.value = draw[1]
	var offset: Array = asset.get("draw_offset",[0,0]);offset_x.value = offset[0];offset_y.value = offset[1]
	directions.text = ",".join(asset.get("directions",["all"]));frames.value = asset.get("frames",1);ticks.value = asset.get("frame_ticks",6)
	for name in clip_controls:
		var controls: Dictionary = clip_controls[name]
		controls.enabled.button_pressed = asset.get("clips",{}).has(name)
		var clip: Dictionary = asset.get("clips",{}).get(name,{"frames":[0],"frame_ticks":6})
		controls.frames.text = ",".join(clip.frames.map(func(index): return str(int(index))));controls.ticks.value = clip.frame_ticks
	apply_button.text = "Save asset settings";result_text.text = "";refresh_inputs();popup_centered()
