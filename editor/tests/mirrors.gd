extends SceneTree
const Fixture = preload("door_group_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Generator = preload("../shared/dungeon_generator.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("Mirror test timed out");quit(1))
	call_deferred("run")
## Map cells relative to the primary: mirroring may shift a unit as a whole.
func relative(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate(true)
	var origin: Array = entry.room.map_position
	for room in [result.room]+result.get("annexes",[]): room.map_position = [int(room.map_position[0])-int(origin[0]),int(room.map_position[1])-int(origin[1])]
	return result
func run() -> void:
	var catalog := Fixture.mirrored_catalog()
	check(not catalog.has("errors") and Templates.validate(catalog).is_empty(),"Mirrored library validates: "+str(Templates.validate(catalog)))
	var up: Dictionary = catalog.templates.filter(func(t): return t.id == "key_suite_up")[0]
	var down := Templates.mirrored(up,"vertical")
	check(down.ports == ["right","up","left"] and down.room.connections.has("down") and not down.room.connections.has("up"),"Vertical mirror flips ports and internal doors")
	check(int(down.annexes[0].map_position[1]) == int(down.room.map_position[1])+1 and int(down.annexes[0].map_position[1]) <= 0,"Companion moves to the mirrored side, within map range")
	for mode in Templates.MIRRORS:
		var twice := Templates.mirrored(Templates.mirrored(up,mode),mode);up.erase("mirrors")
		var original: Dictionary = catalog.templates.filter(func(t): return t.id == "key_suite_up")[0].duplicate(true);original.erase("mirrors")
		check(Templates.canonical(relative(twice)) == Templates.canonical(relative(original)),"Mirroring twice restores the template: "+mode)
	check(Templates.mirror_position([120,77],true,true) == [120,77] and Templates.mirror_position([48,125],true,true) == [192,29] and Templates.mirror_position([64,69],false,true) == [64,69],"Positions mirror by body and foot row")
	var room := Pack.room("r");room.secret = {"cell":[4,3],"direction":"left","reveal":"item"};room.stairs = [{"id":"s","cell":[3,7],"target":"r","target_position":[48,61]}]
	var flipped: Dictionary = Templates.mirrored({"id":"t","ports":["up"],"room":room},"both").room
	check(flipped.secret.cell == [11,7] and flipped.secret.direction == "right" and flipped.stairs[0].cell == [12,3],"Secrets and stairs mirror their cells and directions")
	var bad := catalog.duplicate(true)
	bad.templates[0].mirrors = ["sideways"]
	check(not Templates.validate(bad).is_empty(),"Unknown mirror modes are rejected")
	bad = Fixture.mixed_catalog();bad.format_version = 3
	for entry in bad.templates:
		if entry.id == "mixed_key": entry.mirrors = ["vertical"]
	check(Array(Templates.validate(bad)).any(func(e): return e.contains("only mirror horizontally")),"Cellars refuse vertical mirrors")
	# Without mirrors, a library's variants are exactly its templates.
	var plain := Fixture.catalog()
	check(Templates.variants(plain.templates) == plain.templates,"Libraries without mirrors keep their candidates")
	var mirrored_used := false
	for seed_value in [42,7,91]:
		var generated := Generator.new().generate(catalog,seed_value,8,"blue_candle")
		check(generated.errors.is_empty(),"Seed %d generates with mirrored suites: %s" % [seed_value,str(generated.errors)])
		if generated.errors.is_empty():
			for r in generated.pack.rooms:
				for edge in r.connections:
					var inward := "up" if r.get("template_id","").ends_with("_up") else "right"
					if r.connections[edge].target.begins_with(r.id+"_part_") and edge != inward: mirrored_used = true
	check(mirrored_used,"Generation uses a mirrored suite")
	print("Mirror checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
