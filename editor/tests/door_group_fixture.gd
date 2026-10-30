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
