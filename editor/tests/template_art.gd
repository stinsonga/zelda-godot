extends SceneTree
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Bindings = preload("../shared/art_bindings.gd")
const Generator = preload("../shared/dungeon_generator.gd")
const Units = preload("template_fixture.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Template art checks timed out");quit(1))
	call_deferred("run")
func tiles() -> Dictionary:
	var indices: Array = [];indices.resize(176);indices.fill(-1);indices[51] = 1
	return {"atlas":"art/test_art/tiles","indices":indices}
func run() -> void:
	var source := Units.source()
	source.appearance = Bindings.fresh()
	source.appearance.room_tiles = {"entry":tiles(),"cellar":tiles(),"vault":tiles()}
	source.appearance.room_sprites = {"entry":{"secret":"art/test_art/beast","stairs":"art/test_art/beast"},"cellar":{"stairs":"art/test_art/beast"}}
	source.appearance.enemy_sprites.crawler = "art/test_art/beast"
	var original: Dictionary = source.duplicate(true)
	var captured := Templates.capture(Templates.defaults(),source,"entry","skinned_unit","key",Pack.EDGES,[],true,"cellar",[120,125])
	check(captured.errors.is_empty(),"Art-bearing cellar capture validates: "+str(captured.errors))
	if not captured.errors.is_empty(): quit(1);return
	var entry: Dictionary = captured.catalog.templates[-1]
	var variant: String = entry.annexes[0].enemies[0].type
	check(source==original and captured.catalog.format_version==2,"Capture preserves source and uses version 2")
	check(entry.appearance.enemy_sprites.has(variant) and not entry.appearance.enemy_sprites.has("crawler"),"Enemy art follows scoped definitions")
	check(entry.appearance.room_tiles.size()==2 and not entry.appearance.room_tiles.has("vault"),"Capture excludes art outside selected unit")
	var a := Templates.instantiate(entry,"room_a");var b := Templates.instantiate(entry,"room_b")
	check(a.appearance.room_tiles.has("room_a_cellar_1") and a.appearance.room_sprites.has("room_a") and not a.appearance.room_tiles.has("entry"),"Every room binding remaps to the occurrence")
	a.appearance.room_tiles.room_a.indices[51] = 0
	check(b.appearance.room_tiles.room_b.indices[51]==1 and entry.appearance.room_tiles.entry.indices[51]==1,"Occurrences own independent visual data")
	var invalid: Dictionary = captured.catalog.duplicate(true)
	invalid.templates[-1].appearance.room_tiles.vault = tiles()
	check(not Templates.validate(invalid).is_empty(),"Template cannot bind art outside its unit")
	invalid = captured.catalog.duplicate(true);invalid.templates[-1].appearance.enemy_sprites[variant] = "rom/us_prg0/beast"
	check(not Templates.validate(invalid).is_empty(),"Private ROM IDs cannot enter templates")
	invalid = captured.catalog.duplicate(true)
	var conflicting: Dictionary = entry.duplicate(true);conflicting.id = "conflict";conflicting.appearance.enemy_sprites[variant] = "art/test_art/other"
	invalid.templates.append(conflicting)
	check(not Templates.validate(invalid).is_empty(),"Conflicting global variant skins are diagnosed")
	var catalog := Templates.defaults()
	for role in Templates.ROLES:
		var pack := Pack.fresh();Pack.upgrade(pack)
		if role in ["combat","goal"]: pack.rooms[0].enemies = [{"id":"guard","type":"crawler","position":[80,61]}]
		pack.appearance = Bindings.fresh();pack.appearance.room_tiles.entry = tiles();pack.appearance.enemy_sprites.crawler = "art/test_art/beast"
		var result := Templates.capture(catalog,pack,"entry","art_"+role,role,Pack.EDGES,[])
		check(result.errors.is_empty(),"Single-room authored capture: "+role)
		if not result.errors.is_empty(): quit(1);return
		catalog = result.catalog
	catalog.templates = catalog.templates.filter(func(t): return t.id.begins_with("art_"))
	var saved: Dictionary = JSON.parse_string(JSON.stringify(catalog))
	check(Templates.fingerprint(saved)==Templates.fingerprint(catalog),"Art survives JSON round trip with stable fingerprint")
	var generated := Generator.new().generate(saved,42,6)
	check(generated.errors.is_empty(),"Skinned recipe is progression-verified: "+str(generated.errors))
	if generated.has("pack"):
		check(Pack.validate(generated.pack).is_empty() and generated.pack.appearance.room_tiles.size()==6,"Generated pack has valid art for every primary room")
		var repeated := Generator.new().generate(saved,42,6)
		check(repeated.has("pack") and Templates.canonical(repeated.pack)==Templates.canonical(generated.pack),"Same art recipe and seed produce identical pack")
		for room in generated.pack.rooms:
			for enemy in room.enemies: check(generated.pack.appearance.enemy_sprites.has(enemy.type),"Generated enemies retain captured skins")
	var unit_catalog: Dictionary = captured.catalog
	unit_catalog.templates = unit_catalog.templates.filter(func(t): return t.role != "key" or t.id=="skinned_unit")
	var with_cellars := Generator.new().generate(unit_catalog,42,6)
	check(with_cellars.errors.is_empty(),"Art-bearing cellar unit generates")
	if with_cellars.has("pack"):
		for room in with_cellars.pack.rooms:
			if room.get("template_id")=="skinned_unit": check(with_cellars.pack.appearance.room_tiles.has(room.id) and with_cellars.pack.appearance.room_sprites.has(room.id),"Generated primary and cellar keep their visual slots")
	var resident := Pack.fresh();Pack.upgrade(resident);resident.rooms[0].resident = Pack.resident()
	resident.appearance = Bindings.fresh();resident.appearance.room_sprites.entry = {"resident":"art/test_art/beast"}
	var resident_capture := Templates.capture(Templates.defaults(),resident,"entry","art_resident","treasure",Pack.EDGES,[])
	check(resident_capture.errors.is_empty() and resident_capture.catalog.templates[-1].appearance.room_sprites.entry.has("resident"),"Single-room resident art survives capture")
	print("Template art checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
