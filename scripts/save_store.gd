class_name SaveStore
extends RefCounted

const VERSION := 1
const MAX_BYTES := 1048576
var directory: String

func _init(base_directory: String = "user://saves") -> void:
	directory = base_directory

func path_for(world_id: String) -> String:
	return directory.path_join(world_id.sha256_text().substr(0, 24) + ".json")

func failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func whole(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == floor(float(value)) and value >= low and value <= high

func identifiers(value: Variant) -> bool:
	if not value is Array or value.size() > 10000: return false
	var seen := {}
	for key in value:
		if not key is String or key.is_empty() or key.length() > 256 or seen.has(key): return false
		seen[key] = true
	return true

func validate(data: Variant, world_id: String) -> Dictionary:
	if not data is Dictionary: return failure("Invalid save structure")
	if not whole(data.get("version"), VERSION, VERSION): return failure("Unsupported save version")
	if data.get("world_id") != world_id: return failure("Save belongs to a different world")
	if not data.get("room_id") is String or data.room_id.is_empty(): return failure("Missing saved room")
	for key in ["inventory", "collected", "defeated", "flags"]:
		if not identifiers(data.get(key)): return failure("Invalid saved " + key)
	if not data.get("equipped") is String: return failure("Invalid equipped item")
	if not data.equipped.is_empty() and data.equipped not in data.inventory: return failure("Equipped item is not in inventory")
	if not whole(data.get("max_health"), 2, 128) or int(data.max_health) % 2 != 0: return failure("Invalid heart containers")
	if not whole(data.get("health"), 1, int(data.max_health)): return failure("Invalid saved health")
	if not whole(data.get("rupees"), 0, 255) or not whole(data.get("kill_cycle"), 0, 9): return failure("Invalid counters")
	var position: Variant = data.get("position")
	if not position is Array or position.size() != 2: return failure("Invalid saved position")
	for coordinate in position:
		if not whole(coordinate, -1048576, 1048576): return failure("Invalid saved position")
	var facing: Variant = data.get("facing")
	if not facing is Array or facing.size() != 2: return failure("Invalid saved direction")
	if not whole(facing[0], -1, 1) or not whole(facing[1], -1, 1) or absf(facing[0]) + absf(facing[1]) != 1: return failure("Invalid saved direction")
	return {"ok": true, "data": data}

func read_file(path: String, world_id: String) -> Dictionary:
	if not FileAccess.file_exists(path): return failure("No save found")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return failure("Could not read save")
	if file.get_length() > MAX_BYTES:
		file.close()
		return failure("Save file is too large")
	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK: return failure("Save file is damaged")
	return validate(parser.data, world_id)

func read_snapshot(world_id: String) -> Dictionary:
	var path := path_for(world_id)
	var result := read_file(path, world_id)
	if result.ok:
		result["backup"] = false
		return result
	var backup := read_file(path + ".bak", world_id)
	if backup.ok:
		backup["backup"] = true
		return backup
	return result

func write_snapshot(data: Dictionary, world_id: String) -> Dictionary:
	var checked := validate(data, world_id)
	if not checked.ok: return checked
	var text := JSON.stringify(data, "\t")
	if text.to_utf8_buffer().size() > MAX_BYTES: return failure("Save file is too large")
	var absolute := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(absolute) != OK: return failure("Could not create save folder")
	var path := ProjectSettings.globalize_path(path_for(world_id))
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return failure("Could not write save")
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return failure("Could not finish writing save")
	# Preserve the previous valid snapshot. Never replace a good backup with a
	# corrupt primary file that a player may be trying to recover from.
	if FileAccess.file_exists(path) and read_file(path, world_id).ok:
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			DirAccess.remove_absolute(temporary)
			return failure("Could not preserve backup")
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return failure("Could not replace save")
	return {"ok": true}
