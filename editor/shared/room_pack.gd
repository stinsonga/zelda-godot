extends RefCounted
## The single, engine-independent pack contract, loaded by both Godot projects.
## JSON is data only: no script, resource or external asset paths are accepted.
const VERSION := 1
const EDGES := ["up", "right", "down", "left"]
const OPPOSITE := {"up":"down", "down":"up", "left":"right", "right":"left"}
const KINDS := ["open", "key", "bombable", "shutter", "false", "wall"]
const ITEMS := ["key", "rupee", "heart", "bombs", "wooden_sword"]
const BEHAVIORS := ["walker", "jumper", "gel", "rope", "flyer"]
const ROOM_FIELDS := ["id", "title", "tiles", "spawn", "enemies", "pickups", "connections", "shutter_trigger", "map_position"]

static func room(id: String, title: String = "New room") -> Dictionary:
	var tiles: Array = []
	for y in range(11):
		var row := ""
		for x in range(16): row += "#" if x < 2 or x > 13 or y < 2 or y > 8 else "."
		tiles.append(row)
	return {"id":id,"title":title,"tiles":tiles,"spawn":[120,125],"enemies":[],"pickups":[],"connections":{},"shutter_trigger":1,"map_position":[0,0]}

static func fresh() -> Dictionary:
	return {"schema":VERSION,"id":"custom_dungeon","title":"My dungeon","start_room":"entry","rooms":[room("entry", "Entrance")],
		"enemy_types":{"crawler":{"title":"Crawler","behavior":"walker","health":2,"speed_subpixels":128,"contact_damage":1}}}

static func sample() -> Dictionary:
	var pack := fresh()
	pack.title = "Lantern vault"
	pack.id = "lantern_vault"
	var entry: Dictionary = pack.rooms[0]
	var hall := room("hall", "Guard hall")
	var vault := room("vault", "The vault")
	entry.connections = {"up":{"target":"hall","kind":"key"}}
	entry.pickups = [{"id":"entry_key","item":"key","position":[64,77]}]
	hall.connections = {"down":{"target":"entry","kind":"key"},"right":{"target":"vault","kind":"shutter"}}
	hall.map_position = [0,-1]
	hall.enemies = [{"id":"guard_a","type":"crawler","position":[80,61]},{"id":"guard_b","type":"crawler","position":[176,93]}]
	vault.connections = {"left":{"target":"hall","kind":"shutter"}}
	vault.map_position = [1,-1]
	vault.pickups = [{"id":"reward","item":"rupee","position":[120,77]}]
	pack.rooms.append(hall)
	pack.rooms.append(vault)
	return pack

static func integer(v, low: int, high: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and float(v) == floor(float(v)) and v >= low and v <= high

static func point(v, low_x: int, high_x: int, low_y: int, high_y: int) -> bool:
	return v is Array and v.size() == 2 and integer(v[0],low_x,high_x) and integer(v[1],low_y,high_y)

static func identifier(v) -> bool:
	if not v is String or v.is_empty() or v.length() > 64: return false
	for c in v:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func unknown_fields(data: Dictionary, allowed: Array, prefix: String, errors: PackedStringArray) -> void:
	for key in data:
		if key not in allowed: errors.append(prefix + ": unsupported field " + str(key))

static func walkable(tiles: Array, at: Array) -> bool:
	# Match the game's two standing foot probes; don't index malformed tiles.
	if tiles.size() != 11 or not point(at,0,240,0,157): return false
	for x in [int(at[0]),int(at[0])+8]:
		var row = tiles[(int(at[1])+11)/16]
		if not row is String or row.length() != 16 or row[x/16] != ".": return false
	return true

static func validate(pack) -> PackedStringArray:
	var errors := PackedStringArray()
	if not pack is Dictionary: return PackedStringArray(["Pack must be a JSON object"])
	unknown_fields(pack,["schema","id","title","start_room","rooms","enemy_types"],"Pack",errors)
	if pack.get("schema") != VERSION: errors.append("Unsupported pack schema; expected 1")
	if not identifier(pack.get("id")): errors.append("Pack ID needs lowercase letters, digits, underscores or hyphens")
	if not pack.get("title") is String: errors.append("Pack needs a title")
	var definitions = pack.get("enemy_types")
	if not definitions is Dictionary: errors.append("enemy_types must be an object"); definitions = {}
	if definitions.size() > 128: errors.append("At most 128 enemy types are supported")
	for id in definitions:
		var e = definitions[id]
		if not identifier(id) or not e is Dictionary: errors.append("Invalid enemy definition"); continue
		unknown_fields(e,["title","behavior","health","speed_subpixels","contact_damage"],"Enemy " + id,errors)
		if not e.get("title") is String or e.get("behavior") not in BEHAVIORS: errors.append("Enemy " + id + ": invalid title or behavior")
		for field in {"health":[1,255],"speed_subpixels":[0,2048],"contact_damage":[0,16]}:
			var bounds: Array = {"health":[1,255],"speed_subpixels":[0,2048],"contact_damage":[0,16]}[field]
			if not integer(e.get(field),bounds[0],bounds[1]): errors.append("Enemy " + id + ": invalid " + field)
	var rooms = pack.get("rooms")
	if not rooms is Array or rooms.is_empty() or rooms.size() > 256:
		errors.append("Pack needs 1 to 256 rooms")
		return errors
	var ids: Dictionary = {}
	var map_cells: Dictionary = {}
	for r in rooms:
		if not r is Dictionary: errors.append("Room must be an object"); continue
		var id = r.get("id")
		if not identifier(id): errors.append("Invalid room ID"); continue
		if ids.has(id): errors.append("Duplicate room ID: " + id)
		ids[id] = r
		unknown_fields(r,ROOM_FIELDS,id,errors)
		if not r.get("title") is String: errors.append(id + ": title must be text")
		var tiles = r.get("tiles")
		var good_tiles: bool = tiles is Array and tiles.size() == 11
		if good_tiles:
			for row in tiles:
				if not row is String or row.length() != 16: good_tiles = false; break
				for c in row:
					if c not in ".#~": good_tiles = false
		if not good_tiles: errors.append(id + ": tiles need eleven rows of sixteen . # or ~ characters")
		if not point(r.get("spawn"),0,240,0,157): errors.append(id + ": invalid spawn position")
		elif good_tiles and not walkable(tiles,r.spawn): errors.append(id + ": spawn feet are blocked")
		if not point(r.get("map_position"),0,15,-15,0): errors.append(id + ": map position needs X 0..15 and Y -15..0")
		else:
			var map_key := "%d,%d" % [int(r.map_position[0]),int(r.map_position[1])]
			if map_cells.has(map_key): errors.append(id + ": map position overlaps " + str(map_cells[map_key]))
			map_cells[map_key] = id
		if not integer(r.get("shutter_trigger"),0,1): errors.append(id + ": shutter trigger must be 0 (one-way) or 1 (clear enemies)")
		for field in ["enemies","pickups"]:
			var entries = r.get(field)
			if not entries is Array or entries.size() > (10 if field == "enemies" else 32): errors.append(id + ": invalid " + field + " list"); continue
			var spawn_ids: Dictionary = {}
			for entry in entries:
				if not entry is Dictionary: errors.append(id + ": invalid placement"); continue
				unknown_fields(entry,["id","type","position"] if field == "enemies" else ["id","item","position"],id,errors)
				var spawn_id = entry.get("id")
				if not identifier(spawn_id) or spawn_ids.has(spawn_id): errors.append(id + ": placement IDs must be unique within each list")
				else: spawn_ids[spawn_id] = true
				if not point(entry.get("position"),0,240,0,157): errors.append(id + ": invalid placement position")
				elif good_tiles and not walkable(tiles,entry.position): errors.append(id + ": placement feet are blocked")
				if field == "enemies" and not definitions.has(entry.get("type")): errors.append(id + ": unknown enemy type")
				if field == "pickups" and entry.get("item") not in ITEMS: errors.append(id + ": unknown pickup item")
		var connections = r.get("connections")
		if not connections is Dictionary: errors.append(id + ": connections must be an object"); continue
		for edge in connections:
			var link = connections[edge]
			if edge not in EDGES or not link is Dictionary: errors.append(id + ": invalid connection"); continue
			unknown_fields(link,["target","kind"],id,errors)
			if not identifier(link.get("target")) or link.get("kind") not in KINDS: errors.append(id + ": invalid connection target or door kind")
	if not ids.has(pack.get("start_room")): errors.append("Starting room is missing")
	for id in ids:
		var connections = ids[id].get("connections")
		if not connections is Dictionary: continue
		for edge in connections:
			var link = connections[edge]
			if edge not in EDGES or not link is Dictionary: continue
			var target = link.get("target")
			if not ids.has(target): errors.append(id + ": missing destination " + str(target)); continue
			if target == id: errors.append(id + ": self connections are unsupported")
			var back = ids[target].get("connections",{})
			if not back is Dictionary: continue
			var reverse = back.get(OPPOSITE[edge],{})
			if not reverse is Dictionary or reverse.get("target") != id or reverse.get("kind") != link.get("kind"):
				errors.append(id + ": connection " + edge + " needs a reciprocal door of the same kind")
	return errors

static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"errors":PackedStringArray(["Cannot open " + path])}
	if file.get_length() > 2000000: return {"errors":PackedStringArray(["Pack exceeds 2 MB"])}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK: return {"errors":PackedStringArray(["JSON line %d: %s" % [json.get_error_line(),json.get_error_message()]])}
	return {"pack":json.data,"errors":validate(json.data)}

static func write(path: String, pack: Dictionary) -> Error:
	# Replace through a temporary file, so a failed write preserves the old pack.
	var temp := path + ".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(pack,"  ") + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: DirAccess.remove_absolute(temp); return error
	return DirAccess.rename_absolute(temp,path)

## Non-blocking layout review. Locked/bombable/shutter links count as potential
## paths: this checks topology, not inventory, combat or progression solvability.
static func layout_warnings(pack: Dictionary) -> PackedStringArray:
	var warnings := PackedStringArray()
	if not validate(pack).is_empty(): return warnings
	var directions := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
	var rooms: Dictionary = {}
	for room in pack.rooms: rooms[room.id] = room
	for room in pack.rooms:
		for edge in room.connections:
			var link: Dictionary = room.connections[edge]
			if String(room.id) > String(link.target): continue
			var target: Dictionary = rooms[link.target]
			var offset := Vector2i(int(target.map_position[0])-int(room.map_position[0]),int(target.map_position[1])-int(room.map_position[1]))
			if offset != directions[edge]: warnings.append("%s %s -> %s: map positions are not adjacent in that direction" % [room.id,edge,target.id])
	var visited: Dictionary = {pack.start_room:true}
	var pending: Array = [pack.start_room]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		for link in rooms[id].connections.values():
			if link.kind == "wall" or visited.has(link.target): continue
			visited[link.target] = true
			pending.append(link.target)
	for room in pack.rooms:
		if not visited.has(room.id): warnings.append(room.id + ": no potential connection path from the starting room")
	return warnings
