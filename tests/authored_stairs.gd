extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/stairs_fixture.gd")
func run() -> void:
	for on_return in [false,true]:
		var pack := Fixture.sample(on_return)
		var proof := Solver.new().solve(pack)
		check(proof.status == "solved","Cellar fixture has progression witness")
		if proof.status == "solved": replay(pack,proof)
	var pack := Fixture.sample(true)
	var compiled := Adapter.compile(pack)
	check(compiled.errors.is_empty(),"Authored stairs compile to game resources")
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	prepare_room()
	world.player.place(Vector2i(96,77));tick()
	check(world.room.id == &"entry","Hidden stairs cannot be entered before revealing block secret")
	world.player.place(Vector2i(80,77))
	for i in range(16): tick(Vector2i.RIGHT)
	for i in range(40): tick()
	check(world.secrets.revealed,"Push reveals hidden stair")
	check(walk_to(func(p): return p == Vector2i(96,77),"cellar"),"Player reaches hidden stairs with real movement")
	check(world.room.id == &"cellar" and world.player.pixel_position() == Vector2i(48,45),"Stair uses exact authored arrival position")
	for i in range(20): tick()
	check(world.room.id == &"cellar" and not world.portal_armed,"Arrival on return stair does not immediately bounce back")
	check(walk_to(func(p): return p == Vector2i(48,61)),"Player can leave suppressed arrival square")
	check(world.portal_armed,"Leaving arrival square rearms portals")
	check(walk_to(func(p): return p == Vector2i(48,45),"entry"),"Return stair reaches parent room")
	check(world.room.id == &"entry" and not world.secrets.revealed,"Returning resets parent block secret")
	world.combat.encounter_room = null;world.free()
	# The runtime must agree that an unavoidable active stair prevents walking through.
	pack = Fixture.trap()
	compiled = Adapter.compile(pack)
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	prepare_room()
	check(walk_to(func(p): return p == Vector2i(96,77),"hall"),"Enter trap corridor through its stairs")
	prepare_room()
	check(not walk_to(func(p): return p == Vector2i(112,45)),"Native routing cannot pass through a forced stair")
	check(walk_to(func(p): return p == Vector2i(112,77),"pit") and world.room.id == &"pit","Stepping on forced stair sends player to pit")
	world.combat.encounter_room = null;world.free()
	print("Authored stair native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
