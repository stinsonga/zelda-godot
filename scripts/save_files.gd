class_name SaveFiles
extends RefCounted
## The original's three save files (Z_02 file menu, registration, elimination).
## Each holds a name in tile codes, a death count, the quest, and the hearts and
## ring shown in the menu; a saved game also stores its state through the
## checked SaveStore, without position: files always start at the overworld.
const Saves = preload("res://scripts/save_store.gd")
const COUNT := 3
const NAME_LENGTH := 8
const BLANK := 0x24
var directory: String
## Per slot: null, or {name: Array of tile codes, deaths, quest, max_health, health, ring}.
var meta: Array = [null, null, null]

func _init(base_directory: String = "user://files") -> void:
	directory = base_directory
	load_meta()

func meta_path() -> String:
	return directory.path_join("files.json")

func store_for(slot: int) -> RefCounted:
	return Saves.new(directory.path_join("slot_%d" % slot))

func active(slot: int) -> bool:
	return meta[slot] != null

func load_meta() -> void:
	meta = [null, null, null]
	if not FileAccess.file_exists(meta_path()): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path()))
	if not parsed is Array or parsed.size() != COUNT: return
	for slot in range(COUNT):
		var entry: Variant = parsed[slot]
		if not entry is Dictionary or not entry.get("name") is Array or entry.name.size() != NAME_LENGTH: continue
		meta[slot] = {"name": entry.name.map(func(code: Variant) -> int: return clampi(int(code), 0, 255)),
			"deaths": clampi(int(entry.get("deaths", 0)), 0, 255), "quest": clampi(int(entry.get("quest", 1)), 1, 2),
			"max_health": clampi(int(entry.get("max_health", 6)), 2, 32), "health": clampi(int(entry.get("health", 6)), 0, 32),
			"ring": clampi(int(entry.get("ring", 0)), 0, 2)}

func save_meta() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(meta_path(), FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(meta, "\t"))
	return true

## Z_02 UpdateModeERegister: a new file has three hearts (and eight bombs); a
## name starting "ZELDA" begins the second quest.
func create(slot: int, name: Array) -> void:
	var zelda := [0x23, 0x0E, 0x15, 0x0D, 0x0A]
	meta[slot] = {"name": name.duplicate(), "deaths": 0, "quest": 2 if name.slice(0, 5) == zelda else 1,
		"max_health": 6, "health": 6, "ring": 0}
	erase_state(slot)
	save_meta()

## Z_02 DeleteSlot.
func erase(slot: int) -> void:
	meta[slot] = null
	erase_state(slot)
	save_meta()

func erase_state(slot: int) -> void:
	var dir := ProjectSettings.globalize_path(directory.path_join("slot_%d" % slot))
	if not DirAccess.dir_exists_absolute(dir): return
	for file in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(file))

func read_state(slot: int, world_id: String, previous: PackedStringArray = []) -> Dictionary:
	if not active(slot): return {}
	var paths: Array = [world_id] + Array(previous)
	if not paths.any(func(id): return FileAccess.file_exists(store_for(slot).path_for(id)) or FileAccess.file_exists(store_for(slot).path_for(id) + ".bak")): return {}
	var result: Dictionary = store_for(slot).read_snapshot(world_id, previous)
	return result.data if result.ok else {}

func write_state(slot: int, data: Dictionary, world_id: String) -> bool:
	var result: Dictionary = store_for(slot).write_snapshot(data, world_id)
	if not result.ok: return false
	meta[slot].max_health = int(data.max_health)
	meta[slot].health = int(data.health)
	meta[slot].ring = int(data.get("slots", {}).get("ring", 0))
	return save_meta()

func add_death(slot: int) -> void:
	if not active(slot): return
	meta[slot].deaths = mini(255, meta[slot].deaths + 1)
	save_meta()
