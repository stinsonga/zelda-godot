extends RefCounted
## Optional local appearance, shared by the editor and runtime adapter.
## Asset IDs resolve only through the generated catalog; packs never gain paths.
const Bindings = preload("art_bindings.gd")
const Authored = preload("authored_library.gd")
const Contract = preload("room_pack.gd")
const SHA1 := "a12d74c73a0481599a5d832361d168f4737bbcf6"
const FLOOR := Color("d6bd85")
const WALL := Color("687b3d")
const WATER := Color("4373a1")
var root := ""
var entries: Dictionary = {}
var groups: Dictionary = {}
var textures: Dictionary = {}
var warnings := PackedStringArray()

static func fresh(pack_id: String) -> Dictionary:
	return {"format_version":1,"pack_id":pack_id,"source_sha1":SHA1,"enemy_sprites":{},"room_tiles":{}}
static func has_choices(overlay: Dictionary) -> bool:
	return not overlay.get("enemy_sprites",{}).is_empty() or not overlay.get("room_tiles",{}).is_empty() or not overlay.get("room_sprites",{}).is_empty()
static func local_path(game_root: String, pack_id: String) -> String:
	if not Contract.identifier(pack_id): return ""
	return game_root.path_join("reference-inputs/editor-overrides").path_join(pack_id + ".json")
static func asset_id(value) -> bool:
	if not value is String or not value.begins_with("rom/us_prg0/") or value.length() > 200: return false
	for c in value:
		if c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/": return false
	return true
static func validate(overlay, pack: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not overlay is Dictionary: return PackedStringArray(["Local appearance must be an object"])
	Contract.unknown_fields(overlay,["format_version","pack_id","source_sha1","enemy_sprites","room_tiles"],"Appearance",errors)
	if overlay.get("format_version") != 1 or overlay.get("pack_id") != pack.id or overlay.get("source_sha1") != SHA1:
		errors.append("Local appearance version, pack identity or source revision differs")
	var enemies = overlay.get("enemy_sprites")
	var rooms = overlay.get("room_tiles")
	if not enemies is Dictionary or not rooms is Dictionary: errors.append("Local appearance needs enemy_sprites and room_tiles objects"); return errors
	for id in enemies:
		if not pack.enemy_types.has(id) or not asset_id(enemies[id]): errors.append("Invalid local enemy appearance: " + str(id))
	var room_ids: Array = pack.rooms.map(func(r): return r.id)
	for id in rooms:
		var visual = rooms[id]
		if id not in room_ids or not visual is Dictionary: errors.append("Invalid local room appearance: " + str(id)); continue
		Contract.unknown_fields(visual,["atlas","indices"],"Room appearance",errors)
		if not asset_id(visual.get("atlas")): errors.append("Invalid room atlas ID")
		var indices = visual.get("indices")
		if not indices is Array or indices.size() != 176: errors.append("Room appearance requires 176 indices"); continue
		for index in indices:
			if not Contract.integer(index,-1,65535): errors.append("Invalid local tile index"); break
	return errors
static func read_local(game_root: String, pack: Dictionary) -> Dictionary:
	var path := local_path(game_root,pack.id)
	var empty := fresh(pack.id)
	if path.is_empty() or not FileAccess.file_exists(path): return {"overlay":empty,"warnings":PackedStringArray()}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 2000000: return {"overlay":empty,"warnings":PackedStringArray(["Cannot read local appearance; keeping placeholders"])}
	var data = JSON.parse_string(file.get_as_text())
	var errors := validate(data,pack)
	return {"overlay":data if errors.is_empty() else empty,"warnings":errors}
func warn(text: String) -> void:
	if text not in warnings: warnings.append(text)
func _configure_rom(game_root: String) -> void:
	root = game_root
	entries.clear()
	groups.clear()
	textures.clear()
	warnings.clear()
	var path := root.path_join("imported/editor_catalog.json")
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() > 4000000: warn("Cannot read local image catalog"); return
	var catalog = JSON.parse_string(file.get_as_text())
	if not catalog is Dictionary or catalog.get("format_version") != 1 or not catalog.get("source") is Dictionary or catalog.source.get("prg_sha1") != SHA1 or not catalog.get("entries") is Array:
		warn("Invalid local image catalog"); return
	for entry in catalog.entries:
		if not entry is Dictionary or not asset_id(entry.get("id")) or not entry.get("path") is String or not entry.get("name") is String or entry.get("category") not in ["sprites","tiles","interface"] or not Contract.integer(entry.get("width"),1,2048) or not Contract.integer(entry.get("height"),1,2048):
			warn("Invalid local image entry; reimport to rebuild catalog");continue
		if checked_path(entry.path).is_empty(): warn("Invalid local image path; reimport to rebuild catalog");continue
		entries[entry.id] = entry
	var directional := RegEx.new()
	directional.compile("^(.*)_(up|down|left|right)_([0-9]+)(_p[0-9]+)?$")
	var framed := RegEx.new()
	framed.compile("^(.*)_([0-9]+)$")
	for id in entries:
		var entry: Dictionary = entries[id]
		if entry.get("category") != "sprites" or entry.get("width") != 16 or entry.get("height") != 16: continue
		var stem := String(id)
		var direction := "all"
		var frame := 0
		var result := directional.search(stem)
		var group_id := stem
		if result != null:
			group_id = result.get_string(1) + result.get_string(4)
			direction = result.get_string(2)
			frame = int(result.get_string(3))
		else:
			result = framed.search(stem)
			if result != null: group_id = result.get_string(1); frame = int(result.get_string(2))
		if not groups.has(group_id): groups[group_id] = {"id":group_id,"name":group_id.trim_prefix("rom/us_prg0/").replace("_"," "),"frames":{},"path":entry.path,"category":"sprites"}
		var group: Dictionary = groups[group_id]
		if not group.frames.has(direction): group.frames[direction] = {}
		group.frames[direction][frame] = id
func checked_path(relative: String) -> String:
	if relative.is_empty() or relative.is_absolute_path() or "\\" in relative or ":" in relative or ".." in relative.split("/") or relative.get_extension().to_lower() != "png": return ""
	return root.path_join("imported").path_join(relative).simplify_path()
func texture(id: String) -> Texture2D:
	if textures.has(id): return textures[id]
	if not entries.has(id): warn("Missing local asset: " + id); return null
	var entry: Dictionary = entries[id]
	var path := checked_path(entry.path) if not entry.has("authored_path") else String(entry.authored_path)
	if entry.has("authored_path") and Authored.canonical_path(path) != path: warn("Authored image path is a symlink: "+id);return null
	if path.is_empty() or not FileAccess.file_exists(path): warn("Missing local image: " + str(entry.path)); return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty(): warn("Unreadable local image: " + str(entry.path)); return null
	if image.get_width() != int(entry.get("width",0)) or image.get_height() != int(entry.get("height",0)): warn("Stale local image dimensions: " + str(entry.path)); return null
	var value := ImageTexture.create_from_image(image)
	textures[id] = value
	return value
func enemy_texture(group_id: String, direction: String = "down", pose: int = 0) -> Texture2D:
	if not groups.has(group_id): warn("Missing local sprite set: " + group_id); return null
	if groups[group_id].get("authored",false):
		var group: Dictionary = groups[group_id]
		var sheet := texture(group_id)
		if sheet == null: return null
		var directions: Array = group.directions
		var row := directions.find(direction)
		if row<0: row = directions.find("all")
		if row<0: row = 0
		var result := AtlasTexture.new();result.atlas = sheet
		result.region = Rect2(Vector2(posmod(pose,int(group.frame_count))*int(group.frame_size[0]),row*int(group.frame_size[1])),Vector2(group.frame_size[0],group.frame_size[1]))
		return result
	var frames: Dictionary = groups[group_id].frames
	var source: Dictionary = frames.get(direction,frames.get("all",{}))
	if source.is_empty():
		for fallback in ["down","up","right","left"]:
			if frames.has(fallback): source = frames[fallback]; break
	if source.is_empty(): warn("Empty sprite set: " + group_id); return null
	var keys: Array = source.keys()
	keys.sort()
	return texture(source[keys[posmod(pose,keys.size())]])
func room_texture(room: Dictionary, overlay: Dictionary) -> Texture2D:
	if not overlay.get("room_tiles",{}).has(room.id): return null
	var visual: Dictionary = overlay.room_tiles[room.id]
	var atlas := texture(visual.atlas)
	if atlas == null: return null
	var cell := int(entries.get(visual.atlas,{}).get("cell_size",16))
	if not entries.has(visual.atlas) or entries[visual.atlas].get("category") != "tiles" or atlas.get_width()%cell != 0 or atlas.get_height()%cell != 0:
		warn("Selected image is not a supported tile atlas"); return null
	var input := atlas.get_image()
	var output := Image.create(16*cell,11*cell,false,Image.FORMAT_RGBA8)
	var columns := atlas.get_width()/cell
	var capacity := columns*(atlas.get_height()/cell)
	for i in range(176):
		var at := Vector2i(i%16*cell,i/16*cell)
		var kind: String = room.tiles[i/16][i%16]
		output.fill_rect(Rect2i(at,Vector2i(cell,cell)),WALL if kind == "#" else WATER if kind == "~" else FLOOR)
		var index := int(visual.indices[i])
		if index >= capacity: warn("Tile index outside selected atlas in " + String(room.id)); continue
		if index >= 0: output.blit_rect(input,Rect2i(Vector2i(index%columns,index/columns)*cell,Vector2i(cell,cell)),at)
	# Native door overrides erase these markers when passable. Collision remains
	# solely the room's terrain and DoorDefinition, never inferred from pixels.
	for edge in room.connections:
		var kind: String = room.connections[edge].kind
		if kind not in ["key","shutter"]: continue
		var rect := Rect2i(120,0 if edge == "up" else 160,16,16) if edge in ["up","down"] else Rect2i(0 if edge == "left" else 240,80,16,16)
		output.fill_rect(Rect2i(rect.position*cell/16,rect.size*cell/16),Color("e5c46a") if kind == "key" else Color("b49bdb"))
	return ImageTexture.create_from_image(output)

static func effective(pack: Dictionary, local: Dictionary = {}) -> Dictionary:
	var result: Dictionary = pack.get("appearance",Bindings.fresh()).duplicate(true)
	for field in ["enemy_sprites","room_tiles"]:
		for id in local.get(field,{}): result[field][id] = local[field][id].duplicate(true) if local[field][id] is Dictionary else local[field][id]
	return result
func configure(game_root: String) -> void:
	_configure_rom(game_root)
	var folder := Authored.canonical_path(game_root).path_join("content/art")
	if not DirAccess.dir_exists_absolute(folder): return
	if Authored.canonical_path(folder) != folder: warn("Authored art folder cannot be a symlink");return
	var names := DirAccess.get_directories_at(folder);names.sort()
	for name in names:
		if not Contract.identifier(name): continue
		var directory := folder.path_join(name)
		if Authored.canonical_path(directory) != directory: warn("Authored library folder is a symlink: "+name);continue
		var manifest := directory.path_join("library.json")
		if not FileAccess.file_exists(manifest): continue
		if Authored.canonical_path(manifest) != manifest: warn("Authored manifest is a symlink: "+name);continue
		var loaded := Authored.read(manifest)
		if not loaded.errors.is_empty():
			for error in loaded.errors: warn(name+": "+error)
			continue
		if loaded.library.id != name: warn("Authored library ID differs from folder: "+name);continue
		for asset in loaded.library.assets:
			var id := "art/"+name+"/"+String(asset.id)
			var entry := {"id":id,"name":loaded.library.title+" / "+String(asset.name),"path":"content/art/"+name+"/"+String(asset.file),"authored_path":directory.path_join(asset.file),"category":"tiles" if asset.kind == "tiles" else "sprites","width":asset.width,"height":asset.height}
			if asset.kind == "tiles": entry.cell_size = int(asset.cell_size)
			entries[id] = entry
			if asset.kind == "sprite":
				groups[id] = {"id":id,"name":entry.name,"path":entry.path,"category":"sprites","frames":{},"authored":true,"frame_count":int(asset.frames),"frame_ticks":int(asset.frame_ticks),"frame_size":asset.frame_size,"directions":asset.directions}
func room_cell_size(room: Dictionary, overlay: Dictionary) -> int:
	var id: String = overlay.get("room_tiles",{}).get(room.id,{}).get("atlas","")
	return int(entries.get(id,{}).get("cell_size",16))
func sprite_frames(id: String) -> Array:
	var result: Array = []
	var count := int(groups.get(id,{}).get("frame_count",1))
	for i in count:
		var value := enemy_texture(id,"down",i)
		if value == null: return []
		result.append(value)
	return result
