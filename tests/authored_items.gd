extends "res://tests/generated_dungeons.gd"
## The wider item list in the real game: a red candle opens a blue-candle gate
## along the solver's route, five rupees count five, and the map and compass
## light the authored status-bar map and point at the remaining objective.
const Fixture = preload("res://editor/tests/items_fixture.gd")
func run() -> void:
	var pack := Fixture.sample()
	var proof := Solver.new().solve(pack)
	check(proof.status == "solved","Item pack has a witness")
	if proof.status == "solved": replay(pack,proof)
	var compiled := Adapter.compile(pack)
	world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	prepare_room()
	var hall: int = world.rooms[&"hall"].map_room_id
	check(world.compass_room(world.room.dungeon_level) == hall,"The compass points at the objective's room")
	for pickup in world.room.pickups: world.state.collect(world.room.id,pickup)
	check(world.state.has_level_item(&"map",world.room.dungeon_level) and world.state.has_level_item(&"compass",world.room.dungeon_level),"The map and compass belong to the authored level")
	check(world.state.rupees_to_add == 5,"Five rupees add five")
	check(world.state.item_value(&"candle") == 2,"The red candle is the second candle grade")
	world.queue_redraw();await process_frame
	world.state.collected[world.state.pickup_key(&"hall",&"container")] = true
	check(world.compass_room(world.room.dungeon_level) == -1,"The compass has nothing to point at once objectives are taken")
	world.combat.encounter_room = null;world.free()
	print("Authored item checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
