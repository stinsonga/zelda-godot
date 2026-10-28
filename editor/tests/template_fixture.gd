extends RefCounted
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Stairs = preload("stairs_fixture.gd")
static func source() -> Dictionary:
	var pack := Stairs.sample()
	pack.rooms[1].pickups = []
	pack.rooms[1].enemies = [{"id":"guard","type":"crawler","position":[176,125]}]
	pack.enemy_types.crawler.health = 3
	return pack
static func catalog() -> Dictionary:
	var output := Templates.defaults()
	for role in ["key","goal"]:
		var captured := Templates.capture(output,source(),"entry",role+"_cellar",role,Pack.EDGES,[],true,"cellar",[120,125])
		if not captured.errors.is_empty(): return {"capture_errors":captured.errors}
		output = captured.catalog
	output.id = "cellar_templates"
	output.templates = output.templates.filter(func(entry): return entry.role not in ["key","goal"] or entry.id.ends_with("_cellar"))
	return output

static func nested_catalog() -> Dictionary:
	var pack := source()
	var deep := Pack.cellar("deep");deep.map_position = [2,0]
	deep.stairs = [{"id":"up","cell":[3,3],"target":"cellar","target_position":[120,125]}]
	pack.rooms[1].stairs.append({"id":"deeper","cell":[12,3],"target":"deep","target_position":[48,61]})
	pack.rooms.append(deep)
	var captured := Templates.capture(catalog(),pack,"entry","nested_key","key",Pack.EDGES,[],true,"deep",[120,125])
	if not captured.errors.is_empty(): return {"capture_errors":captured.errors}
	captured.catalog.templates = captured.catalog.templates.filter(func(entry): return entry.role != "key" or entry.id == "nested_key")
	return captured.catalog
