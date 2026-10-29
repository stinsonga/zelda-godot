extends "res://tests/resident_routes.gd"
const Secrets = preload("res://editor/tests/destructible_fixture.gd")
func run() -> void:
	for trigger in ["bomb","fire"]:
		for direction in Pack.EDGES:
			var pack := Secrets.sample(trigger,direction)
			var proof := Solver.new().solve(pack)
			check(proof.status == "solved","Secret trial has witness")
			if proof.status == "solved": replay(pack,proof)
		var doorway := Secrets.doorway_revisit(trigger)
		replay(doorway,Solver.new().solve(doorway))
		var returning := Secrets.revisit(trigger)
		var proof := Solver.new().solve(returning)
		check(proof.status == "solved","Persistent return trial has witness")
		if proof.status == "solved": replay(returning,proof)
	for pack in [Secrets.gifted_candle(),Secrets.purchased_bombs()]: replay(pack,Solver.new().solve(pack))
	var generated := Generator.new().generate(Secrets.catalog(),42,6)
	check(generated.errors.is_empty(),"Destructible template library generates")
	if generated.has("pack"): replay(generated.pack,generated.proof)
	# Hidden stairs become usable only after the actual bomb detonation.
	var pack := Secrets.sample()
	var cellar := Pack.cellar("cellar");cellar.map_position = [1,0]
	cellar.stairs = [{"id":"return","cell":[3,3],"target":"entry","target_position":[120,125]}]
	cellar.pickups = [{"id":"goal","item":"heart","position":[120,125]}]
	pack.rooms[0].pickups = []
	pack.rooms[0].stairs = [{"id":"hidden","cell":[6,5],"target":"cellar","target_position":[48,61],"requires_secret":true}]
	pack.rooms.append(cellar);pack.goals = [{"room":"cellar","pickup":"goal"}]
	replay(pack,Solver.new().solve(pack))
	var compiled := Adapter.compile(Secrets.sample("fire"))
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false;prepare_room()
	var proof := Solver.new().solve(Secrets.sample("fire"))
	for event in proof.events:
		if event.type == "reveal": replay_reveal_event(event)
	check(not world.use_item(),"Blue candle remains once-per-room after revealing")
	var room: Resource = world.room
	world.enter_room(room,room.spawn,Vector2i.DOWN)
	check(world.secrets.revealed and not world.is_blocked(Vector2i(104,88)),"Fire reveal remains open after re-entry")
	world.combat.encounter_room = null;world.free()
	print("Destructible secret native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
