extends RefCounted
const Pack = preload("room_pack.gd")
const ROLES := ["start","key","item","combat","treasure","goal"]
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
	if data.get("format_version") != 1 or not Pack.identifier(data.get("id")): errors.append("Invalid template library version or ID")
	if not data.get("enemy_types") is Dictionary or not data.get("templates") is Array: errors.append("Template library needs enemy_types and templates");return errors
	if data.templates.is_empty() or data.templates.size()>128: errors.append("Template library needs 1..128 templates");return errors
	var ids: Dictionary = {}
	var roles: Dictionary = {}
	for entry in data.templates:
		if not entry is Dictionary: errors.append("Template must be an object");continue
		Pack.unknown_fields(entry,["id","role","weight","ports","requires","room"],"Template",errors)
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
		if entry.room.get("stairs",[]) != []: errors.append(entry.id+": linked stairs need a multi-room template; single-room capture is unsupported")
		if entry.room.get("connections") != {}: errors.append(entry.id+": template connections must be empty")
		var pack := {"schema":2,"id":"template_check","title":"Template","start_room":entry.room.get("id",""),"enemy_types":data.enemy_types,"rooms":[entry.room],"starting_items":[],"goals":[]}
		for error in Pack.validate(pack): errors.append(entry.id+": "+error)
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
		var keys: Array = value.keys();keys.sort()
		var parts: PackedStringArray = []
		for key in keys: parts.append(JSON.stringify(key)+":"+canonical(value[key]))
		return "{"+",".join(parts)+"}"
	if value is Array:
		var parts: PackedStringArray = []
		for entry in value: parts.append(canonical(entry))
		return "["+",".join(parts)+"]"
	if value is float and value == floor(value): return JSON.stringify(int(value))
	return JSON.stringify(value)
static func fingerprint(data: Dictionary) -> String: return canonical(data).sha256_text()
static func capture(catalog: Dictionary, pack: Dictionary, room_id: String, id: String, role: String, ports: Array, requirements: Array) -> Dictionary:
	var source_errors := Pack.validate(pack)
	if not source_errors.is_empty(): return {"errors":source_errors}
	var output := catalog.duplicate(true)
	if output.templates.any(func(t): return t.id == id): return {"errors":PackedStringArray(["Template ID already exists; choose a new ID"])}
	var matches: Array = pack.rooms.filter(func(r): return r.id == room_id)
	if matches.is_empty(): return {"errors":PackedStringArray(["Room is missing"])}
	if not matches[0].get("stairs",[]).is_empty(): return {"errors":PackedStringArray(["Linked stairs require multi-room templates; remove the links before capturing a single room."])}
	var room: Dictionary = matches[0].duplicate(true)
	room.connections = {}
	room.erase("template_id");room.erase("role")
	room.map_position = [0,0]
	for enemy in room.enemies:
		var original: String = enemy.type
		var scoped := id.left(20)+"_"+original.left(20)+"_"+(id+"/"+original).sha256_text().left(8)
		if output.enemy_types.has(scoped) and output.enemy_types[scoped] != pack.enemy_types[original]: return {"errors":PackedStringArray(["Scoped enemy definition collision"])}
		output.enemy_types[scoped] = pack.enemy_types[original].duplicate(true)
		enemy.type = scoped
	output.templates.append({"id":id,"role":role,"weight":1,"ports":ports.duplicate(),"requires":requirements.duplicate(),"room":room})
	return {"catalog":output,"errors":validate(output)}
