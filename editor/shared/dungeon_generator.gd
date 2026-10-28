extends RefCounted
const Pack = preload("room_pack.gd")
const Templates = preload("dungeon_templates.gd")
const Solver = preload("progression_solver.gd")
const DIRS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
var rng_state := 0
func random_int(limit: int) -> int:
	rng_state = (1664525*rng_state+1013904223)&0xffffffff
	return (rng_state >> 8)%limit
func shuffled_edges() -> Array:
	var edges: Array = Pack.EDGES.duplicate()
	for i in range(edges.size()-1,0,-1):
		var j := random_int(i+1)
		var old = edges[i];edges[i] = edges[j];edges[j] = old
	return edges
func generate(catalog: Dictionary, seed_value: int, room_count: int = 8, required_item: String = "blue_candle", verification_ms: int = 6000) -> Dictionary:
	var errors := Templates.validate(catalog)
	if not errors.is_empty(): return {"errors":errors}
	if verification_ms<0 or verification_ms>60000: return {"errors":PackedStringArray(["Verification budget must be 0..60000 ms"])}
	if seed_value<0 or seed_value>2147483647 or room_count<6 or room_count>16 or required_item not in Pack.REQUIRED_ITEMS: return {"errors":PackedStringArray(["Seed must be 0..2147483647, rooms 6..16, required item supported"])}
	rng_state = seed_value
	var last_report: Dictionary = {}
	for attempt in range(12):
		var candidate := build(catalog,seed_value,room_count,required_item)
		if not candidate.has("pack"): continue
		var proof := Solver.new().solve(candidate.pack,16000,verification_ms)
		if proof.status == "solved": return {"errors":PackedStringArray(),"pack":candidate.pack,"proof":proof,"attempts":attempt+1}
		if proof.status == "limit" and proof.get("limit_kind") == "time":
			return {"errors":PackedStringArray(["Verification exceeded its time budget. No alternate candidate was published, preserving seed determinism. Reduce complexity or retry verification."]),"proof":proof}
		last_report = proof
	return {"errors":PackedStringArray(["No verified dungeon found in 12 attempts. Templates may block entrances, rewards or required items."]),"proof":last_report}
func build(catalog: Dictionary, seed_value: int, count: int, required_item: String) -> Dictionary:
	var branch_count := count/4 if count>=8 else 0
	var main_count := count-branch_count
	var positions: Array[Vector2i] = [Vector2i(8,-7)]
	var parents: Array[int] = [-1]
	var edges: Array[String] = [""]
	for i in range(1,count):
		var options: Array = []
		var sources: Array = [i-1] if i<main_count else range(i)
		for source in sources:
			for edge in shuffled_edges():
				var at: Vector2i = positions[source]+DIRS[edge]
				if at.x>=0 and at.x<16 and at.y>=-15 and at.y<=0 and at not in positions: options.append({"parent":source,"edge":edge,"at":at})
		if options.is_empty(): return {}
		var selected: Dictionary = options[random_int(options.size())]
		positions.append(selected.at);parents.append(selected.parent);edges.append(selected.edge)
	var roles: Array = []
	for i in range(count):
		roles.append("start" if i == 0 else "key" if i == 1 else "combat" if i == 2 else "item" if i == 3 else "goal" if i == main_count-1 else "treasure")
	var chosen: Array = []
	for i in range(count):
		var ports: Array = []
		if i>0: ports.append(Pack.OPPOSITE[edges[i]])
		for j in range(i+1,count):
			if parents[j] == i: ports.append(edges[j])
		var eligible: Array = catalog.templates.filter(func(t): return t.role == roles[i] and ports.all(func(port): return port in t.ports) and (i != 0 or t.requires.all(func(item): return item == "wooden_sword")))
		if eligible.is_empty(): return {}
		var total := 0
		for t in eligible: total += int(t.weight)
		var roll := random_int(total)
		for t in eligible:
			roll -= int(t.weight)
			if roll<0: chosen.append(t);break
	var pack := Pack.fresh()
	Pack.upgrade(pack)
	pack.id = "generated_%d_%d_%s_%s" % [seed_value,count,required_item,Templates.fingerprint(catalog).left(8)]
	pack.title = "Seed %d dungeon" % seed_value
	pack.start_room = "room_0"
	pack.enemy_types = catalog.enemy_types.duplicate(true)
	pack.rooms = []
	pack.generation = {"algorithm":"authored_tree","version":1,"seed":seed_value,"template_sha256":Templates.fingerprint(catalog),"room_count":count,"required_item":required_item,"templates":{}}
	for i in range(count):
		var template: Dictionary = chosen[i]
		var room: Dictionary = template.room.duplicate(true)
		room.id = "room_"+str(i)
		room.title = String(template.room.title)+" "+str(i+1)
		room.connections = {}
		room.map_position = [positions[i].x,positions[i].y]
		room.role = roles[i];room.template_id = template.id
		pack.generation.templates[room.id] = template.id
		pack.rooms.append(room)
	for i in range(1,count):
		var source: Dictionary = pack.rooms[parents[i]]
		var target: Dictionary = pack.rooms[i]
		var kind := "key" if i == 2 or i == main_count-1 else "bombable" if i>=main_count and random_int(2) == 0 else "open"
		var requirements: Array = chosen[i].requires.duplicate()
		if i == 4 and required_item not in requirements: requirements.append(required_item)
		source.connections[edges[i]] = {"target":target.id,"kind":kind,"requires":requirements.duplicate()}
		target.connections[Pack.OPPOSITE[edges[i]]] = {"target":source.id,"kind":kind,"requires":requirements.duplicate()}
	add_pickup(pack.rooms[1],"key","progress_key")
	if branch_count>0: add_pickup(pack.rooms[1],"bombs","branch_bombs")
	add_pickup(pack.rooms[3],required_item,"required_item")
	add_pickup(pack.rooms[4],"key","final_key")
	var goal := add_pickup(pack.rooms[main_count-1],"rupee","goal_reward",true)
	pack.goals.append({"room":pack.rooms[main_count-1].id,"pickup":goal})
	for i in range(main_count,count):
		var pickup := add_pickup(pack.rooms[i],"rupee","branch_reward")
		pack.goals.append({"room":pack.rooms[i].id,"pickup":pickup})
	return {"pack":pack}
func add_pickup(room: Dictionary, item: String, prefix: String, requires_clear: bool = false) -> String:
	var id := prefix
	var n := 1
	while room.pickups.any(func(p): return p.id == id): id = prefix+"_"+str(n);n += 1
	# A template may block this point; the progression solver must reject it.
	var pickup := {"id":id,"item":item,"position":[120,77],"requires_clear":requires_clear}
	if room.has("secret") and room.secret.reveal == "item": pickup.requires_secret = true
	room.pickups.append(pickup)
	return id
