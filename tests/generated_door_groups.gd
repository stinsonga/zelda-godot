extends "res://tests/generated_dungeons.gd"
const Fixture = preload("res://editor/tests/door_group_fixture.gd")
func run() -> void:
	var loaded := Templates.read("res://content/templates/door_templates.json")
	check(loaded.errors.is_empty(),"Shipped door-group library loads")
	if not loaded.errors.is_empty(): quit(1);return
	var catalog: Dictionary = loaded.catalog
	check(not catalog.has("errors"),"Door-group library captures")
	if catalog.has("errors"): quit(1);return
	for recipe in [[42,6,{}],[42,8,{"branch_rooms":2,"loop_count":1}]]:
		var generated := Generator.new().generate(catalog,recipe[0],recipe[1],"blue_candle",6000,recipe[2])
		check(generated.errors.is_empty(),"Door-group recipe verifies")
		if generated.has("pack"):
			check(generated.pack.goals.any(func(goal): return goal.room.contains("_part_")),"Goal requires internal door traversal")
			replay(generated.pack,generated.proof)
	var mixed := Generator.new().generate(Fixture.mixed_catalog(),42,6)
	check(mixed.errors.is_empty(),"Mixed internal doors and cellar stairs verify")
	if mixed.has("pack"): replay(mixed.pack,mixed.proof)
	# Suites captured facing up or right, mirrored by the generator.
	for seed_value in [42,7,91]:
		var generated := Generator.new().generate(Fixture.mirrored_catalog(),seed_value,8)
		check(generated.errors.is_empty(),"Mirrored suites verify for seed %d" % seed_value)
		if generated.has("pack"): replay(generated.pack,generated.proof)
	# Rooms hung off companion rooms' ports.
	for seed_value in [42,7]:
		var generated := Generator.new().generate(Fixture.companion_catalog(),seed_value,8)
		check(generated.errors.is_empty(),"Companion ports verify for seed %d" % seed_value)
		if generated.has("pack"): replay(generated.pack,generated.proof)
	# Main paths split across floors, climbing generated stairs.
	for recipe in [["single",7,8,3],["suites",42,8,2]]:
		var generated := Generator.new().generate(Fixture.floor_catalog(recipe[0]),recipe[1],recipe[2],"blue_candle",6000,{"branch_rooms":0,"loop_count":0,"floors":recipe[3]})
		check(generated.errors.is_empty(),"%d floors verify for seed %d" % [recipe[3],recipe[1]])
		if generated.has("pack"): replay(generated.pack,generated.proof)
	print("Generated door-group native checks: ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)
