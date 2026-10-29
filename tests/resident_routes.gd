extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/economy_fixture.gd")
func settle() -> void:
	for i in range(900):
		var session: RefCounted = world.cave_session
		var held: bool = session != null and (session.blocks_player() or session.phase in ["prices","text","hide"])
		if not held and world.lift_remaining == 0 and world.state.rupees_settled(): return
		tick()
	check(false,"Resident dialogue, lift and rupee counters settle")
func after_walk_tick() -> void: settle()
func prepare_room() -> void:
	for i in range(65): tick()
	settle()
	if not world.combat.enemies.is_empty(): check(world.state.item_value(&"sword")>0,"Witness supplies sword before assuming combat victory")
	for actor in world.combat.enemies:
		actor.invulnerability = 0
		if actor.health>0: actor.receive_hit(actor.health,Vector2i.RIGHT,"sword")
	for i in range(65): tick()
	settle()
func replay_economy_event(event: Dictionary) -> void:
	if event.type == "coins":
		for i in event.pickups.size():
			var at := Vector2i(int(event.positions[i][0]),int(event.positions[i][1]))
			check(walk_to(func(p): return p == at),"Native movement collects planned coin group")
			for j in range(4): tick()
			settle()
			check(world.state.has_collected(StringName(event.room),StringName(event.pickups[i])),"Planned coin is actually collected")
	else:
		var at := Vector2i(int(event.at[0]),int(event.at[1]))
		check(walk_to(func(p): return p == at),"Native movement reaches selected resident offer")
		tick();settle()
		check(world.cave_session.chosen == int(event.slot) and world.cave_session.taken[int(event.slot)],"Native transaction takes exactly the selected ware")
		check(not world.cave_session.person_visible(),"Transaction finishes before next route action")
	check(world.state.rupees>=int(event.rupees),"Settled native wallet covers the certified budget")
func run() -> void:
	for pack in [Fixture.keys(),Fixture.keys(1,20,20),Fixture.item_gift(),Fixture.item_gift("wooden_sword"),Fixture.barrier("gift"),Fixture.keys(2,0,0),Fixture.choice(),Fixture.choice(2,true),Fixture.bomb_shop(),Fixture.funded_by_gift()]:
		var proof := Solver.new().solve(pack)
		check(proof.status == "solved","Resident route has solver witness")
		if proof.status == "solved": replay(pack,proof)
	var catalog := Templates.defaults()
	for entry in catalog.templates:
		if entry.role == "item": entry.room.resident = Pack.resident("gift")
	var generated := Generator.new().generate(catalog,42,6)
	check(generated.errors.is_empty(),"Resident-bearing template library generates")
	if generated.has("pack"): replay(generated.pack,generated.proof)
	print("Resident route native checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
