extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/resident_fixture.gd")
func wait_text() -> void:
	for i in range(600):
		tick()
		if not world.cave_session.blocks_player() and world.cave_session.phase != "prices": return
	check(false,"Resident greeting finishes")
func enter(id: String) -> void:
	world.enter_room(world.rooms[StringName(id)],Vector2i(120,125),Vector2i.UP)
	wait_text()
func approach(until: Callable) -> void:
	world.player.place(Vector2i(120,109))
	for i in range(100):
		tick(Vector2i.UP)
		if until.call(): return
	check(false,"Resident ware interaction succeeds")
func run() -> void:
	var compiled := Adapter.compile(Fixture.sample())
	check(compiled.errors.is_empty(),"Authored residents compile")
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	enter("hint")
	check(world.cave_session.visible_text() == "THE PATH LOOPS BACK." and not world.cave_session.wares_visible(),"Hint displays authored text without wares")
	check(walk_to(func(p): return p == Vector2i(48,109),"entry"),"Resident cave return stairs work")
	enter("gift")
	check(world.state.item_value(&"bow") == 0,"Gift starts unclaimed")
	approach(func(): return world.state.item_value(&"bow") == 1)
	check(world.lift_remaining>0 and world.state.has_collected(&"gift",&"taken"),"Gift grants item with native lift and persistent taken flag")
	for i in range(200): tick()
	world.enter_room(world.rooms[&"entry"],Vector2i(120,125),Vector2i.UP)
	enter("gift")
	check(not world.cave_session.person_visible() and not world.cave_session.wares_visible(),"Taken gift stays gone on re-entry")
	enter("shop")
	world.state.rupees = 19
	world.player.place(Vector2i(120,93))
	for i in range(30): tick()
	check(world.state.item_value(&"keys") == 0 and world.state.rupees == 19,"Insufficient funds do not grant item or charge rupees")
	world.state.rupees = 25
	for i in range(240): tick()
	check(world.state.item_value(&"keys") == 1 and world.state.rupees == 5,"Shop grants one item and charges exact price")
	world.state.rupees = 20
	for i in range(40): tick()
	check(world.state.item_value(&"keys") == 1 and world.state.rupees == 20,"Shop allows only one purchase per visit")
	world.enter_room(world.rooms[&"entry"],Vector2i(120,125),Vector2i.UP)
	enter("shop")
	approach(func(): return world.state.item_value(&"keys") == 2)
	for i in range(240): tick()
	check(world.state.rupees == 0,"Shop reopens on next visit and charges again")
	world.combat.encounter_room = null;world.free()
	print("Authored resident native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
