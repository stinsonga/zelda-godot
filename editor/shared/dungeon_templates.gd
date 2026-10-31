extends RefCounted
const Pack = preload("room_pack.gd")
const Bindings = preload("art_bindings.gd")
const ROLES := ["start","key","item","combat","treasure","goal"]
## Rooms are 16x11 tiles, so they mirror rather than turn: a format-3 template
## may list any of these to give the generator mirrored versions.
const MIRRORS := ["horizontal","vertical","both"]
static func defaults() -> Dictionary:
	var catalog := {"format_version":1,"id":"native_templates","enemy_types":Pack.fresh().enemy_types,"templates":[]}
	for role in ROLES:
		var room := Pack.room(role,role.capitalize()+" chamber")
		if role == "combat" or role == "goal": room.enemies = [{"id":"guard","type":"crawler","position":[80,61]}]
		catalog.templates.append({"id":role+"_plain","role":role,"weight":2,"ports":Pack.EDGES.duplicate(),"requires":[],"room":room})
	var pillar := Pack.room("pillars","Pillar gallery")
	for cell in [Vector2i(4,3),Vector2i(11,3),Vector2i(4,7),Vector2i(11,7)]:
		var row: String = pillar.tiles[cell.y]
		pillar.tiles[cell.y] = row.left(cell.x)+"#"+row.substr(cell.x+1)
	for role in ["key","item","treasure","combat"]:
		var room := pillar.duplicate(true)
		if role == "combat": room.enemies = [{"id":"guard","type":"crawler","position":[80,77]}]
		catalog.templates.append({"id":role+"_pillars","role":role,"weight":1,"ports":Pack.EDGES.duplicate(),"requires":[],"room":room})
	return catalog
static func validate(data) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary: return PackedStringArray(["Template library must be an object"])
	Pack.unknown_fields(data,["format_version","id","enemy_types","templates"],"Templates",errors)
	if not Pack.integer(data.get("format_version"),1,3) or not Pack.identifier(data.get("id")): errors.append("Invalid template library version or ID");return errors
	if not data.get("enemy_types") is Dictionary or not data.get("templates") is Array: errors.append("Template library needs enemy_types and templates");return errors
	if data.templates.is_empty() or data.templates.size()>128: errors.append("Template library needs 1..128 templates");return errors
	var ids: Dictionary = {}
	var roles: Dictionary = {}
	var enemy_art: Dictionary = {}
	for entry in data.templates:
		if not entry is Dictionary: errors.append("Template must be an object");continue
		Pack.unknown_fields(entry,["id","role","weight","ports","requires","room"] + (["annexes","reward","appearance"] if data.format_version >= 2 else [])+(["mirrors","companion_ports"] if data.format_version >= 3 else []),"Template",errors)
		if not Pack.identifier(entry.get("id")) or ids.has(entry.get("id")): errors.append("Template IDs must be unique");continue
		ids[entry.id] = true
		if entry.get("role") not in ROLES: errors.append(entry.id+": invalid role")
		else: roles[entry.role] = true
		if not Pack.integer(entry.get("weight"),1,100): errors.append(entry.id+": weight must be 1..100")
		for field in ["ports","requires"]:
			var values = entry.get(field)
			if not values is Array: errors.append(entry.id+": invalid "+field);continue
			if field == "ports" and values.is_empty(): errors.append(entry.id+": choose at least one door port")
			var seen: Array = []
			for value in values:
				if value not in (Pack.EDGES if field == "ports" else Pack.REQUIRED_ITEMS) or value in seen: errors.append(entry.id+": invalid or duplicate "+field)
				seen.append(value)
		if not entry.get("room") is Dictionary: errors.append(entry.id+": missing room");continue
		var annexes = entry.get("annexes",[])
		if not annexes is Array or annexes.size()>3: errors.append(entry.id+": use at most three companion rooms");continue
		var rooms: Array = [entry.room]+annexes
		for room in rooms:
			if not room is Dictionary: errors.append(entry.id+": annex must be a room");continue
			if data.format_version < 3 and room.get("connections") != {}: errors.append(entry.id+": template room connections must be empty; use format 3 for internal doors")
			if data.format_version < 3 and room != entry.room and room.get("kind") != "cellar": errors.append(entry.id+": annexes must be cellar rooms")
		var pack := {"schema":2,"id":"template_check","title":"Template","start_room":entry.room.get("id",""),"enemy_types":data.enemy_types,"rooms":rooms,"starting_items":[],"goals":[]}
		if entry.has("appearance"): pack.appearance = entry.appearance
		var room_errors := Pack.validate(pack)
		for error in room_errors: errors.append(entry.id+": "+error)
		if not room_errors.is_empty(): continue
		for variant in entry.get("appearance",{}).get("enemy_sprites",{}):
			var art: String = entry.appearance.enemy_sprites[variant]
			if enemy_art.has(variant) and enemy_art[variant] != art: errors.append("Conflicting template art for enemy variant "+variant)
			enemy_art[variant] = art
		if not Pack.layout_warnings(pack).is_empty(): errors.append(entry.id+": all rooms must be reachable and internal doors must join adjacent map cells")
		if entry.has("companion_ports"):
			for error in companion_port_problems(entry): errors.append(entry.id+": "+error)
		if entry.has("mirrors"):
			var mirror_errors := mirror_problems(entry)
			for error in mirror_errors: errors.append(entry.id+": "+error)
			if mirror_errors.is_empty():
				for mode in entry.mirrors:
					var flipped := mirrored(entry,mode)
					var check := pack.duplicate();check.rooms = [flipped.room]+flipped.get("annexes",[])
					for error in Pack.validate(check): errors.append(entry.id+" ("+mode+"): "+error)
		if data.format_version >= 3 and entry.get("ports") is Array:
			for edge in entry.ports:
				if entry.room.connections.has(edge): errors.append(entry.id+": external port overlaps an internal door: "+str(edge))
		if entry.has("reward"):
			var reward = entry.reward
			if not reward is Dictionary: errors.append(entry.id+": reward must name a room and position");continue
			Pack.unknown_fields(reward,["room","position"],entry.id+" reward",errors)
			var matches: Array = rooms.filter(func(room): return room.id == reward.get("room"))
			if matches.is_empty() or not Pack.point(reward.get("position"),0,240,0,157): errors.append(entry.id+": reward needs a template-local room and valid position");continue
			var destination: Dictionary = matches[0]
			if not Pack.walkable(destination.tiles,reward.position): errors.append(entry.id+": reward feet need floor")
			if destination.has("secret") and Pack.block_overlaps(destination.secret,reward.position,false) and destination.secret.reveal != "item": errors.append(entry.id+": a reward under a block needs item reveal mode")

	for role in ROLES:
		if not roles.has(role): errors.append("Missing template role: "+role)
	return errors
static func read(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length()>2000000: return {"errors":PackedStringArray(["Cannot read template library (maximum 2 MB)"])}
	var data = JSON.parse_string(file.get_as_text())
	return {"catalog":data,"errors":validate(data)}
static func canonical(value) -> String:
	if value is Dictionary:
		var keys: Array = value.keys();keys.sort_custom(func(a,b): return String(a)<String(b))
		var parts: PackedStringArray = []
		for key in keys: parts.append(JSON.stringify(String(key))+":"+canonical(value[key]))
		return "{"+",".join(parts)+"}"
	if value is Array:
		var parts: PackedStringArray = []
		for entry in value: parts.append(canonical(entry))
		return "["+",".join(parts)+"]"
	if value is float and value == floor(value): return JSON.stringify(int(value))
	return JSON.stringify(value)
static func fingerprint(data: Dictionary) -> String: return canonical(data).sha256_text()
static func capture(catalog: Dictionary, pack: Dictionary, room_id: String, id: String, role: String, ports: Array, requirements: Array, include_linked: bool = false, reward_room: String = "", reward_position: Array = [120,77], door_rooms: Array = []) -> Dictionary:
	if not door_rooms.is_empty(): return capture_unit(catalog,pack,room_id,id,role,ports,requirements,include_linked,reward_room,reward_position,door_rooms)
	if include_linked or not reward_room.is_empty(): return capture_unit(catalog,pack,room_id,id,role,ports,requirements,include_linked,reward_room,reward_position)
	var source_errors := Pack.validate(pack)
	if not source_errors.is_empty(): return {"errors":source_errors}
	var output := catalog.duplicate(true)
	if output.templates.any(func(t): return t.id == id): return {"errors":PackedStringArray(["Template ID already exists; choose a new ID"])}
	var matches: Array = pack.rooms.filter(func(r): return r.id == room_id)
	if matches.is_empty(): return {"errors":PackedStringArray(["Room is missing"])}
	if not matches[0].get("stairs",[]).is_empty(): return {"errors":PackedStringArray(["Linked stairs require multi-room templates; remove the links before capturing a single room."])}
	var room: Dictionary = matches[0].duplicate(true)
	room.connections = {}
	room.erase("template_id");room.erase("role");room.erase("floor")
	room.map_position = [0,0]
	var variants: Dictionary = {}
	for enemy in room.enemies:
		var original: String = enemy.type
		var scoped := id.left(20)+"_"+original.left(20)+"_"+(id+"/"+original).sha256_text().left(8)
		if output.enemy_types.has(scoped) and output.enemy_types[scoped] != pack.enemy_types[original]: return {"errors":PackedStringArray(["Scoped enemy definition collision"])}
		output.enemy_types[scoped] = pack.enemy_types[original].duplicate(true)
		enemy.type = scoped;variants[original] = scoped
	var entry := {"id":id,"role":role,"weight":1,"ports":ports.duplicate(),"requires":requirements.duplicate(),"room":room}
	attach_art(output,entry,pack,[room_id],variants)
	output.templates.append(entry)
	return {"catalog":output,"errors":validate(output)}

## Stair closure is explicit: include only cellar destinations, never another
## main dungeon room or a silent partial copy of an external link.
static func linked_rooms(pack: Dictionary, root: String) -> Dictionary:
	var lookup: Dictionary = {}
	for room in pack.rooms: lookup[room.id] = room
	if not lookup.has(root): return {"errors":PackedStringArray(["Primary room is missing"])}
	var pending: Array = [root]
	var found: Dictionary = {root:true}
	var cursor := 0
	while cursor<pending.size():
		var room: Dictionary = lookup[pending[cursor]];cursor+=1
		if room.id != root and (room.get("kind") != "cellar" or not room.connections.is_empty()): return {"errors":PackedStringArray(["Linked room "+String(room.id)+" must be a cellar with no external door connections"])}
		for stair in room.get("stairs",[]):
			if found.has(stair.target): continue
			if not lookup.has(stair.target): return {"errors":PackedStringArray(["Missing linked room "+String(stair.target)])}
			found[stair.target] = true;pending.append(stair.target)
			if pending.size()>4: return {"errors":PackedStringArray(["Capture supports one primary room and at most three linked cellars"])}
	var annex_ids: Array = found.keys();annex_ids.erase(root);annex_ids.sort()
	var rooms: Array = [lookup[root]]
	for id in annex_ids: rooms.append(lookup[id])
	return {"errors":PackedStringArray(),"rooms":rooms}
static func capture_unit(catalog: Dictionary, pack: Dictionary, root: String, id: String, role: String, ports: Array, requirements: Array, include_linked: bool, reward_room: String, reward_position: Array, door_rooms: Array = []) -> Dictionary:
	var errors := Pack.validate(pack)
	if not errors.is_empty(): return {"errors":errors}
	if not validate(catalog).is_empty(): return {"errors":validate(catalog)}
	if catalog.templates.any(func(t): return t.id == id): return {"errors":PackedStringArray(["Template ID already exists; choose a new ID"])}
	var selected := door_group_rooms(pack,root,door_rooms,include_linked) if not door_rooms.is_empty() else linked_rooms(pack,root)
	if not selected.errors.is_empty(): return selected
	if door_rooms.is_empty() and not include_linked and selected.rooms.size()>1: return {"errors":PackedStringArray(["Enable linked-cellar capture to preserve these stair destinations"])}
	var output := catalog.duplicate(true);output.format_version = maxi(int(output.format_version),3 if not door_rooms.is_empty() else 2)
	var rooms: Array = selected.rooms.duplicate(true)
	var variants: Dictionary = {}
	var members: Array = rooms.map(func(room): return room.id)
	var min_x := 15;var max_y := -15
	for room in rooms: min_x = mini(min_x,int(room.map_position[0]));max_y = maxi(max_y,int(room.map_position[1]))
	for i in rooms.size():
		var room: Dictionary = rooms[i]
		if door_rooms.is_empty(): room.connections = {}
		else:
			for edge in room.connections.keys():
				if room.connections[edge].target not in members: room.connections.erase(edge)
		room.erase("template_id");room.erase("role");room.erase("floor")
		room.map_position = [i,0] if door_rooms.is_empty() else [int(room.map_position[0])-min_x,int(room.map_position[1])-max_y]
		for enemy in room.enemies:
			var original: String = enemy.type
			var scoped := id.left(20)+"_"+original.left(20)+"_"+(id+"/"+original).sha256_text().left(8)
			if output.enemy_types.has(scoped) and canonical(output.enemy_types[scoped]) != canonical(pack.enemy_types[original]): return {"errors":PackedStringArray(["Scoped enemy definition collision"])}
			output.enemy_types[scoped] = pack.enemy_types[original].duplicate(true);enemy.type = scoped;variants[original] = scoped
	var entry := {"id":id,"role":role,"weight":1,"ports":ports.duplicate(),"requires":requirements.duplicate(),"room":rooms[0]}
	if rooms.size()>1: entry.annexes = rooms.slice(1)
	if not reward_room.is_empty(): entry.reward = {"room":reward_room,"position":reward_position.duplicate()}
	attach_art(output,entry,pack,rooms.map(func(room): return room.id),variants)
	output.templates.append(entry)
	return {"catalog":output,"errors":validate(output)}
## Pure expansion: map every local destination within this occurrence.
static func instantiate(entry: Dictionary, primary_id: String) -> Dictionary:
	var rooms: Array = [entry.room.duplicate(true)]
	for annex in entry.get("annexes",[]): rooms.append(annex.duplicate(true))
	var names: Dictionary = {entry.room.id:primary_id}
	for i in range(1,rooms.size()): names[rooms[i].id] = primary_id+("_cellar_" if rooms[i].get("kind")=="cellar" else "_part_")+str(i)
	for room in rooms:
		room.id = names[room.id]
		for stair in room.get("stairs",[]): stair.target = names[stair.target]
		for link in room.connections.values(): link.target = names[link.target]
	var reward: Dictionary = entry.get("reward",{"room":entry.room.id,"position":[120,77]})
	var reward_room: Dictionary
	for room in rooms:
		if room.id == names[reward.room]: reward_room = room;break
	var result := {"primary":rooms[0],"annexes":rooms.slice(1),"reward_room":reward_room,"reward_position":reward.position.duplicate()}
	if entry.has("appearance"):
		var art: Dictionary = entry.appearance.duplicate(true)
		for field in ["room_tiles","room_sprites"]:
			var remapped: Dictionary = {}
			for id in art[field]: remapped[names[id]] = art[field][id]
			art[field] = remapped
		result.appearance = art
	return result

## Capture only the shared art belonging to this unit. ROM overlays never enter
## the pack, and scoped enemy IDs keep independently captured skins distinct.
static func attach_art(catalog: Dictionary, entry: Dictionary, pack: Dictionary, room_ids: Array, variants: Dictionary) -> void:
	if not pack.has("appearance"): return
	var art := Bindings.fresh()
	for field in ["room_tiles","room_sprites"]:
		for id in room_ids:
			if pack.appearance[field].has(id): art[field][id] = pack.appearance[field][id].duplicate(true)
	for id in variants:
		if pack.appearance.enemy_sprites.has(id): art.enemy_sprites[variants[id]] = pack.appearance.enemy_sprites[id]
	if art.enemy_sprites.is_empty() and art.room_tiles.is_empty() and art.room_sprites.is_empty(): return
	catalog.format_version = maxi(int(catalog.format_version),2)
	entry.appearance = art

## Explicit membership avoids accidentally capturing the entire connected dungeon.
## Outgoing stairs may add cellar closure; door membership is always deliberate.
static func door_group_rooms(pack: Dictionary, root: String, chosen: Array, include_cellars: bool) -> Dictionary:
	var lookup: Dictionary = {}
	for room in pack.rooms: lookup[room.id] = room
	var ids: Array = [root]
	for id in chosen:
		if id == root or id in ids: return {"errors":PackedStringArray(["Choose each companion room once, excluding the primary"])}
		ids.append(id)
	var cursor := 0
	while cursor < ids.size():
		var id = ids[cursor];cursor += 1
		if not lookup.has(id): return {"errors":PackedStringArray(["Selected room is missing: "+str(id)])}
		if ids.size()>4: return {"errors":PackedStringArray(["Capture supports one primary and at most three companion rooms"])}
		for stair in lookup[id].get("stairs",[]):
			if stair.target in ids: continue
			if not include_cellars or not lookup.has(stair.target) or lookup[stair.target].get("kind") != "cellar": return {"errors":PackedStringArray(["Stair destinations must be selected, or included through linked-cellar capture"])}
			ids.append(stair.target)
	var companions := ids.slice(1);companions.sort()
	var rooms: Array = [lookup[root]]
	for id in companions: rooms.append(lookup[id])
	return {"errors":PackedStringArray(),"rooms":rooms}

static func mirror_problems(entry: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var values = entry.mirrors
	var distinct: Array = []
	if values is Array:
		for value in values:
			if value in MIRRORS and value not in distinct: distinct.append(value)
	if not values is Array or values.is_empty() or distinct.size() != values.size():
		errors.append("mirrors must list distinct horizontal, vertical or both");return errors
	var rooms: Array = [entry.room]+entry.get("annexes",[])
	var art: Dictionary = entry.get("appearance",{})
	if not art.get("room_tiles",{}).is_empty() or not art.get("room_sprites",{}).is_empty(): errors.append("room art is drawn one way; mirror only templates without room art")
	if values.any(func(v): return v != "horizontal") and rooms.any(func(r): return r.get("kind") == "cellar" or r.has("resident")):
		errors.append("cellars and residents only mirror horizontally")
	return errors
## A copy of a template entry mirrored left-right, top-bottom, or both.
static func mirrored(entry: Dictionary, mode: String) -> Dictionary:
	var flip_x := mode in ["horizontal","both"]
	var flip_y := mode in ["vertical","both"]
	var result := entry.duplicate(true)
	result.erase("mirrors")
	result.ports = entry.ports.map(func(edge): return mirror_edge(edge,flip_x,flip_y))
	for id in result.get("companion_ports",{}): result.companion_ports[id] = result.companion_ports[id].map(func(edge): return mirror_edge(edge,flip_x,flip_y))
	var origin: Array = entry.room.map_position
	var rooms: Array = [result.room]+result.get("annexes",[])
	for room in rooms:
		room.tiles = room.tiles.map(func(row): return row.reverse() if flip_x else row)
		if flip_y: room.tiles.reverse()
		room.spawn = mirror_position(room.spawn,flip_x,flip_y)
		for field in ["enemies","pickups"]:
			for placement in room[field]: placement.position = mirror_position(placement.position,flip_x,flip_y)
		var links: Dictionary = {}
		for edge in room.connections: links[mirror_edge(edge,flip_x,flip_y)] = room.connections[edge]
		room.connections = links
		if room.has("secret"):
			room.secret.cell = mirror_cell(room.secret.cell,flip_x,flip_y)
			room.secret.direction = mirror_edge(room.secret.direction,flip_x,flip_y)
		for stair in room.get("stairs",[]):
			stair.cell = mirror_cell(stair.cell,flip_x,flip_y)
			stair.target_position = mirror_position(stair.target_position,flip_x,flip_y)
		var offset := Vector2i(int(room.map_position[0])-int(origin[0]),int(room.map_position[1])-int(origin[1]))
		if flip_x: offset.x = -offset.x
		if flip_y: offset.y = -offset.y
		room.map_position = [int(origin[0])+offset.x,int(origin[1])+offset.y]
	# Only offsets matter; keep the unit's local cells in the valid map range.
	var shift := Vector2i(maxi(0,-rooms.map(func(r): return int(r.map_position[0])).min()),mini(0,-rooms.map(func(r): return int(r.map_position[1])).max()))
	for room in rooms: room.map_position = [int(room.map_position[0])+shift.x,int(room.map_position[1])+shift.y]
	if result.has("reward"): result.reward.position = mirror_position(result.reward.position,flip_x,flip_y)
	return result
static func mirror_edge(edge: String, flip_x: bool, flip_y: bool) -> String:
	if (flip_x and edge in ["left","right"]) or (flip_y and edge in ["up","down"]): return Pack.OPPOSITE[edge]
	return edge
static func mirror_cell(cell: Array, flip_x: bool, flip_y: bool) -> Array:
	return [15-int(cell[0]) if flip_x else int(cell[0]),10-int(cell[1]) if flip_y else int(cell[1])]
## Link's sixteen-pixel body mirrors exactly across the room's width. Vertically
## his feet (y+11) decide the tile, so the foot row mirrors and keeps its offset.
static func mirror_position(at: Array, flip_x: bool, flip_y: bool) -> Array:
	var x := int(at[0]);var y := int(at[1])
	if flip_x: x = 240-x
	if flip_y:
		var foot := y+11
		y = 16*(10-foot/16)+foot%16-11
	return [x,y]
## Each template and its mirrored versions, in a fixed order. Libraries without
## mirrors list exactly their templates, keeping earlier seed results.
static func variants(templates: Array) -> Array:
	var result: Array = []
	for entry in templates:
		result.append(entry)
		for mode in entry.get("mirrors",[]): result.append(mirrored(entry,mode))
	return result

## Ports on dungeon companions: each names a companion by its local ID and lists
## distinct edges that are not internal doors and lead out of the unit.
static func companion_port_problems(entry: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var ports = entry.companion_ports
	if not ports is Dictionary or ports.is_empty(): return PackedStringArray(["companion_ports must map companion IDs to edges"])
	var rooms: Array = [entry.room]+entry.get("annexes",[])
	var cells: Dictionary = {}
	for room in rooms: cells[Vector2i(int(room.map_position[0]),int(room.map_position[1]))] = true
	for id in ports:
		var matches: Array = entry.get("annexes",[]).filter(func(r): return r.id == id)
		if matches.is_empty() or matches[0].get("kind") == "cellar": errors.append("companion port room must be a dungeon companion: "+str(id));continue
		var room: Dictionary = matches[0]
		var edges = ports[id]
		if not edges is Array or edges.is_empty(): errors.append(str(id)+": list at least one companion port");continue
		var seen: Array = []
		for edge in edges:
			if edge not in Pack.EDGES or edge in seen: errors.append(str(id)+": invalid or duplicate companion port");continue
			seen.append(edge)
			if room.connections.has(edge): errors.append(str(id)+": companion port overlaps an internal door: "+edge)
			var outside: Vector2i = Vector2i(int(room.map_position[0]),int(room.map_position[1]))+{"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}[edge]
			if cells.has(outside): errors.append(str(id)+": companion port "+edge+" leads into its own unit")
	return errors
