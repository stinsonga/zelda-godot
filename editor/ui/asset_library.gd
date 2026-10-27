extends VBoxContainer
## Optional local library. Art choices emit symbolic IDs, never mutate packs.
const Appearance = preload("../shared/appearance.gd")
const Preview = preload("asset_preview.gd")
signal enemy_chosen(group_id: String)
signal tile_chosen(atlas_id: String, index: int)
var library = Appearance.new()
var selected_entry: Dictionary = {}
var enemy_apply: Button
var tile_apply: Button
var frame_clock := 0.0
var direction: OptionButton
var game_root := ""
var entries: Array = []
var shown: Array = []
var catalog_message := ""
var search: LineEdit
var category: OptionButton
var summary: Label
var list: ItemList
var preview: Control
var details: Label
var refresh_button: Button
func _ready() -> void:
	var tools := HBoxContainer.new()
	add_child(tools)
	search = LineEdit.new()
	search.placeholder_text = "Filter images (e.g. stalfos, octorok, level 1)"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(search)
	search.text_changed.connect(func(_text): populate())
	category = OptionButton.new()
	for value in ["all","sprites","tiles","interface"]: category.add_item(value)
	tools.add_child(category)
	category.item_selected.connect(func(_index): populate())
	refresh_button = Button.new()
	refresh_button.text = "Refresh library"
	tools.add_child(refresh_button)
	refresh_button.pressed.connect(func(): load_catalog(game_root))
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(summary)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	list = ItemList.new()
	list.custom_minimum_size.x = 300
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.fixed_icon_size = Vector2i(40,40)
	list.item_selected.connect(select_image)
	body.add_child(list)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 250
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	preview = Preview.new()
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(preview)
	preview.tile_selected.connect(func(index):
		if not selected_entry.is_empty(): details.text = String(selected_entry.path) + "\nSelected tile: " + str(index))
	direction = OptionButton.new()
	for value in ["down","up","right","left"]: direction.add_item(value)
	right.add_child(direction)
	direction.item_selected.connect(func(_i): update_frame())
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(details)
	enemy_apply = Button.new()
	enemy_apply.text = "Use sprite set for selected enemy variant"
	enemy_apply.disabled = true
	enemy_apply.pressed.connect(func(): enemy_chosen.emit(selected_entry.id))
	right.add_child(enemy_apply)
	tile_apply = Button.new()
	tile_apply.text = "Paint selected atlas tile in Room"
	tile_apply.disabled = true
	tile_apply.pressed.connect(func(): tile_chosen.emit(selected_entry.id,preview.selected_tile))
	right.add_child(tile_apply)
	var note := Label.new()
	note.text = "ROM art choices are local. Enemy stats and terrain collision stay in the shared pack."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
func checked_path(relative: String) -> String:
	if relative.is_empty() or relative.is_absolute_path() or "\\" in relative or ":" in relative or relative.get_extension().to_lower() != "png": return ""
	if ".." in relative.split("/"): return ""
	return game_root.path_join("imported").path_join(relative).simplify_path()
func load_catalog(root_path: String) -> void:
	game_root = root_path
	entries.clear()
	library.configure(root_path)
	var filename := game_root.path_join("imported/editor_catalog.json")
	if not FileAccess.file_exists(filename):
		catalog_message = "No editor image catalog. Use Import ROM… to create the local library."
		populate()
		return
	var file := FileAccess.open(filename,FileAccess.READ)
	if file == null or file.get_length() > 4000000:
		catalog_message = "Cannot read image catalog (or it exceeds 4 MB). Reimport to rebuild it."
		populate()
		return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.get("format_version") != 1 or not data.get("entries") is Array or not data.get("source") is Dictionary:
		catalog_message = "Unsupported image catalog. Reimport to rebuild it."
		populate()
		return
	if data.source.get("prg_sha1") != "a12d74c73a0481599a5d832361d168f4737bbcf6":
		catalog_message = "Unsupported image source revision. Reimport the supported US PRG0 ROM."
		populate()
		return
	for entry in data.entries:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("name") is String or entry.get("category") not in ["sprites","tiles","interface"] or checked_path(entry.path).is_empty():
			entries.clear()
			catalog_message = "Invalid image entry. Reimport to rebuild the catalog."
			populate()
			return
		entries.append(entry)
	catalog_message = "%d local ROM images • US PRG0" % entries.size()
	populate()
func texture(relative: String) -> Texture2D:
	var filename := checked_path(relative)
	if filename.is_empty() or not FileAccess.file_exists(filename): return null
	var image := Image.load_from_file(filename)
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)
func populate() -> void:
	if list == null: return
	list.clear()
	shown.clear()
	selected_entry = {}
	enemy_apply.disabled = true
	tile_apply.disabled = true
	preview.tile_mode = false
	preview.texture = null
	details.text = "Select an image to preview it."
	var filter := search.text.to_lower()
	var kind := category.get_item_text(category.selected)
	var matches := 0
	var choices: Array = []
	for group in library.groups.values(): choices.append(group)
	for entry in entries:
		if entry.category != "sprites" or entry.get("width") != 16 or entry.get("height") != 16: choices.append(entry)
	choices.sort_custom(func(a,b): return String(a.name) < String(b.name))
	for entry in choices:
		if kind != "all" and entry.category != kind: continue
		if not filter.is_empty() and filter not in String(entry.name).to_lower() and filter not in String(entry.path).to_lower(): continue
		matches += 1
		if shown.size() >= 250: continue
		shown.append(entry)
		list.add_item(entry.name,library.enemy_texture(entry.id) if entry.has("frames") else texture(entry.path))
		list.set_item_tooltip(list.item_count-1,entry.path)
	summary.text = catalog_message + (" • %d choices (first 250 shown; refine filter)" % matches if matches > 250 else " • %d choices" % matches)
func select_image(index: int) -> void:
	if index < 0 or index >= shown.size(): return
	selected_entry = shown[index]
	preview.selected_tile = 0
	preview.tile_mode = selected_entry.category == "tiles"
	enemy_apply.disabled = not selected_entry.has("frames")
	tile_apply.disabled = not preview.tile_mode
	frame_clock = 0.0
	update_frame()
	if preview.tile_mode: details.text += "\nClick an atlas cell, then choose Paint."
func _process(delta: float) -> void:
	if selected_entry.is_empty() or not selected_entry.has("frames"): return
	frame_clock += delta
	update_frame()
func update_frame() -> void:
	if selected_entry.is_empty(): return
	preview.texture = library.enemy_texture(selected_entry.id,direction.get_item_text(direction.selected),int(frame_clock/0.1)) if selected_entry.has("frames") else texture(selected_entry.path)
	details.text = String(selected_entry.name) + ("\n%d × %d pixels" % [preview.texture.get_width(),preview.texture.get_height()] if preview.texture != null else "\nImage is missing or unreadable; reimport to restore it.")
