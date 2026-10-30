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
func generate(catalog: Dictionary, seed_value: int, room_count: int = 8, required_item: String = "blue_candle", verification_ms: int = 6000, layout: Dictionary = {}) -> Dictionary:
	var errors := Templates.validate(catalog)
	if not errors.is_empty(): return {"errors":errors}
	if verification_ms<0 or verification_ms>60000: return {"errors":PackedStringArray(["Verification budget must be 0..60000 ms"])}
	if seed_value<0 or seed_value>2147483647 or room_count<6 or room_count>16 or required_item not in Pack.REQUIRED_ITEMS: return {"errors":PackedStringArray(["Seed must be 0..2147483647, rooms 6..16, required item supported"])}
	var layout_errors := PackedStringArray()
	Pack.unknown_fields(layout,["branch_rooms","loop_count"],"Layout",layout_errors)
	if not layout.is_empty():
		if not Pack.integer(layout.get("branch_rooms",room_count/4 if room_count>=8 else 0),0,room_count-6): layout_errors.append("Branch rooms must leave at least six primary rooms on the main path")
		if not Pack.integer(layout.get("loop_count",0),0,8): layout_errors.append("Loop count must be 0..8")
	if not layout_errors.is_empty(): return {"errors":layout_errors}
	rng_state = seed_value
	var last_report: Dictionary = {}
	var build_errors := PackedStringArray()
	for attempt in range(12):
		var candidate := build(catalog,seed_value,room_count,required_item,layout)
		if not candidate.has("pack"):
			build_errors = candidate.get("errors",PackedStringArray())
			continue
		var proof := Solver.new().solve(candidate.pack,16000,verification_ms)
		if proof.status == "solved": return {"errors":PackedStringArray(),"pack":candidate.pack,"proof":proof,"attempts":attempt+1}
		if proof.status == "limit" and proof.get("limit_kind") == "time":
			return {"errors":PackedStringArray(["Verification exceeded its time budget. No alternate candidate was published, preserving seed determinism. Reduce complexity or retry verification."]),"proof":proof}
		last_report = proof
	return {"errors":PackedStringArray(["No verified dungeon found in 12 attempts. Templates may block entrances, rewards or required items."])+build_errors,"proof":last_report}
func build(catalog: Dictionary, seed_value: int, count: int, required_item: String, layout: Dictionary = {}) -> Dictionary:
	var branch_count := int(layout.get("branch_rooms",count/4 if count>=8 else 0))
	var loop_count := int(layout.get("loop_count",0))
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
	# Resident solvability changes candidate acceptance. Give those libraries
	# a new recipe and world identity, preserving existing v1/v2 seed results.
	var resident_library: bool = catalog.templates.any(func(t): return t.room.has("resident") or t.get("annexes",[]).any(func(room): return room.has("resident")))
	var persistent_library: bool = catalog.templates.any(func(t): return ([t.room]+t.get("annexes",[])).any(func(room): return room.has("secret") and Pack.secret_trigger(room.secret) != "block"))
	var algorithm_version := 4 if persistent_library else 3 if resident_library else int(catalog.format_version)
	if not layout.is_empty(): algorithm_version = 5
	var pack := Pack.fresh()
	Pack.upgrade(pack)
	pack.id = ("generated_v"+str(algorithm_version)+"_" if algorithm_version>=3 else "generated_")+"%d_%d_%s_%s" % [seed_value,count,required_item,Templates.fingerprint(catalog).left(8)]
	if algorithm_version==5: pack.id = "generated_v5_%d_%d_%s_b%d_l%d_%s" % [seed_value,count,required_item,branch_count,loop_count,Templates.fingerprint(catalog).left(8)]
	pack.title = "Seed %d dungeon" % seed_value
	pack.start_room = "room_0"
	pack.enemy_types = catalog.enemy_types.duplicate(true)
	pack.rooms = []
	pack.generation = {"algorithm":"authored_tree","version":algorithm_version,"seed":seed_value,"template_sha256":Templates.fingerprint(catalog),"room_count":count,"required_item":required_item,"templates":{}}
	if algorithm_version==5:
		pack.generation.algorithm = "authored_graph"
		pack.generation.branch_rooms = branch_count;pack.generation.loop_count = loop_count;pack.generation.loop_edges = []
	var units: Array = []
	for i in range(count):
		var template: Dictionary = chosen[i]
		var unit := Templates.instantiate(template,"room_"+str(i))
		units.append(unit)
		if unit.has("appearance"):
			if not pack.has("appearance"): pack.appearance = Templates.Bindings.fresh()
			for field in ["enemy_sprites","room_tiles","room_sprites"]:
				pack.appearance[field].merge(unit.appearance[field],true)
		var room: Dictionary = unit.primary
		room.title = String(template.room.title)+" "+str(i+1)
		room.connections = {}
		room.map_position = [positions[i].x,positions[i].y]
		room.role = roles[i];room.template_id = template.id
		pack.generation.templates[room.id] = template.id
		pack.rooms.append(room)
	# Keep the first `count` slots as the critical-path/branch rooms. Annexes
	# are placed afterward, without consuming PRNG values or colliding on the map.
	for i in range(count):
		for annex in units[i].annexes:
			if pack.rooms.size()>=32: return {"errors":PackedStringArray(["Template expansion exceeds the 32-room progression limit; reduce primary rooms or cellar annexes"])}
			annex.map_position = annex_position(pack.rooms,positions[i])
			annex.title = String(annex.title)+" "+str(i+1)
			annex.template_id = chosen[i].id
			pack.rooms.append(annex)
			pack.generation.templates[annex.id] = chosen[i].id
	for i in range(1,count):
		var source: Dictionary = pack.rooms[parents[i]]
		var target: Dictionary = pack.rooms[i]
		var kind := "key" if i == 2 or i == main_count-1 else "bombable" if i>=main_count and random_int(2) == 0 else "open"
		var requirements: Array = chosen[i].requires.duplicate()
		if i == 4 and required_item not in requirements: requirements.append(required_item)
		source.connections[edges[i]] = {"target":target.id,"kind":kind,"requires":requirements.duplicate()}
		target.connections[Pack.OPPOSITE[edges[i]]] = {"target":source.id,"kind":kind,"requires":requirements.duplicate()}
	add_pickup(units[1].reward_room,"key","progress_key",false,units[1].reward_position)
	if branch_count>0: add_pickup(units[1].reward_room,"bombs","branch_bombs",false,units[1].reward_position)
	add_pickup(units[3].reward_room,required_item,"required_item",false,units[3].reward_position)
	add_pickup(units[4].reward_room,"key","final_key",false,units[4].reward_position)
	var goal := add_pickup(units[main_count-1].reward_room,"rupee","goal_reward",true,units[main_count-1].reward_position)
	pack.goals.append({"room":units[main_count-1].reward_room.id,"pickup":goal})
	for i in range(main_count,count):
		var pickup := add_pickup(units[i].reward_room,"rupee","branch_reward",false,units[i].reward_position)
		pack.goals.append({"room":units[i].reward_room.id,"pickup":pickup})
	if algorithm_version==5:
		var errors := add_loops(pack,chosen,count,loop_count)
		if not errors.is_empty(): return {"errors":errors}
	return {"pack":pack}
func add_pickup(room: Dictionary, item: String, prefix: String, requires_clear: bool = false, position: Array = [120,77]) -> String:
	var id := prefix
	var n := 1
	while room.pickups.any(func(p): return p.id == id): id = prefix+"_"+str(n);n += 1
	# A template may block this point; the progression solver must reject it.
	var pickup := {"id":id,"item":item,"position":position.duplicate(),"requires_clear":requires_clear}
	if room.has("secret") and room.secret.reveal == "item": pickup.requires_secret = true
	room.pickups.append(pickup)
	return id

func annex_position(rooms: Array, primary: Vector2i) -> Array:
	var used: Dictionary = {}
	for room in rooms: used[Vector2i(int(room.map_position[0]),int(room.map_position[1]))] = true
	var best := Vector2i(-1,1)
	var distance := 1000
	for y in range(-15,1):
		for x in range(16):
			var at := Vector2i(x,y)
			var delta := absi(x-primary.x)+absi(y-primary.y)
			if not used.has(at) and delta<distance: best = at;distance = delta
	return [best.x,best.y]

## Each new edge inherits all permanent-item gates on its ORIGINAL tree path.
## A single consumable lock can be mirrored on an alternative route; two such
## cuts would need a door that spends multiple resources, so those pairs fail.
func loop_gate(tree: Dictionary, source: String, target: String) -> Dictionary:
	var pending: Array = [source]
	var previous: Dictionary = {source:{}}
	var cursor := 0
	while cursor<pending.size() and not previous.has(target):
		var id: String = pending[cursor];cursor+=1
		for link in tree[id].values():
			if not previous.has(link.target): previous[link.target] = {"source":id,"link":link};pending.append(link.target)
	if not previous.has(target): return {}
	var requirements: Array = [];var locks: Array = []
	var at := target
	while at!=source:
		var step: Dictionary = previous[at];var link: Dictionary = step.link
		for item in link.get("requires",[]):
			if item not in requirements: requirements.append(item)
		if link.kind in ["key","bombable"]: locks.append(link.kind)
		elif link.kind!="open": return {}
		at = step.source
	if locks.size()>1: return {}
	requirements.sort()
	return {"kind":locks[0] if not locks.is_empty() else "open","requires":requirements}
func add_loops(pack: Dictionary, chosen: Array, count: int, requested: int) -> PackedStringArray:
	if requested==0: return PackedStringArray()
	var tree: Dictionary = {}
	for i in count: tree[pack.rooms[i].id] = pack.rooms[i].connections.duplicate(true)
	var options: Array = []
	for i in count:
		for j in range(i+1,count):
			var a: Dictionary = pack.rooms[i];var b: Dictionary = pack.rooms[j]
			var delta := Vector2i(int(b.map_position[0])-int(a.map_position[0]),int(b.map_position[1])-int(a.map_position[1]))
			for edge in Pack.EDGES:
				if delta!=DIRS[edge] or a.connections.has(edge) or b.connections.has(Pack.OPPOSITE[edge]): continue
				if edge not in chosen[i].ports or Pack.OPPOSITE[edge] not in chosen[j].ports: continue
				var gate := loop_gate(tree,a.id,b.id)
				if not gate.is_empty(): options.append({"source":i,"target":j,"edge":edge,"gate":gate})
	if options.size()<requested: return PackedStringArray(["Cannot fit exactly %d gate-preserving loops in this layout/template selection; try fewer loops, more rooms or another seed." % requested])
	for i in requested:
		var index := random_int(options.size());var option: Dictionary = options[index];options.remove_at(index)
		var a: Dictionary = pack.rooms[option.source];var b: Dictionary = pack.rooms[option.target]
		a.connections[option.edge] = {"target":b.id,"kind":option.gate.kind,"requires":option.gate.requires.duplicate()}
		b.connections[Pack.OPPOSITE[option.edge]] = {"target":a.id,"kind":option.gate.kind,"requires":option.gate.requires.duplicate()}
		pack.generation.loop_edges.append({"room":a.id,"edge":option.edge,"target":b.id})
	return PackedStringArray()
