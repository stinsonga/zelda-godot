extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/block_fixture.gd")
func run() -> void:
	for direction in Pack.EDGES:
		for reveal in ["shutters","item"]:
			var pack := Fixture.sample(direction,reveal)
			var proof := Solver.new().solve(pack)
			check(proof.status == "solved","Fixture has a supported progression proof")
			if proof.status == "solved": replay(pack,proof)
	var revisit := Fixture.revisit()
	replay(revisit,Solver.new().solve(revisit))
	var catalog := Templates.defaults()
	for template in catalog.templates:
		if template.role == "key": template.room.secret = {"cell":[6,5],"direction":"left","reveal":"item"}
	var generated := Generator.new().generate(catalog,42,8)
	check(generated.errors.is_empty(),"Puzzle templates generate a verified dungeon")
	if generated.has("pack"): replay(generated.pack,generated.proof)
	# Reset behavior, wrong-side rejection and the combat prerequisite in a real room.
	var pack := Fixture.sample()
	pack.rooms[0].enemies = [{"id":"guard","type":"crawler","position":[176,61]}]
	var compiled := Adapter.compile(pack)
	check(compiled.errors.is_empty(),"Combat block fixture compiles")
	world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	for i in range(65): tick()
	world.player.place(Vector2i(80,77))
	for i in range(60): tick(Vector2i.RIGHT)
	check(not world.secrets.pushed and not world.shutters_open(),"Living monster prevents block push and keeps shutters closed")
	prepare_room()
	world.player.place(Vector2i(96,93))
	for i in range(20): tick(Vector2i.UP)
	check(not world.secrets.pushed,"Authored block rejects an otherwise valid push from the wrong side")
	world.player.place(Vector2i(80,77))
	for i in range(16): tick(Vector2i.RIGHT)
	for i in range(40): tick()
	check(world.secrets.revealed and world.shutters_open(),"Cleared room's chosen push opens shutters")
	check(not world.state.flags.get("secret/entry",false),"Authored block reveal is not persisted to save flags")
	var entry: Resource = world.room
	world.enter_room(world.rooms[&"hall"],Vector2i(120,125),Vector2i.UP)
	world.enter_room(entry,entry.spawn,Vector2i.UP)
	check(not world.secrets.pushed and not world.secrets.revealed and not world.shutters_open(),"Room re-entry resets block and shutters")
	check(world.is_blocked(Vector2i(96,80)) and not world.is_blocked(Vector2i(112,80)),"Re-entry restores original block collision")
	world.combat.encounter_room = null;world.free()
	print("Authored block native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
