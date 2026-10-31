extends RefCounted
## Renaming placements, enemy variants and the pack itself. Placement and pack
## IDs appear in saves, so like rooms they keep flat histories; enemy variants
## do not, so renaming one only rewrites the pack.
##
## placement_aliases: {"pickups": {"room/old": "room/new"}, "enemies": {...}}.
## An empty target marks a deleted placement. previous_ids: earlier pack IDs.
const RoomIds = preload("room_ids.gd")
const FIELDS := ["pickups","enemies"]
const LIMIT := 1024

static func placement_key(room: String, id: String) -> String: return room+"/"+id
static func live(pack: Dictionary, field: String, key: String) -> bool:
	var parts := key.split("/")
	if parts.size() != 2: return false
	return pack.rooms.any(func(room): return room.id == parts[0] and room.get(field,[]).any(func(p): return p.id == parts[1]))

static func validate(pack: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if pack.has("placement_aliases"):
		var aliases = pack.placement_aliases
		if not aliases is Dictionary or aliases.keys().any(func(k): return k not in FIELDS): return PackedStringArray(["Placement aliases need pickups and enemies objects"])
		for field in aliases:
			var map = aliases[field]
			if not map is Dictionary or map.size() > LIMIT: errors.append("Placement aliases for "+field+" must be an object with at most 1024 entries");continue
			for old in map:
				var parts: PackedStringArray = String(old).split("/")
				if parts.size() != 2 or not RoomIds.valid_id(parts[0]) or not RoomIds.valid_id(parts[1]) or live(pack,field,old): errors.append("Historical placement IDs must be valid, reserved room/placement names: "+str(old))
				var target = map[old]
				if not target is String or (not target.is_empty() and (not live(pack,field,target) or target.get_slice("/",0) != parts[0])): errors.append("Placement aliases must point to a live placement in the same room, or be empty: "+str(old))
	if pack.has("previous_ids"):
		var ids = pack.previous_ids
		if not ids is Array or ids.size() > 64: return errors+PackedStringArray(["Previous pack IDs must be a list of at most 64"])
		var seen: Array = []
		for id in ids:
			if not RoomIds.valid_id(id) or id == pack.id or id in seen: errors.append("Previous pack IDs must be distinct valid IDs other than the current one")
			seen.append(id)
	return errors

## Live or historical in this room; such IDs are never handed out again.
static func reserved_placement(pack: Dictionary, room: String, field: String, id: String) -> bool:
	return live(pack,field,placement_key(room,id)) or pack.get("placement_aliases",{}).get(field,{}).has(placement_key(room,id))

static func rename_placement(pack: Dictionary, room_id: String, field: String, old: String, id: String) -> Dictionary:
	if field not in FIELDS: return {"errors":PackedStringArray(["Only pickups and enemies have placement IDs"])}
	if not RoomIds.valid_id(id): return {"errors":PackedStringArray(["Placement ID needs 1..64 lowercase letters, digits, underscores or hyphens"])}
	if not live(pack,field,placement_key(room_id,old)): return {"errors":PackedStringArray(["Placement is missing"])}
	var output: Dictionary = pack.duplicate(true)
	if old == id: return {"errors":PackedStringArray(),"pack":output}
	if reserved_placement(pack,room_id,field,id): return {"errors":PackedStringArray(["That ID is live or reserved by this room's placement history. Choose a new ID."])}
	var aliases: Dictionary = output.get("placement_aliases",{}).get(field,{})
	if aliases.size() >= LIMIT: return {"errors":PackedStringArray(["Placement migration history limit reached"])}
	if output.schema == 1: output.schema = 2;output.starting_items = ["wooden_sword"];output.goals = []
	var from := placement_key(room_id,old);var to := placement_key(room_id,id)
	for previous in aliases:
		if aliases[previous] == from: aliases[previous] = to
	aliases[from] = to
	if not output.has("placement_aliases"): output.placement_aliases = {}
	output.placement_aliases[field] = aliases
	for room in output.rooms:
		if room.id != room_id: continue
		for placement in room[field]:
			if placement.id == old: placement.id = id
	if field == "pickups":
		for goal in output.goals:
			if goal.room == room_id and goal.pickup == old: goal.pickup = id
	return {"errors":PackedStringArray(),"pack":output}

## A deleted placement's ID stays reserved, so old progress cannot attach to a
## new placement that happens to reuse it.
static func retire_placement(pack: Dictionary, room_id: String, field: String, id: String) -> void:
	if not pack.has("placement_aliases"): pack.placement_aliases = {}
	if not pack.placement_aliases.has(field): pack.placement_aliases[field] = {}
	var aliases: Dictionary = pack.placement_aliases[field]
	var key := placement_key(room_id,id)
	for previous in aliases:
		if aliases[previous] == key: aliases[previous] = ""
	aliases[key] = ""

## Room renames carry the room's placement history along; a deleted room is
## itself reserved, so its placement history can go.
static func rekey_room(pack: Dictionary, old: String, id: String) -> void:
	for field in pack.get("placement_aliases",{}):
		var moved: Dictionary = {}
		var aliases: Dictionary = pack.placement_aliases[field]
		for key in aliases:
			var room := String(key).get_slice("/",0)
			if room == old and id.is_empty(): continue
			var target: String = aliases[key]
			if not target.is_empty() and target.get_slice("/",0) == old: target = placement_key(id,target.get_slice("/",1))
			moved[placement_key(id,String(key).get_slice("/",1)) if room == old else key] = target
		pack.placement_aliases[field] = moved

static func unique_placement_id(pack: Dictionary, room_id: String, field: String, prefix: String) -> String:
	var n := 1
	while reserved_placement(pack,room_id,field,prefix+"_"+str(n)): n += 1
	return prefix+"_"+str(n)

## Enemy variants are pack-local: saves record placements, not variants.
static func rename_variant(pack: Dictionary, old: String, id: String, overlay: Dictionary = {}) -> Dictionary:
	if not RoomIds.valid_id(id): return {"errors":PackedStringArray(["Variant ID needs 1..64 lowercase letters, digits, underscores or hyphens"])}
	if not pack.enemy_types.has(old): return {"errors":PackedStringArray(["Enemy variant is missing"])}
	var output: Dictionary = pack.duplicate(true);var art: Dictionary = overlay.duplicate(true)
	if old == id: return {"errors":PackedStringArray(),"pack":output,"appearance":art}
	if pack.enemy_types.has(id): return {"errors":PackedStringArray(["Another variant already uses that ID"])}
	var types: Dictionary = {}
	for key in output.enemy_types: types[id if key == old else key] = output.enemy_types[key]
	output.enemy_types = types
	for room in output.rooms:
		for enemy in room.enemies:
			if enemy.type == old: enemy.type = id
	for sprites in [output.get("appearance",{}).get("enemy_sprites",{}),art.get("enemy_sprites",{})]:
		if sprites.has(old): sprites[id] = sprites[old];sprites.erase(old)
	return {"errors":PackedStringArray(),"pack":output,"appearance":art}

## On save: a pack published under one ID and saved under another remembers
## the old one, so saves made with it still load.
static func record_identity(pack: Dictionary, published_id: String) -> void:
	if published_id.is_empty() or published_id == pack.id or not RoomIds.valid_id(published_id): return
	var ids: Array = pack.get("previous_ids",[]).filter(func(id): return id != pack.id)
	if published_id not in ids: ids.append(published_id)
	pack.previous_ids = ids.slice(-64)
