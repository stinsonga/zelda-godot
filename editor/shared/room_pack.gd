extends RefCounted
## The single, engine-independent pack contract, loaded by both Godot projects.
## JSON is data only: no script, resource or external asset paths are accepted.
const VERSION := 1 # Fresh/v1 documents remain backwards compatible.
const REQUIRED_ITEMS := ["wooden_sword","bow","ladder","blue_candle","recorder","magic_key"]
const ITEM_SLOTS := {"wooden_sword":"sword","bow":"bow","ladder":"ladder","blue_candle":"candle","recorder":"recorder","magic_key":"magic_key"}
const EDGES := ["up", "right", "down", "left"]
const OPPOSITE := {"up":"down", "down":"up", "left":"right", "right":"left"}
const KINDS := ["open", "key", "bombable", "shutter", "false", "wall"]
const ITEMS := ["key", "rupee", "heart", "bombs", "wooden_sword","bow","ladder","blue_candle","recorder","magic_key"]
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
	var version = pack.get("schema")
	var fields := ["schema","id","title","start_room","rooms","enemy_types"]
	if version == 2: fields.append_array(["starting_items","goals","generation"])
	unknown_fields(pack,fields,"Pack",errors)
	if version != 1 and version != 2: errors.append("Unsupported pack schema; expected 1 or 2")
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
		var room_fields: Array = ROOM_FIELDS.duplicate()
		if version == 2: room_fields.append_array(["template_id","role","secret","stairs","kind","resident"])
		unknown_fields(r,room_fields,id,errors)
		if version == 2:
			if r.has("kind") and r.kind not in ["dungeon","cellar","cave"]: errors.append(id + ": room kind must be dungeon, cellar or cave")
			if r.has("template_id") and not identifier(r.template_id): errors.append(id + ": invalid template ID")
			if r.has("role") and r.role not in ["start","key","item","combat","treasure","goal"]: errors.append(id + ": invalid template role")
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
		if not integer(r.get("shutter_trigger"),0,4) or int(r.get("shutter_trigger")) not in ([0,1,4] if version == 2 else [0,1]): errors.append(id + ": shutter trigger must be 0 (one-way), 1 (clear enemies), or 4 (push block)")
		if r.has("resident"): validate_resident(r,errors)
		if r.has("secret"): validate_block(r,good_tiles,errors)
		elif r.get("shutter_trigger") == 4: errors.append(id + ": push-block shutters require a block secret")
		for field in ["enemies","pickups"]:
			var entries = r.get(field)
			if not entries is Array or entries.size() > (10 if field == "enemies" else 32): errors.append(id + ": invalid " + field + " list"); continue
			var spawn_ids: Dictionary = {}
			for entry in entries:
				if not entry is Dictionary: errors.append(id + ": invalid placement"); continue
				var placement_fields := ["id","type","position"] if field == "enemies" else ["id","item","position"]
				if version == 2 and field == "pickups": placement_fields.append_array(["requires_clear","requires_secret"])
				unknown_fields(entry,placement_fields,id,errors)
				for flag in ["requires_clear","requires_secret"]:
					if entry.has(flag) and not entry[flag] is bool: errors.append(id + ": " + flag + " must be true or false")
				if entry.get("requires_secret") == true and not r.has("secret"): errors.append(id + ": secret-gated pickup needs a room secret")
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
			unknown_fields(link,["target","kind","requires"] if version == 2 else ["target","kind"],id,errors)
			if version == 2 and link.has("requires"):
				if not link.requires is Array: errors.append(id + ": connection requirements must be a list")
				else:
					var seen_requirements: Array = []
					for requirement in link.requires:
						if requirement not in REQUIRED_ITEMS or requirement in seen_requirements: errors.append(id + ": invalid or duplicate required item")
						seen_requirements.append(requirement)
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
			if not reverse is Dictionary or reverse.get("target") != id or reverse.get("kind") != link.get("kind") or requirements(reverse) != requirements(link):
				errors.append(id + ": connection " + edge + " needs a reciprocal door of the same kind")
	if version == 2:
		validate_stairs(ids,errors)
		validate_progression(pack,ids,errors)
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
		var links: Array = rooms[id].connections.values().duplicate()
		for stair in rooms[id].get("stairs",[]): links.append({"target":stair.target,"kind":"open"})
		for link in links:
			if link.kind == "wall" or visited.has(link.target): continue
			visited[link.target] = true
			pending.append(link.target)
	for room in pack.rooms:
		if not visited.has(room.id): warnings.append(room.id + ": no potential connection path from the starting room")
	return warnings

static func requirements(link: Dictionary) -> Array:
	var values = link.get("requires",[])
	if not values is Array: return []
	var result: Array = values.duplicate()
	# Validate elements before sorting, so malformed input never crashes review.
	for value in result:
		if not value is String: return []
	result.sort()
	return result
static func upgrade(pack: Dictionary) -> void:
	if pack.schema == 2: return
	pack.schema = 2
	pack.starting_items = ["wooden_sword"]
	pack.goals = []
static func validate_progression(pack: Dictionary, rooms: Dictionary, errors: PackedStringArray) -> void:
	var starting = pack.get("starting_items")
	if not starting is Array or starting.size() > 32: errors.append("Version 2 needs at most 32 starting_items")
	else:
		for item in starting:
			if item not in REQUIRED_ITEMS and item not in ["key","bombs"]: errors.append("Unsupported starting item")
	var goals = pack.get("goals")
	if not goals is Array or goals.size() > 16: errors.append("Version 2 needs a goals list (at most 16)")
	else:
		var seen: Array = []
		for goal in goals:
			if not goal is Dictionary: errors.append("Goal must name a room and pickup"); continue
			unknown_fields(goal,["room","pickup"],"Goal",errors)
			if not goal.get("room") is String or not goal.get("pickup") is String: errors.append("Goal needs room/pickup IDs"); continue
			var key: String = goal.room + "/" + goal.pickup
			if key in seen: errors.append("Duplicate goal")
			seen.append(key)
			if not rooms.has(goal.room): errors.append("Goal room is missing"); continue
			var pickups = rooms[goal.room].get("pickups")
			if not pickups is Array or not pickups.any(func(p): return p is Dictionary and p.get("id") == goal.pickup): errors.append("Goal pickup is missing")
	if pack.has("generation"):
		var g = pack.generation
		if not g is Dictionary: errors.append("Generation provenance must be an object"); return
		unknown_fields(g,["algorithm","version","seed","template_sha256","room_count","required_item","templates"],"Generation",errors)
		if g.get("algorithm") != "authored_tree" or not integer(g.get("version"),1,4) or not integer(g.get("seed"),0,2147483647) or not integer(g.get("room_count"),6,16): errors.append("Unsupported generator provenance")
		var hash = g.get("template_sha256")
		if not hash is String or hash.length() != 64 or not hash.is_valid_hex_number(): errors.append("Invalid template fingerprint")
		if g.get("required_item") not in REQUIRED_ITEMS or not g.get("templates") is Dictionary: errors.append("Invalid generator template metadata")
		elif g.templates.size() > 256: errors.append("Too many generation template records")
		else:
			for id in g.templates:
				if not identifier(id) or not identifier(g.templates[id]): errors.append("Invalid generation template ID")

## One directional dungeon block. Base tiles remain floor; collision is an overlay.
static func validate_block(room: Dictionary, good_tiles: bool, errors: PackedStringArray) -> void:
	var prefix := String(room.id) + ": "
	var secret = room.secret
	if not secret is Dictionary: errors.append(prefix+"secret must be a block object");return
	unknown_fields(secret,["cell","direction","reveal","trigger"],prefix+"secret",errors)
	if secret_trigger(secret) not in ["block","bomb","fire"] or not point(secret.get("cell"),2,13,2,8) or secret.get("direction") not in EDGES or secret.get("reveal") not in ["shutters","item"]:
		errors.append(prefix+"secret needs a block/bomb/fire trigger, interior cell, cardinal direction and shutters/item reveal");return
	if secret.reveal == "shutters" and room.get("shutter_trigger") != 4: errors.append(prefix+"block-controlled shutters need shutter trigger 4")
	if secret.reveal == "item" and room.get("shutter_trigger") == 4: errors.append(prefix+"use a shutters reveal for shutter trigger 4")
	var cell := Vector2i(int(secret.cell[0]),int(secret.cell[1]))
	var direction: Vector2i = {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}[secret.direction]
	var squares: Array = [cell,cell+direction,cell-direction] if secret_trigger(secret) == "block" else [cell,cell-direction*(2 if secret_trigger(secret) == "fire" else 1)]
	for square in squares:
		if square.x<2 or square.x>13 or square.y<2 or square.y>8:
			errors.append(prefix+"secret object and its interaction approach must lie inside the wall frame")
		elif good_tiles and room.tiles[square.y][square.x] != ".": errors.append(prefix+"secret object and its interaction approach need floor tiles")
	if good_tiles and point(room.get("spawn"),0,240,0,157) and block_overlaps(secret,room.spawn,false): errors.append(prefix+"player spawn overlaps the block")
	for kind in ["enemies","pickups"]:
		var entries = room.get(kind,[])
		if not entries is Array: continue
		for entry in entries:
			if not entry is Dictionary or not point(entry.get("position"),0,240,0,157): continue
			if block_overlaps(secret,entry.position,false) and not (kind == "pickups" and entry.get("requires_secret") == true): errors.append(prefix+"placement overlaps the initial block")
static func block_overlaps(secret: Dictionary, at: Array, pushed: bool) -> bool:
	var cell := Vector2i(int(secret.cell[0]),int(secret.cell[1]))
	if pushed and secret_trigger(secret) != "block": return false
	if pushed: cell += {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}[secret.direction]
	for offset in [0,8]:
		if Vector2i((int(at[0])+offset)/16,(int(at[1])+11)/16) == cell: return true
	return false

static func stair_position(stair: Dictionary) -> Vector2i:
	return Vector2i(int(stair.cell[0])*16,int(stair.cell[1])*16-3)
static func validate_stairs(rooms: Dictionary, errors: PackedStringArray) -> void:
	for id in rooms:
		var room: Dictionary = rooms[id]
		var stairs = room.get("stairs",[])
		if not stairs is Array or stairs.size()>4: errors.append(id+": stairs must be a list of at most four links");continue
		var ids: Dictionary = {}
		var cells: Dictionary = {}
		for stair in stairs:
			var prefix := String(id)+": stairs "
			if not stair is Dictionary: errors.append(prefix+"must be an object");continue
			unknown_fields(stair,["id","cell","target","target_position","requires_secret"],prefix,errors)
			if not identifier(stair.get("id")) or ids.has(stair.get("id")): errors.append(prefix+"IDs must be unique")
			else: ids[stair.id] = true
			if stair.has("requires_secret") and not stair.requires_secret is bool: errors.append(prefix+"requires_secret must be true or false")
			if stair.get("requires_secret") == true and not room.has("secret"): errors.append(prefix+"hidden stairs need a block secret")
			if not point(stair.get("cell"),3,12,3,7): errors.append(prefix+"cell must lie at X 3..12, Y 3..7, clear of door approaches");continue
			var at := stair_position(stair)
			if room.has("resident") and at.y<77: errors.append(prefix+"resident interiors need stairs at row 5 or below, clear of the native resident barrier")
			if cells.has(at): errors.append(prefix+"cells must be unique")
			cells[at] = true
			if not room.get("tiles") is Array or not walkable(room.tiles,[at.x,at.y]): errors.append(prefix+"cell needs walkable floor")
			if point(room.get("spawn"),0,240,0,157) and at == Vector2i(int(room.spawn[0]),int(room.spawn[1])): errors.append(prefix+"cannot cover the room's initial spawn")
			var secret = room.get("secret")
			if secret is Dictionary and point(secret.get("cell"),2,13,2,8) and secret.get("direction") in EDGES:
				if block_overlaps(secret,[at.x,at.y],false) and stair.get("requires_secret") != true: errors.append(prefix+"under a block must require its secret")
				if block_overlaps(secret,[at.x,at.y],true): errors.append(prefix+"cannot occupy the block's landing square")
			if not identifier(stair.get("target")) or not rooms.has(stair.get("target")) or stair.target == id: errors.append(prefix+"needs a different existing destination room");continue
			var target: Dictionary = rooms[stair.target]
			var position = stair.get("target_position")
			if not point(position,0,240,0,157): errors.append(prefix+"invalid arrival position");continue
			if int(position[0])%8 != 0 or posmod(int(position[1])-5,8) != 0: errors.append(prefix+"arrival must lie on the eight-pixel dungeon grid")
			if not target.get("tiles") is Array or not walkable(target.tiles,position): errors.append(prefix+"arrival feet are blocked")
			secret = target.get("secret")
			if secret is Dictionary and point(secret.get("cell"),2,13,2,8) and secret.get("direction") in EDGES and block_overlaps(secret,position,false): errors.append(prefix+"arrival overlaps the destination's reset block")

static func cellar(id: String) -> Dictionary:
	var result := room(id,"Cellar")
	result.kind = "cellar"
	for y in range(2,8): result.tiles[y] = "###.########.###"
	return result

static func resident(mode: String = "hint") -> Dictionary:
	var wares: Array = [null,null,null]
	if mode == "gift": wares[1] = {"item":"wooden_sword","price":0}
	if mode == "shop": wares = [{"item":"bombs","price":10},{"item":"key","price":20},{"item":"heart","price":5}]
	return {"mode":mode,"text":"WELCOME, TRAVELER.","wares":wares}
static func validate_resident(room: Dictionary, errors: PackedStringArray) -> void:
	var prefix := String(room.id)+": resident "
	var data = room.resident
	if not data is Dictionary: errors.append(prefix+"must be an object");return
	unknown_fields(data,["mode","text","wares"],prefix,errors)
	if data.get("mode") not in ["hint","gift","shop"]: errors.append(prefix+"mode must be hint, gift or shop")
	var text = data.get("text")
	if not text is String: errors.append(prefix+"text must be a string")
	elif text.length()>74: errors.append(prefix+"text supports three lines of at most 24 characters")
	else:
		var lines: PackedStringArray = text.split("\n")
		if lines.size()>3: errors.append(prefix+"text supports at most three lines")
		for line in lines:
			if line.length()>24: errors.append(prefix+"text lines support at most 24 characters")
			for character in line:
				if character.unicode_at(0)<32 or character.unicode_at(0)>126: errors.append(prefix+"text requires printable ASCII")
	var wares = data.get("wares")
	if not wares is Array or wares.size()!=3: errors.append(prefix+"needs exactly three ware slots");return
	var count := 0
	for i in range(3):
		var ware = wares[i]
		if ware == null: continue
		count+=1
		if not ware is Dictionary: errors.append(prefix+"ware must be an item/price object or null");continue
		unknown_fields(ware,["item","price"],prefix+"ware",errors)
		if ware.get("item") not in ITEMS or not integer(ware.get("price"),0,255): errors.append(prefix+"ware needs a supported item and price 0..255")
		if data.get("mode") == "gift" and ware.get("price") != 0: errors.append(prefix+"gifts must be free")
		var tiles = room.get("tiles")
		if tiles is Array and not (walkable(tiles,[88+i*32,85]) or walkable(tiles,[88+i*32,93])): errors.append(prefix+"ware approach needs walkable floor")
	if data.get("mode") == "hint" and count!=0: errors.append(prefix+"hints cannot offer wares")
	if data.get("mode") == "gift" and count!=1: errors.append(prefix+"gifts offer exactly one item")
	if data.get("mode") == "shop" and count==0: errors.append(prefix+"shops need at least one item")
	if room.get("enemies") is Array and not room.enemies.is_empty(): errors.append(prefix+"rooms cannot contain enemies in this version")
	if room.has("secret"): errors.append(prefix+"place block secrets in the entrance room, not the resident interior")
	if room.get("pickups") is Array:
		for pickup in room.pickups:
			if pickup is Dictionary and pickup.get("id") == "taken": errors.append(prefix+"reserves pickup ID taken for resident transactions")

static func secret_trigger(secret: Dictionary) -> String:
	var value = secret.get("trigger","block")
	return value if value is String else ""
static func secret_approach(secret: Dictionary) -> Vector2i:
	var direction: Vector2i = {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}[secret.direction]
	var distance := 2 if secret_trigger(secret) == "fire" else 1
	return (Vector2i(int(secret.cell[0]),int(secret.cell[1]))-direction*distance)*16+Vector2i(0,-3)
