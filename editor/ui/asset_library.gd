extends VBoxContainer
## Shared authored libraries and optional private ROM art; choices emit symbolic IDs.
const Bindings = preload("../shared/art_bindings.gd")
const ImportDialog = preload("graphics_import_dialog.gd")
const Appearance = preload("../shared/appearance.gd")
const Preview = preload("asset_preview.gd")
signal preview_clip_chosen(clip: String)
signal library_changed
signal room_sprite_chosen(slot: String, id: String)
signal room_sprite_cleared(slot: String)
var importer: AcceptDialog
var room_apply: Button
var room_slot: OptionButton
signal enemy_chosen(group_id: String)
signal tile_chosen(atlas_id: String, index: int)
var library = Appearance.new()
var selected_entry: Dictionary = {}
var enemy_apply: Button
var tile_apply: Button
var frame_clock := 0.0
var preview_clip: OptionButton
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
	var import_button := Button.new();import_button.text = "Import authored PNG…";tools.add_child(import_button)
	importer = ImportDialog.new();add_child(importer)
	import_button.pressed.connect(func(): importer.game_root = game_root;importer.popup_centered())
	importer.imported.connect(func(_id): load_catalog(game_root);library_changed.emit())
	refresh_button = Button.new()
	refresh_button.text = "Refresh library"
	tools.add_child(refresh_button)
	refresh_button.pressed.connect(func(): load_catalog(game_root);library_changed.emit())
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
	var clip_row := HBoxContainer.new();right.add_child(clip_row)
	preview_clip = OptionButton.new();preview_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL;preview_clip.add_item("default");clip_row.add_child(preview_clip)
	var replay := Button.new();replay.text = "Replay clip";clip_row.add_child(replay)
	replay.pressed.connect(func(): frame_clock = 0.0;update_frame();preview_clip_chosen.emit(preview_clip.get_item_text(preview_clip.selected)))
	preview_clip.item_selected.connect(func(_i): frame_clock = 0.0;update_frame();preview_clip_chosen.emit(preview_clip.get_item_text(preview_clip.selected)))
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
	room_slot = OptionButton.new()
	for slot in ["secret","stairs","resident"]: room_slot.add_item(slot)
	right.add_child(room_slot)
	room_apply = Button.new();room_apply.text = "Use authored sprite for room feature";room_apply.disabled = true
	room_apply.pressed.connect(func(): room_sprite_chosen.emit(room_slot.get_item_text(room_slot.selected),selected_entry.id));right.add_child(room_apply)
	var clear := Button.new();clear.text = "Clear selected room feature art"
	clear.pressed.connect(func(): room_sprite_cleared.emit(room_slot.get_item_text(room_slot.selected)));right.add_child(clear)
	var note := Label.new()
	note.text = "Authored art saves with the shared pack. ROM choices remain private. Enemy stats, movement and terrain collision are independent."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
func checked_path(relative: String) -> String:
	if relative.is_empty() or relative.is_absolute_path() or "\\" in relative or ":" in relative or relative.get_extension().to_lower() != "png": return ""
	if ".." in relative.split("/"): return ""
	return game_root.path_join("imported").path_join(relative).simplify_path()
func load_catalog(root_path: String) -> void:
	game_root = root_path
	library.configure(root_path)
	entries = library.entries.values()
	var authored := entries.filter(func(entry): return entry.has("authored_path")).size()
	catalog_message = "%d authored assets • %d local ROM images" % [authored,entries.size()-authored]
	if entries.is_empty(): catalog_message = "No graphics libraries. Import authored PNGs, or use Import ROM for optional private art."
	if not library.warnings.is_empty(): catalog_message += " • "+"; ".join(library.warnings)
	populate()

func texture(relative: String) -> Texture2D:
	for entry in entries:
		if entry.path == relative: return library.texture(entry.id)
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
	room_apply.disabled = true
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
		if entry.category != "sprites" or (not entry.has("authored_path") and (entry.get("width") != 16 or entry.get("height") != 16)): choices.append(entry)
	choices.sort_custom(func(a,b): return String(a.name) < String(b.name))
	for entry in choices:
		if kind != "all" and entry.category != kind: continue
		if not filter.is_empty() and filter not in String(entry.name).to_lower() and filter not in String(entry.path).to_lower(): continue
		matches += 1
		if shown.size() >= 250: continue
		shown.append(entry)
		list.add_item(entry.name,library.animation_texture(entry.id,"down","idle",0) if entry.has("frames") else texture(entry.path))
		list.set_item_tooltip(list.item_count-1,entry.path)
	summary.text = catalog_message + (" • %d choices (first 250 shown; refine filter)" % matches if matches > 250 else " • %d choices" % matches)
func select_image(index: int) -> void:
	if index < 0 or index >= shown.size(): return
	selected_entry = shown[index]
	preview.selected_tile = 0
	preview.tile_mode = selected_entry.category == "tiles"
	preview.cell_size = int(selected_entry.get("cell_size",16))
	room_apply.disabled = not (selected_entry.has("frames") and Bindings.asset_id(selected_entry.id))
	enemy_apply.disabled = not selected_entry.has("frames")
	tile_apply.disabled = not preview.tile_mode
	preview_clip.clear()
	for name in ["idle","walk","attack"]:
		if selected_entry.get("clips",{}).has(name): preview_clip.add_item(name)
	if preview_clip.item_count==0: preview_clip.add_item("default")
	preview_clip.disabled = not selected_entry.has("frames")
	frame_clock = 0.0
	preview_clip_chosen.emit(preview_clip.get_item_text(preview_clip.selected))
	update_frame()
	if preview.tile_mode: details.text += "\nClick an atlas cell, then choose Paint."
func _process(delta: float) -> void:
	if selected_entry.is_empty() or not selected_entry.has("frames"): return
	frame_clock += delta
	update_frame()
func update_frame() -> void:
	if selected_entry.is_empty(): return
	preview.texture = library.animation_texture(selected_entry.id,direction.get_item_text(direction.selected),preview_clip.get_item_text(preview_clip.selected),int(frame_clock*60)) if selected_entry.has("frames") else texture(selected_entry.path)
	details.text = String(selected_entry.name) + ("\n%d × %d pixels" % [preview.texture.get_width(),preview.texture.get_height()] if preview.texture != null else "\nImage is missing or unreadable; reimport to restore it.")
	if Bindings.asset_id(selected_entry.get("id","")) and selected_entry.has("frames"):
		var layout := library.sprite_layout(selected_entry.id)
		details.text += "\nDraw %s; offset %s logical pixels" % [layout.size,layout.position]
		if not selected_entry.get("clips",{}).is_empty(): details.text += "\nClip: "+preview_clip.get_item_text(preview_clip.selected)+" (attack holds its final frame)"
