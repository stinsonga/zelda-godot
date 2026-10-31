extends SceneTree
const Fixture = preload("door_group_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Solver = preload("../shared/progression_solver.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(180).timeout.connect(func(): push_error("Floor generation test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var catalog := Fixture.floor_catalog()
	check(Templates.validate(catalog).is_empty(),"Stair-cell library validates: "+str(Templates.validate(catalog)))
	var bad := catalog.duplicate(true)
	bad.templates[0].stair_cell = [7,9]
	check(not Templates.validate(bad).is_empty(),"A stair cell stays clear of door approaches")
	bad.templates[0].stair_cell = [7,5]
	check(not Templates.validate(bad).is_empty(),"A stair cell cannot cover the reward")
	bad = catalog.duplicate(true);bad.format_version = 2
	check(not Templates.validate(bad).is_empty(),"Stair cells need format 3")
	var pillars: Dictionary = catalog.templates.filter(func(t): return t.id == "key_pillars")[0]
	check(Templates.mirrored(pillars,"horizontal").stair_cell == [8,4],"Mirroring moves the stair cell")
	check(Generator.floor_changes(6,3) == [1,3] and Generator.floor_changes(8,2) == [3] and Generator.floor_changes(6,4).is_empty(),"Floor changes avoid gated doors and adjacent rooms")
	var plain := {"branch_rooms":2,"loop_count":0}
	var single := Generator.new().generate(catalog,42,8,"blue_candle",6000,plain)
	var one_floor := Generator.new().generate(catalog,42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":0,"floors":1})
	check(single.has("pack") and one_floor.has("pack") and Templates.canonical(single.pack) == Templates.canonical(one_floor.pack),"One floor keeps the existing recipe")
	for recipe in [[catalog,42,8,{"branch_rooms":2,"loop_count":1,"floors":2}],[catalog,7,8,{"branch_rooms":0,"loop_count":0,"floors":3}],[catalog,91,6,{"branch_rooms":0,"loop_count":0,"floors":3}],[Fixture.floor_catalog("suites"),42,8,{"branch_rooms":2,"loop_count":0,"floors":2}]]:
		var label := "seed %d, %d rooms, %d floors" % [recipe[1],recipe[2],recipe[3].floors]
		var generated := Generator.new().generate(recipe[0],recipe[1],recipe[2],"blue_candle",6000,recipe[3])
		check(generated.errors.is_empty(),"Generates across floors (%s): %s" % [label,str(generated.errors)])
		if not generated.has("pack"): continue
		var pack: Dictionary = generated.pack
		check(pack.generation.version == 8 and pack.generation.floors == recipe[3].floors and pack.id.contains("_f%d_" % recipe[3].floors),"Floors are recipe version 8 (%s)" % label)
		check(Pack.validate(pack).is_empty() and Pack.layout_warnings(pack).is_empty(),"Generated floors validate without door warnings (%s): %s" % [label,str(Pack.layout_warnings(pack))])
		var used: Array = []
		for room in pack.rooms:
			if Pack.floor_of(room) not in used: used.append(Pack.floor_of(room))
		used.sort()
		check(used == range(recipe[3].floors),"Every floor is used (%s): %s" % [label,str(used)])
		check(pack.goals.any(func(goal): return Pack.floor_of(pack.rooms.filter(func(r): return r.id == goal.room)[0]) == recipe[3].floors-1),"The goal is on the top floor (%s)" % label)
		check(generated.proof.events.any(func(e): return e.type == "stairs"),"The proof climbs stairs (%s)" % label)
		var again := Generator.new().generate(recipe[0],recipe[1],recipe[2],"blue_candle",6000,recipe[3])
		check(again.has("pack") and Templates.canonical(again.pack) == Templates.canonical(pack),"Floor layouts are deterministic (%s)" % label)
	var flat := Templates.defaults();flat.format_version = 3
	var failed := Generator.new().generate(flat,42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":0,"floors":2})
	check(not failed.errors.is_empty(),"Floors need templates with stair cells")
	failed = Generator.new().generate(Templates.defaults(),42,8,"blue_candle",6000,{"branch_rooms":2,"loop_count":0,"floors":2})
	check(not failed.errors.is_empty() and failed.errors[0].contains("format-3"),"Floors need a format-3 library")
	failed = Generator.new().generate(catalog,42,6,"blue_candle",6000,{"branch_rooms":0,"loop_count":0,"floors":4})
	check(not failed.errors.is_empty(),"At most three floors")
	print("Floor generation checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
