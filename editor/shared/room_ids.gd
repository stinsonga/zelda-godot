extends RefCounted
## Authored room identities and their flat historical aliases. Empty targets are
## deleted-room tombstones; neither aliases nor tombstones may become live IDs.
static func valid_id(value) -> bool:
	if not value is String or value.is_empty() or value.length()>64: return false
	for c in value:
		if c not in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true
static func validate(aliases, rooms: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not aliases is Dictionary or aliases.size()>1024: return PackedStringArray(["Room aliases must be an object with at most 1024 entries"])
	for old in aliases:
		var target = aliases[old]
		if not valid_id(old) or rooms.has(old): errors.append("Historical room IDs must be valid, reserved names: "+str(old))
		if not target is String or (not target.is_empty() and (not valid_id(target) or not rooms.has(target))): errors.append("Room aliases must point directly to a live room, or an empty deleted-room marker")
	return errors
static func reserved(pack: Dictionary, id: String) -> bool:
	if pack.rooms.any(func(room): return room.id==id) or pack.get("room_aliases",{}).has(id): return true
	var recipe: Dictionary = pack.get("generation",{})
	if recipe.get("templates",{}).has(id): return true
	return recipe.get("loop_edges",[]).any(func(edge): return edge.room==id or edge.target==id)
static func move_key(data: Dictionary, old: String, id: String) -> void:
	if data.has(old): data[id] = data[old];data.erase(old)
static func rename(pack: Dictionary, old: String, id: String, overlay: Dictionary = {}) -> Dictionary:
	if not valid_id(id): return {"errors":PackedStringArray(["Room ID needs 1..64 lowercase letters, digits, underscores or hyphens"])}
	if not pack.rooms.any(func(room): return room.id==old): return {"errors":PackedStringArray(["Room is missing"])}
	if old!=id and reserved(pack,id): return {"errors":PackedStringArray(["That ID is live or reserved by room/generation history. Choose a new ID."])}
	if not overlay.get("room_tiles",{}) is Dictionary: return {"errors":PackedStringArray(["Invalid local room appearance"])}
	if old!=id and overlay.get("room_tiles",{}).has(id): return {"errors":PackedStringArray(["Local appearance already uses the requested ID"])}
	var output: Dictionary = pack.duplicate(true);var art: Dictionary = overlay.duplicate(true)
	if old==id: return {"errors":PackedStringArray(),"pack":output,"appearance":art}
	if output.get("room_aliases",{}).size()>=1024: return {"errors":PackedStringArray(["Room migration history limit reached"])}
	if output.schema==1: output.schema = 2;output.starting_items = ["wooden_sword"];output.goals = []
	if not output.has("room_aliases"): output.room_aliases = {}
	for previous in output.room_aliases:
		if output.room_aliases[previous]==old: output.room_aliases[previous] = id
	output.room_aliases[old] = id
	if output.start_room==old: output.start_room = id
	for room in output.rooms:
		if room.id==old: room.id = id
		for link in room.connections.values():
			if link.target==old: link.target = id
		for stair in room.get("stairs",[]):
			if stair.target==old: stair.target = id
	for goal in output.goals:
		if goal.room==old: goal.room = id
	for field in ["room_tiles","room_sprites"]:
		if output.has("appearance"): move_key(output.appearance[field],old,id)
	if art.has("room_tiles"): move_key(art.room_tiles,old,id)
	if output.has("generation"):
		move_key(output.generation.templates,old,id)
		for edge in output.generation.get("loop_edges",[]):
			if edge.room==old: edge.room = id
			if edge.target==old: edge.target = id
	return {"errors":PackedStringArray(),"pack":output,"appearance":art}
static func retire(pack: Dictionary, id: String) -> void:
	if not pack.has("room_aliases"): pack.room_aliases = {}
	for old in pack.room_aliases:
		if pack.room_aliases[old]==id: pack.room_aliases[old] = ""
	pack.room_aliases[id] = ""
