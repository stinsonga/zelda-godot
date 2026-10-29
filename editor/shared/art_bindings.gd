extends RefCounted
## Public art is symbolic and authored-only. No dependency on the pack loader.
static func fresh() -> Dictionary:
	return {"format_version":1,"enemy_sprites":{},"room_tiles":{},"room_sprites":{}}
static func identifier(value) -> bool:
	if not value is String or value.is_empty() or value.length()>64: return false
	for c in value:
		if c not in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true
static func asset_id(value) -> bool:
	if not value is String: return false
	var parts: PackedStringArray = value.split("/")
	return parts.size() == 3 and parts[0] == "art" and identifier(parts[1]) and identifier(parts[2])
static func fields(data: Dictionary, allowed: Array, errors: PackedStringArray) -> void:
	for key in data:
		if key not in allowed: errors.append("Authored appearance: unknown field "+str(key))
static func validate(data, pack: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary: return PackedStringArray(["Authored appearance must be an object"])
	fields(data,["format_version","enemy_sprites","room_tiles","room_sprites"],errors)
	if data.get("format_version") != 1: errors.append("Unsupported authored appearance version")
	for key in ["enemy_sprites","room_tiles","room_sprites"]:
		if not data.get(key) is Dictionary: errors.append("Authored appearance needs "+key+" object")
	if not errors.is_empty(): return errors
	var rooms: Dictionary = {}
	for room in pack.get("rooms",[]):
		if room is Dictionary and room.get("id") is String: rooms[room.id] = room
	var definitions = pack.get("enemy_types",{})
	if not definitions is Dictionary: definitions = {}
	for id in data.enemy_sprites:
		if not definitions.has(id) or not asset_id(data.enemy_sprites[id]): errors.append("Invalid authored enemy sprite: "+str(id))
	for id in data.room_tiles:
		var visual = data.room_tiles[id]
		if not rooms.has(id) or not visual is Dictionary: errors.append("Invalid authored room art: "+str(id));continue
		fields(visual,["atlas","indices"],errors)
		if not asset_id(visual.get("atlas")): errors.append("Authored atlas must use art/library/asset ID")
		var indices = visual.get("indices")
		if not indices is Array or indices.size()!=176: errors.append("Authored room art needs 176 tile indices");continue
		for index in indices:
			if not (index is int or index is float) or not is_finite(float(index)) or float(index)!=floor(float(index)) or index< -1 or index>65535: errors.append("Invalid authored tile index");break
	for id in data.room_sprites:
		var sprites = data.room_sprites[id]
		if not rooms.has(id) or not sprites is Dictionary: errors.append("Invalid authored room sprite binding");continue
		fields(sprites,["secret","stairs","resident"],errors)
		for slot in sprites:
			if not asset_id(sprites[slot]): errors.append("Room sprites require authored art IDs")
			if slot == "secret" and not rooms[id].has("secret"): errors.append("Secret art needs a room secret")
			if slot == "resident" and not rooms[id].has("resident"): errors.append("Resident art needs a resident")
			if slot == "stairs":
				var stairs = rooms[id].get("stairs",[])
				if not stairs is Array or stairs.is_empty(): errors.append("Stair art needs a stair link")
	return errors
static func prune(pack: Dictionary) -> void:
	if not pack.get("appearance") is Dictionary: return
	var data: Dictionary = pack.appearance
	var rooms: Dictionary = {}
	for room in pack.rooms: rooms[room.id] = room
	for field in ["room_tiles","room_sprites"]:
		for id in data[field].keys():
			if not rooms.has(id): data[field].erase(id)
	for id in data.room_sprites.keys():
		var slots: Dictionary = data.room_sprites[id]
		for slot in slots.keys():
			if (slot in ["resident","secret"] and not rooms[id].has(slot)) or (slot == "stairs" and rooms[id].get("stairs",[]).is_empty()): slots.erase(slot)
		if slots.is_empty(): data.room_sprites.erase(id)
	for id in data.enemy_sprites.keys():
		if not pack.enemy_types.has(id): data.enemy_sprites.erase(id)
	if data.enemy_sprites.is_empty() and data.room_tiles.is_empty() and data.room_sprites.is_empty(): pack.erase("appearance")
