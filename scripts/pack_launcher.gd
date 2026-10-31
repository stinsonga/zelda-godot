extends Node2D
## The game's entry: plays the original front end unless game bundles are
## installed, in which case it lists them. Bundles are folders made by the
## editor's Export game, found in packs/ beside the executable (or beside the
## macOS app), in user://packs, or named with `-- --pack <folder or json>`.
## Keys: arrows choose, Enter starts.
const Bundle = preload("res://editor/shared/pack_bundle.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
const ORIGINAL := ""

## Bundle folders, with ORIGINAL first when the original game is available.
var choices: PackedStringArray = []
var titles: PackedStringArray = []
var cursor := 0
var error := ""

static func search_directories() -> Array:
	var base := OS.get_executable_path().get_base_dir()
	var result := [base.path_join("packs"), ProjectSettings.globalize_path("user://packs")]
	if base.ends_with(".app/Contents/MacOS"): result.insert(1, base.get_base_dir().get_base_dir().get_base_dir().path_join("packs"))
	return result

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var named := args.find("--pack")
	if named >= 0 and named + 1 < args.size(): start(args[named + 1]); return
	var found := Bundle.find(search_directories())
	var original := ResourceLoader.exists("res://imported/world.tres")
	if found.is_empty() or (found.size() == 1 and not original):
		start(found[0] if not found.is_empty() else ORIGINAL)
		return
	if original: choices.append(ORIGINAL); titles.append("THE ORIGINAL GAME")
	for folder in found:
		var loaded := Bundle.read(folder)
		choices.append(folder)
		titles.append(String(loaded.pack.get("title", folder.get_file())) if loaded.errors.is_empty() else folder.get_file() + " (INVALID)")
	queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or choices.is_empty(): return
	match event.physical_keycode:
		KEY_UP, KEY_W: cursor = (cursor + choices.size() - 1) % choices.size()
		KEY_DOWN, KEY_S, KEY_TAB: cursor = (cursor + 1) % choices.size()
		KEY_ENTER, KEY_Z, KEY_SPACE: start(choices[cursor])
	queue_redraw()

## Hands over to the front end with the original world or the bundle's.
func start(choice: String) -> void:
	var front_end: Node = preload("res://scenes/front_end.tscn").instantiate()
	if choice != ORIGINAL:
		var loaded := Bundle.read(choice)
		var result := Adapter.compile(loaded.pack, {}, loaded.root) if loaded.errors.is_empty() else {"errors": loaded.errors}
		for warning in result.get("appearance_warnings", []): push_warning(warning)
		if not result.errors.is_empty():
			front_end.free()
			error = "\n".join(result.errors)
			push_error("Cannot play " + choice + ": " + error)
			queue_redraw()
			return
		front_end.pack_world = result.world
		front_end.files_directory = files_directory(loaded.pack)
		get_window().title = String(loaded.pack.title).replace("\n", " ").strip_edges().left(120)
	var tree := get_tree()
	tree.root.add_child.call_deferred(front_end)
	tree.set_deferred("current_scene", front_end)
	queue_free()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(0, 0, 256, 240), Color.BLACK)
	draw_string(font, Vector2(24, 32), "CHOOSE A GAME", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	for i in range(titles.size()):
		draw_string(font, Vector2(36, 60 + i * 16), titles[i].left(28), HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	if not titles.is_empty(): draw_string(font, Vector2(24, 60 + cursor * 16), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	if not error.is_empty(): draw_multiline_string(font, Vector2(24, 200), error.left(200), HORIZONTAL_ALIGNMENT_LEFT, 208, 8, 3, Color("e85050"))

## Each bundle's file slots, under its pack ID; a renamed pack keeps using the
## folder of its most recent earlier ID until it has its own.
static func files_directory(pack: Dictionary) -> String:
	var ids: Array = [String(pack.id)]
	var previous: Array = pack.get("previous_ids",[]).duplicate();previous.reverse();ids.append_array(previous)
	for id in ids:
		var folder := "user://pack_files".path_join(id)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)): return folder
	return "user://pack_files".path_join(String(pack.id))
