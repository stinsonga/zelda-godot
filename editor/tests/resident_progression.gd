extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Solver = preload("../shared/progression_solver.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Fixture = preload("economy_fixture.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Resident progression checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	for pack in [Fixture.keys(),Fixture.keys(1,20,20),Fixture.item_gift(),Fixture.item_gift("wooden_sword"),Fixture.barrier("gift"),Fixture.keys(2,0,0),Fixture.choice(),Fixture.choice(2,true),Fixture.bomb_shop(),Fixture.funded_by_gift()]:
		check(Pack.validate(pack).is_empty(),"Economy fixture validates")
		var result := Solver.new().solve(pack)
		check(result.status == "solved","Resident route solves: "+str(result.get("message")))
		if result.status != "solved": print(result)
		check(result.events.any(func(e): return e.type == "resident"),"Witness includes actual resident transaction")
	var repeat := Solver.new().solve(Fixture.keys())
	check(repeat.events.filter(func(e): return e.type == "resident").size() == 2,"Two key locks require two purchases on distinct visits")
	check(repeat.events.filter(func(e): return e.type == "stairs" and e.target == "market").size() >= 2,"Shop resets only on room re-entry")
	check("unchosen offer" in repeat.assumptions,"Report discloses conservative offer routing")
	for pack in [Fixture.keys(1,20,19),Fixture.keys(2,0,0,true),Fixture.barrier(),Fixture.choice(1,true)]:
		var result := Solver.new().solve(pack)
		check(result.status == "blocked","Underfunded, repeated gift, hint barrier or overspent route is blocked: "+str(result.status))
	var one_coin := Fixture.funded_by_gift()
	for room in one_coin.rooms:
		if room.id == "market": room.resident.wares[1].price = 2
	check(Solver.new().solve(one_coin).status == "blocked","One coin gift cannot be reclaimed to fund a second rupee")
	var example := Pack.read(ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("content/packs/shop_route.json"))
	check(example.errors.is_empty() and Solver.new().solve(example.pack).status == "solved","Shipped shop route is certifiable")
	var choice := Solver.new().solve(Fixture.choice())
	check(choice.events.filter(func(e): return e.type == "resident").all(func(e): return e.item == "bow"),"Solver can choose the useful ware without buying the wrong one")
	var money := Fixture.keys();money.rooms[-1].resident.wares[1] = {"item":"rupee","price":0}
	check(Solver.new().solve(money).status == "unsupported","Repeatable money offers are declined explicitly")
	var mixed := Fixture.bomb_shop();mixed.rooms[0].pickups.append({"id":"bombs","item":"bombs","position":[176,109]})
	check(Solver.new().solve(mixed).status == "unsupported","Mixed shop and automatic finite bomb supply is not certified")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(Fixture.keys()))
	check(Solver.new().solve(parsed).status == "solved","Economy route survives JSON roundtrip")
	check(Solver.new().solve(Fixture.keys(),1).status == "limit","Economy search limits stay inconclusive")
	var catalog := Templates.defaults()
	for entry in catalog.templates:
		if entry.role == "item": entry.room.resident = Pack.resident("gift")
	var generated := Generator.new().generate(catalog,42,6)
	check(generated.errors.is_empty() and generated.pack.generation.version == 3 and generated.pack.id.begins_with("generated_v3_"),"Resident libraries use a new recipe and world identity")
	check(Pack.write("/tmp/zelda-shop-route.json",Fixture.keys()) == OK,"ROM-free shop route example writes")
	print("Resident progression checks: ","PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
