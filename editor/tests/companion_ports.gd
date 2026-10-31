extends SceneTree
const Fixture = preload("door_group_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("Companion port test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var catalog := Fixture.companion_catalog()
	check(not catalog.has("errors") and Templates.validate(catalog).is_empty(),"Companion-port library validates: "+str(Templates.validate(catalog)))
	var bad := catalog.duplicate(true)
	var suite: Dictionary = bad.templates.filter(func(t): return t.id == "key_suite_up")[0]
	var inward: String = suite.annexes[0].connections.keys()[0]
	suite.companion_ports = {suite.annexes[0].id:[inward]}
	check(not Templates.validate(bad).is_empty(),"A companion port cannot overlap its internal door")
	suite.companion_ports = {"nowhere":["up"]}
	check(not Templates.validate(bad).is_empty(),"A companion port must name a companion")
	var flipped: Dictionary = Templates.mirrored(catalog.templates.filter(func(t): return t.id == "key_suite_up")[0],"vertical")
	check(flipped.companion_ports.values()[0].has("down") and not flipped.companion_ports.values()[0].has("up"),"Mirroring flips companion ports")
	var from_companion := false
	for seed_value in [42,7,91,5]:
		var generated := Generator.new().generate(catalog,seed_value,8)
		check(generated.errors.is_empty(),"Seed %d generates with companion ports: %s" % [seed_value,str(generated.errors)])
		if not generated.has("pack"): continue
		check(generated.pack.generation.version == 7 and Pack.validate(generated.pack).is_empty(),"Companion layouts are recipe version 7")
		var again := Generator.new().generate(catalog,seed_value,8)
		check(again.has("pack") and Templates.canonical(again.pack) == Templates.canonical(generated.pack),"Companion layouts are deterministic")
		for room in generated.pack.rooms:
			if not room.id.contains("_part_"): continue
			for link in room.connections.values():
				if not link.target.begins_with(room.id.get_slice("_part_",0)): from_companion = true
	check(from_companion,"Some room is reached through a companion's port")
	print("Companion port checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
