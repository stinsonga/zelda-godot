extends RefCounted
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const DIRS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
static func source(edge: String = "right", locked: bool = false) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack)
	var primary: Dictionary = pack.rooms[0];primary.map_position = [7,-7]
	var side := Pack.room("side","Side chamber")
	var at: Vector2i = Vector2i(7,-7)+DIRS[edge];side.map_position = [at.x,at.y]
	primary.connections[edge] = {"target":"side","kind":"key" if locked else "open"}
	side.connections[Pack.OPPOSITE[edge]] = {"target":"entry","kind":"key" if locked else "open"}
	if locked: primary.pickups.append({"id":"internal_key","item":"key","position":[80,125]})
	side.enemies = [{"id":"guard","type":"crawler","position":[176,77]}]
	pack.rooms.append(side)
	return pack
static func catalog() -> Dictionary:
	var catalog := Templates.defaults()
	for role in ["key","goal"]:
		for edge in Pack.EDGES:
			var ports: Array = Pack.EDGES.duplicate();ports.erase(edge)
			var result := Templates.capture(catalog,source(edge,role=="goal"),"entry",role+"_suite_"+edge,role,ports,[],false,"side",[120,77],["side"])
			if not result.errors.is_empty(): return {"errors":result.errors}
			catalog = result.catalog
	catalog.id = "door_templates"
	catalog.templates = catalog.templates.filter(func(t): return t.role not in ["key","goal"] or t.id.contains("_suite_"))
	return catalog

static func mixed_catalog() -> Dictionary:
	var pack := source()
	var cellar := Pack.cellar("cellar");cellar.map_position = [9,-7]
	pack.rooms[1].stairs = [{"id":"down","cell":[7,4],"target":"cellar","target_position":[48,61]}]
	cellar.stairs = [{"id":"back","cell":[3,3],"target":"side","target_position":[120,125]}]
	pack.rooms.append(cellar)
	var result := Templates.capture(catalog(),pack,"entry","mixed_key","key",["up","down","left"],[],true,"cellar",[120,125],["side"])
	if not result.errors.is_empty(): return {"errors":result.errors}
	result.catalog.templates = result.catalog.templates.filter(func(t): return t.role!="key" or t.id=="mixed_key")
	return result.catalog

## Only the upward suites, mirrored to cover the other three directions.
static func mirrored_catalog() -> Dictionary:
	var catalog := catalog()
	if catalog.has("errors"): return catalog
	catalog.id = "mirrored_door_templates"
	catalog.templates = catalog.templates.filter(func(t): return not t.id.contains("_suite_") or t.id.ends_with("_up"))
	for entry in catalog.templates:
		if entry.id.ends_with("_up"): entry.mirrors = ["vertical"]
	# A right-facing suite mirrored horizontally covers left.
	var right := catalog()
	for entry in right.templates:
		if entry.id.contains("_suite_right"): entry.mirrors = ["horizontal"];catalog.templates.append(entry)
	return catalog

## Door suites whose companion rooms also offer every outward edge as a port.
static func companion_catalog() -> Dictionary:
	var catalog := catalog()
	if catalog.has("errors"): return catalog
	catalog.id = "companion_door_templates"
	for entry in catalog.templates:
		if not entry.id.contains("_suite_"): continue
		var side: Dictionary = entry.annexes[0]
		var inward: Array = side.connections.keys()
		entry.companion_ports = {side.id:Pack.EDGES.filter(func(edge): return edge not in inward)}
	return catalog

## The classic single-room library, plus the companion suites, with a stair
## cell on every template so generation can change floors anywhere.
static func floor_catalog(rooms: String = "single") -> Dictionary:
	var catalog := Templates.defaults() if rooms == "single" else companion_catalog()
	if catalog.has("errors"): return catalog
	catalog.format_version = 3;catalog.id = "floor_templates"
	for entry in catalog.templates: entry.stair_cell = [7,4]
	return catalog
