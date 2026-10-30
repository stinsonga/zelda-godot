extends RefCounted
const Pack = preload("room_pack.gd")
const MAX_IMAGE := 2048
static func validate(data) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary: return PackedStringArray(["Art library must be an object"])
	Pack.unknown_fields(data,["format_version","id","title","assets"],"Art library",errors)
	if data.get("format_version") != 1 or not Pack.identifier(data.get("id")) or not data.get("title") is String: errors.append("Invalid art library identity/version")
	var assets = data.get("assets")
	if not assets is Array or assets.size()>64: errors.append("Art library supports at most 64 assets");return errors
	var ids: Dictionary = {}
	for asset in assets:
		if not asset is Dictionary: errors.append("Art entry must be an object");continue
		Pack.unknown_fields(asset,["id","name","kind","file","width","height","cell_size","frame_size","directions","frames","frame_ticks","draw_size","draw_offset","clips"],"Art entry",errors)
		if not Pack.identifier(asset.get("id")) or ids.has(asset.get("id")): errors.append("Art asset IDs must be unique");continue
		ids[asset.id] = true
		if not asset.get("name") is String or asset.get("file") != asset.id+".png": errors.append("Art PNG must be named asset_id.png")
		if not Pack.integer(asset.get("width"),1,MAX_IMAGE) or not Pack.integer(asset.get("height"),1,MAX_IMAGE): errors.append("Art image dimensions exceed supported bounds");continue
		if asset.get("kind") == "tiles":
			if not Pack.integer(asset.get("cell_size"),16,64) or int(asset.cell_size) not in [16,32,64]: errors.append("Tile cells must be 16, 32 or 64 pixels");continue
			if int(asset.width)%int(asset.cell_size) != 0 or int(asset.height)%int(asset.cell_size) != 0: errors.append("Atlas dimensions must be multiples of its cell size")
		elif asset.get("kind") == "sprite":
			if not Pack.point(asset.get("frame_size"),1,256,1,256): errors.append("Invalid sprite frame size");continue
			if not Pack.point(asset.get("draw_size",[16,16]),1,128,1,128): errors.append("Sprite draw size must be 1..128 logical pixels per side")
			if not Pack.point(asset.get("draw_offset",[0,0]),-128,128,-128,128): errors.append("Sprite offset must be -128..128 logical pixels")
			var directions = asset.get("directions")
			if not directions is Array or directions.is_empty() or directions.size()>4: errors.append("Choose 1..4 sprite direction rows");continue
			var seen: Array = []
			for direction in directions:
				if direction not in ["all","down","up","right","left"] or direction in seen: errors.append("Invalid/duplicate sprite direction")
				seen.append(direction)
			if "all" in directions and directions.size()!=1: errors.append("All-direction row cannot mix with directional rows")
			if not Pack.integer(asset.get("frames"),1,16) or not Pack.integer(asset.get("frame_ticks"),1,120): errors.append("Sprite needs 1..16 frames and timing 1..120 ticks");continue
			validate_clips(asset.get("clips",{}),int(asset.frames),errors)
			if int(asset.width) != int(asset.frame_size[0])*int(asset.frames) or int(asset.height) != int(asset.frame_size[1])*directions.size(): errors.append("Sprite sheet must match frame columns and direction rows exactly")
		else: errors.append("Art kind must be tiles or sprite")
	return errors
static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length()>1000000: return {"errors":PackedStringArray(["Cannot read art library (max 1 MB)"])}
	var data = JSON.parse_string(file.get_as_text())
	return {"library":data,"errors":validate(data)}
static func import_png(root: String, source: String, library_id: String, asset_id: String, kind: String, cell_size: int, directions: Array = ["all"], frames: int = 1, frame_ticks: int = 6, frame_size: Array = [], draw_size: Array = [16,16], draw_offset: Array = [0,0], clips: Dictionary = {}) -> Dictionary:
	if not Pack.identifier(library_id) or not Pack.identifier(asset_id): return {"errors":PackedStringArray(["Library and asset IDs need lowercase letters, digits, underscores or hyphens"])}
	var absolute := canonical_path(source)
	if absolute.is_empty(): return {"errors":PackedStringArray(["Cannot resolve source path"])}
	for folder in ["imported","reference-inputs",".godot"]:
		if absolute.begins_with(canonical_path(root.path_join(folder))+"/"): return {"errors":PackedStringArray(["Import authored graphics from outside local ROM/import directories"])}
	if source.get_extension().to_lower() != "png": return {"errors":PackedStringArray(["Choose a PNG image"])}
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null or file.get_length()<24 or file.get_length()>16000000: return {"errors":PackedStringArray(["Cannot read PNG or image exceeds 16 MB"])}
	var signature := file.get_buffer(8)
	if signature != PackedByteArray([137,80,78,71,13,10,26,10]): return {"errors":PackedStringArray(["Invalid PNG signature"])}
	file.big_endian = true;file.seek(16)
	var width := file.get_32();var height := file.get_32();file.close()
	if width<1 or height<1 or width>MAX_IMAGE or height>MAX_IMAGE: return {"errors":PackedStringArray(["PNG must be at most 2048 pixels per side"])}
	var folder := root.path_join("content/art").path_join(library_id)
	if canonical_path(folder) != canonical_path(root).path_join("content/art").path_join(library_id): return {"errors":PackedStringArray(["Authored library folders cannot be symlinks"])}
	var manifest := folder.path_join("library.json")
	var directory := DirAccess.open(folder)
	if directory != null:
		for name in ["library.json","library.json.tmp",asset_id+".png"]:
			if directory.is_link(name): return {"errors":PackedStringArray(["Authored output files cannot be symlinks"])}
	var data: Dictionary = {"format_version":1,"id":library_id,"title":library_id.capitalize(),"assets":[]}
	if FileAccess.file_exists(manifest):
		var loaded := read(manifest)
		if not loaded.errors.is_empty(): return loaded
		data = loaded.library
		if data.id != library_id: return {"errors":PackedStringArray(["Existing library ID differs from its folder"])}
	var asset := {"id":asset_id,"name":asset_id.capitalize(),"kind":kind,"file":asset_id+".png","width":width,"height":height}
	if kind == "tiles": asset.cell_size = cell_size
	else:
		asset.frame_size = frame_size.duplicate() if not frame_size.is_empty() else [cell_size,cell_size]
		if not clips.is_empty(): asset.clips = clips.duplicate(true)
		asset.draw_size = draw_size.duplicate();asset.draw_offset = draw_offset.duplicate()
		asset.directions = directions.duplicate();asset.frames = frames;asset.frame_ticks = frame_ticks
	data.assets.append(asset)
	var errors := validate(data)
	if not errors.is_empty(): return {"errors":errors}
	var destination := folder.path_join(asset_id+".png")
	if FileAccess.file_exists(destination): return {"errors":PackedStringArray(["Asset PNG already exists; use a new asset ID"])}
	var image := Image.load_from_file(source)
	if image == null or image.is_empty() or image.get_width()!=width or image.get_height()!=height: return {"errors":PackedStringArray(["Unreadable PNG pixels"])}
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error != OK: return {"errors":PackedStringArray(["Cannot create authored library folder"])}
	var temporary := destination+".%d.tmp.png" % Time.get_ticks_usec()
	error = image.save_png(temporary)
	if error == OK: error = DirAccess.rename_absolute(temporary,destination)
	if error == OK: error = Pack.write(manifest,data)
	if error != OK:
		DirAccess.remove_absolute(temporary);DirAccess.remove_absolute(destination)
		return {"errors":PackedStringArray(["Art import failed: "+error_string(error)])}
	return {"errors":PackedStringArray(),"id":"art/"+library_id+"/"+asset_id,"manifest":manifest}

static func canonical_path(path: String, depth: int = 0) -> String:
	if depth>16: return ""
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not absolute.is_absolute_path(): return ""
	var parts: PackedStringArray = absolute.split("/",false)
	var parent := "/"
	for i in parts.size():
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(parts[i]):
			var target := directory.read_link(parts[i])
			if not target.is_absolute_path(): target = parent.path_join(target)
			for j in range(i+1,parts.size()): target = target.path_join(parts[j])
			return canonical_path(target,depth+1)
		parent = parent.path_join(parts[i])
	return parent.simplify_path()

static func validate_clips(clips, count: int, errors: PackedStringArray) -> void:
	if not clips is Dictionary: errors.append("Sprite clips must be an object");return
	for name in clips:
		if name not in ["idle","walk","attack"]: errors.append("Unknown sprite clip: "+str(name));continue
		var clip = clips[name]
		if not clip is Dictionary: errors.append("Sprite clip must be an object");continue
		Pack.unknown_fields(clip,["frames","frame_ticks","loop"],"Sprite clip "+name,errors)
		if not Pack.integer(clip.get("frame_ticks"),1,120): errors.append("Clip timing must be 1..120 ticks")
		if not clip.get("loop") is bool or clip.loop != (name != "attack"): errors.append("Idle/walk clips loop; attack clips play once")
		var frames = clip.get("frames")
		if not frames is Array or frames.is_empty() or frames.size()>64: errors.append("Clip needs 1..64 frame indices");continue
		for index in frames:
			if not Pack.integer(index,0,count-1): errors.append("Clip frame index outside sprite sheet");break
