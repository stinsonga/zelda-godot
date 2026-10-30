extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Cellars = preload("template_fixture.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Graph generation checks timed out");quit(1))
	call_deferred("run")
func original_tree(pack: Dictionary) -> Dictionary:
	var tree: Dictionary = {}
	for i in int(pack.generation.room_count): tree[pack.rooms[i].id] = pack.rooms[i].connections.duplicate(true)
	for edge in pack.generation.loop_edges:
		tree[edge.room].erase(edge.edge);tree[edge.target].erase(Pack.OPPOSITE[edge.edge])
	return tree
func side_of_cut(tree: Dictionary, start: String, end: String) -> Dictionary:
	var pending: Array = [start];var found: Dictionary = {start:true};var cursor := 0
	while cursor<pending.size():
		var id: String = pending[cursor];cursor+=1
		for link in tree[id].values():
			if (id==start and link.target==end) or (id==end and link.target==start): continue
			if not found.has(link.target): found[link.target] = true;pending.append(link.target)
	return found
func verify_graph(pack: Dictionary, branches: int, loops: int) -> void:
	check(Pack.validate(pack).is_empty(),"Generated graph validates")
	var count: int = pack.generation.room_count
	var links := 0;var lookup: Dictionary = {}
	for i in count: links+=pack.rooms[i].connections.size();lookup[pack.rooms[i].id] = pack.rooms[i]
	check(links/2-count+1==loops and pack.generation.loop_edges.size()==loops,"Connected graph has exactly the requested independent cycles")
	check(pack.goals.size()==branches+1,"Branch treasures remain objectives")
	var tree := original_tree(pack)
	for i in range(1,count-branches): check(tree[pack.rooms[i].id].values().any(func(link): return link.target==pack.rooms[i-1].id),"Main path retains ordered progression")
	for i in range(count-branches,count): check(pack.rooms[i].role=="treasure","Configured branch rooms have branch roles")
	for source in tree:
		for link in tree[source].values():
			if source>link.target: continue
			if link.kind=="open" and link.get("requires",[]).is_empty(): continue
			var side := side_of_cut(tree,source,link.target)
			for extra in pack.generation.loop_edges:
				if side.has(extra.room)==side.has(extra.target): continue
				var shortcut: Dictionary = lookup[extra.room].connections[extra.edge]
				if link.kind in ["key","bombable"]: check(shortcut.kind==link.kind,"Every added crossing retains the cut's consumable lock")
				for item in link.get("requires",[]): check(item in shortcut.requires,"Every added crossing retains the cut's item gate")
func run() -> void:
	var catalog := Templates.defaults();var before := Templates.canonical(catalog)
	var first: Dictionary = {}
	for recipe in [[42,8,2,1],[7,10,2,2],[91,12,3,2],[42,6,0,1],[42,8,0,1],[42,10,4,1],[42,8,0,0]]:
		var generated := Generator.new().generate(catalog,recipe[0],recipe[1],"blue_candle",6000,{"branch_rooms":recipe[2],"loop_count":recipe[3]})
		check(generated.errors.is_empty(),"Custom recipe solves: "+str(recipe)+" "+str(generated.errors))
		if not generated.has("pack"): continue
		verify_graph(generated.pack,recipe[2],recipe[3])
		if first.is_empty(): first = generated.pack
	check(Templates.canonical(catalog)==before,"Generation leaves template library unchanged")
	var shipped := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/looped_dungeon.json"))
	check(shipped.errors.is_empty() and Templates.canonical(shipped.pack)==Templates.canonical(first),"GUI-saved example reproduces the documented recipe")
	var repeated := Generator.new().generate(JSON.parse_string(JSON.stringify(catalog)),42,8,"blue_candle",6000,{"loop_count":1})
	check(repeated.has("pack") and Templates.canonical(repeated.pack)==Templates.canonical(first),"Seed, normalized settings and JSON library reproduce identical graph")
	var legacy := Generator.new().generate(catalog,42,8)
	check(legacy.has("pack") and legacy.pack.generation.algorithm=="authored_tree" and legacy.pack.id!=first.id,"Opt-in graph recipes have distinct identities")
	for layout in [{"branch_rooms":3},{"branch_rooms":-1},{"branch_rooms":1.5},{"loop_count":9},{"loop_count":-1},{"typo":1}]:
		check(not Generator.new().generate(catalog,42,8,"blue_candle",6000,layout).errors.is_empty(),"Invalid layout rejected: "+str(layout))
	var impossible := Generator.new().generate(catalog,42,6,"blue_candle",6000,{"branch_rooms":0,"loop_count":8})
	check(not impossible.has("pack") and not impossible.errors.is_empty(),"Impossible exact loop request never silently degrades")
	check(Generator.new().generate(catalog,42,8,"blue_candle",0,{"loop_count":1}).get("proof",{}).get("status")=="limit","Time limits remain inconclusive")
	var malformed: Dictionary = first.duplicate(true);malformed.generation.loop_edges = []
	check(not Pack.validate(malformed).is_empty(),"Malformed graph provenance rejected")
	var edited: Dictionary = first.duplicate(true);var extra: Dictionary = edited.generation.loop_edges[0]
	for room in edited.rooms:
		if room.id==extra.room: room.connections.erase(extra.edge)
		if room.id==extra.target: room.connections.erase(Pack.OPPOSITE[extra.edge])
	check(Pack.validate(edited).is_empty(),"Historical recipe does not prevent ordinary manual edge edits")
	var port_limited: Dictionary = first.duplicate(true);var restricted: Array = []
	var tree := original_tree(port_limited)
	for room in port_limited.rooms:
		room.connections = tree[room.id].duplicate(true);restricted.append({"ports":room.connections.keys()})
	port_limited.generation.loop_edges = []
	var snapshot := Templates.canonical(port_limited)
	check(not Generator.new().add_loops(port_limited,restricted,8,1).is_empty() and Templates.canonical(port_limited)==snapshot,"Unsupported template ports reject loops without partial edits")
	var two_locks := {"a":{"right":{"target":"b","kind":"key"}},"b":{"left":{"target":"a","kind":"key"},"right":{"target":"c","kind":"key"}},"c":{"left":{"target":"b","kind":"key"}}}
	check(Generator.new().loop_gate(two_locks,"a","c").is_empty(),"Shortcut cannot collapse two key costs into one")
	var cellar := Generator.new().generate(Cellars.catalog(),42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":1})
	check(cellar.errors.is_empty(),"Graph layout supports stair-linked template units")
	if cellar.has("pack"):
		verify_graph(cellar.pack,2,1)
		check(cellar.pack.rooms.size()>8,"Cellar annexes remain additional rooms")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui);ui.open_dungeon_tools(0)
	var dialog = ui.dungeon_tools
	check(not dialog.custom_layout.button_pressed and not dialog.branch_rooms.editable,"Classic recipe is the GUI default")
	dialog.custom_layout.button_pressed = true;dialog.loop_count.value = 1;dialog.start_generation()
	check(dialog.custom_layout.disabled and not dialog.loop_count.editable,"Layout controls lock during worker generation")
	while dialog.busy: await process_frame
	check(not dialog.candidate.is_empty() and dialog.candidate.generation.algorithm=="authored_graph" and dialog.candidate.generation.loop_count==1,"Threaded GUI generates custom graph")
	dialog.use_candidate()
	check(ui.dirty() and ui.pack.generation.algorithm=="authored_graph","Loading generated work marks the new document unsaved")
	check(ui.save_to("/tmp/zelda-graph-saved-pack.json") and not ui.dirty(),"Saving generated work clears its unsaved state")
	dialog.branch_rooms.value = 0
	check(dialog.candidate.is_empty() and dialog.use_button.disabled,"Changing branches invalidates previous candidate")
	dialog.count.value = 6
	check(dialog.branch_rooms.max_value==0,"GUI reserves six main-path rooms")
	dialog.custom_layout.button_pressed = false
	check(not dialog.loop_count.editable,"Classic mode disables custom controls")
	ui.free()
	Pack.write("/tmp/zelda-graph-generation-fixture.json",first)
	print("Graph generation checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
