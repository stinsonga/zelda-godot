extends "res://tests/generated_dungeons.gd"
const Cellars = preload("res://editor/tests/template_fixture.gd")
func run() -> void:
	for recipe in [[42,8,2,1],[7,10,2,2]]:
		var generated := Generator.new().generate(Templates.defaults(),recipe[0],recipe[1],"blue_candle",6000,{"branch_rooms":recipe[2],"loop_count":recipe[3]})
		check(generated.errors.is_empty(),"Graph recipe generates for native replay")
		if generated.has("pack"): replay(generated.pack,generated.proof)
	var cellar := Generator.new().generate(Cellars.catalog(),42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":1})
	check(cellar.errors.is_empty(),"Graph with cellar rewards generates")
	if cellar.has("pack"): replay(cellar.pack,cellar.proof)
	var generated := Generator.new().generate(Templates.defaults(),42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":1})
	if generated.has("pack"): verify_shortcut(generated.pack)
	print("Generated graph native checks: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
func verify_shortcut(pack: Dictionary) -> void:
	var record: Dictionary = pack.generation.loop_edges[0]
	var room: Dictionary
	for source in pack.rooms:
		if source.id==record.room: room = source;break
	check(room.connections[record.edge].kind=="key" and "blue_candle" in room.connections[record.edge].requires,"Example shortcut mirrors final lock and item gate")
	var compiled := Adapter.compile(pack)
	compiled.world.start_room = StringName(record.room)
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	prepare_room()
	world.state.take_item(load("res://content/items/key.tres"));world.player.place(HOT[record.edge])
	world.try_doors(DIRS[record.edge])
	check(world.state.item_value(&"keys")==1,"Shortcut cannot spend a key before required item is owned")
	world.state.take_item(load("res://content/items/blue_candle.tres"))
	world.try_doors(DIRS[record.edge])
	check(world.state.item_value(&"keys")==0,"Satisfied shortcut spends its own actual key")
	for i in range(24): tick()
	check(walk_to(func(at): return at==EDGE[record.edge]),"Native movement reaches opened shortcut")
	for i in range(100):
		tick(DIRS[record.edge])
		if String(world.room.id)==record.target and world.entry_walk_remaining==0 and world.settle_ticks==0: break
	check(String(world.room.id)==record.target,"Added loop really transitions through its authored doorway")
	for actor in world.combat.enemies: actor.source.tile_probe = Callable()
	world.combat.enemies.clear();world.combat.encounter_room = null;world.free()
