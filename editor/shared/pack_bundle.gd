extends RefCounted
## A standalone game bundle: a folder holding pack.json and the shared authored
## art the pack names, under content/art/<library>/. The game plays bundles
## without the source project; local ROM appearance never enters one.
const Pack = preload("room_pack.gd")
const Library = preload("authored_library.gd")
const PACK_FILE := "pack.json"

## Authored libraries the pack's public appearance refers to.
static func libraries(pack: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var art: Dictionary = pack.get("appearance",{})
	var ids: Array = []
	ids.append_array(art.get("enemy_sprites",{}).values())
	for visual in art.get("room_tiles",{}).values(): ids.append(visual.get("atlas",""))
	for sprites in art.get("room_sprites",{}).values(): ids.append_array(sprites.values())
	for id in ids:
		var parts: PackedStringArray = String(id).split("/")
		if parts.size() == 3 and parts[0] == "art" and parts[1] not in result: result.append(parts[1])
	result.sort()
	return result

## Writes the bundle into an empty or new folder. game_root holds content/art.
static func write_bundle(pack: Dictionary, game_root: String, destination: String) -> PackedStringArray:
	var errors := Pack.validate(pack)
	if not errors.is_empty(): return errors
	if DirAccess.dir_exists_absolute(destination) and not (DirAccess.get_files_at(destination).is_empty() and DirAccess.get_directories_at(destination).is_empty()):
		return PackedStringArray(["Export into an empty folder"])
	var copies: Array = []
	for name in libraries(pack):
		var folder := game_root.path_join("content/art").path_join(name)
		var loaded := Library.read(folder.path_join("library.json"))
		if not loaded.errors.is_empty(): errors.append("Art library " + name + ": " + "; ".join(loaded.errors)); continue
		copies.append([folder.path_join("library.json"),"content/art/%s/library.json" % name])
		for asset in loaded.library.assets: copies.append([folder.path_join(asset.file),"content/art/%s/%s" % [name,asset.file]])
	if not errors.is_empty(): return errors
	for copy in copies:
		var target := destination.path_join(copy[1])
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var error := DirAccess.copy_absolute(copy[0],target)
		if error != OK: return PackedStringArray(["Cannot copy " + copy[1] + ": " + error_string(error)])
	DirAccess.make_dir_recursive_absolute(destination)
	var error := Pack.write(destination.path_join(PACK_FILE),pack)
	if error != OK: return PackedStringArray(["Cannot write pack: " + error_string(error)])
	return PackedStringArray()

## {"pack", "root", "errors"} for a bundle folder, or a bare pack JSON file
## (which plays with placeholder art).
static func read(path: String) -> Dictionary:
	var root := path
	var file := path.path_join(PACK_FILE)
	if path.get_extension().to_lower() == "json": root = path.get_base_dir(); file = path
	var loaded := Pack.read(file)
	loaded.root = root
	return loaded

## Bundle folders in each search directory (sorted by folder name), skipping
## folders without a pack.json.
static func find(directories: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for directory in directories:
		if not DirAccess.dir_exists_absolute(directory): continue
		var names := DirAccess.get_directories_at(directory)
		names.sort()
		for name in names:
			var folder: String = String(directory).path_join(name)
			if FileAccess.file_exists(folder.path_join(PACK_FILE)): result.append(folder)
	return result
