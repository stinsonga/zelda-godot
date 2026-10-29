extends SceneTree
const Fixture = preload("res://editor/tests/authored_art_fixture.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
const Templates = preload("res://editor/shared/dungeon_templates.gd")
const Generator = preload("res://editor/shared/dungeon_generator.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := Fixture.create();var pack := Fixture.pack()
	var plain: Dictionary = pack.duplicate(true);plain.erase("appearance")
	var before := Adapter.compile(plain)
	var result := Adapter.compile(pack,{},folder)
	check(result.errors.is_empty() and result.appearance_warnings.is_empty(),"Authored art compiles without local overlay: "+str(result))
	var room: Resource = result.world.rooms[0]
	check(room.atlas_cell_size==Vector2i(32,32) and room.tile_atlas.get_width()==512,"Runtime retains high-resolution tile cells")
	check(room.tiles==before.world.rooms[0].tiles and room.collision_tiles==before.world.rooms[0].collision_tiles,"Tile art does not alter collision")
	var enemy: Resource = result.world.rooms[1].enemies[0].enemy
	var original: Resource = before.world.rooms[1].enemies[0].enemy
	check(enemy.authored_frame_count==2 and enemy.animation_frame_ticks==9,"Runtime uses authored visual animation timing")
	check(enemy.behavior==original.behavior and enemy.health==original.health and enemy.speed_subpixels==original.speed_subpixels and enemy.contact_damage==original.contact_damage,"Art leaves behavior and stats unchanged")
	var texture: Texture2D = result.world.visual_theme.sprites[&"__editor_crawler_left_1"]
	check(texture.get_width()==32 and texture.get_image().get_pixel(1,1)==Color.CYAN,"Native theme has matching direction/frame crop")
	check(room.authored_sprites.secret.size()==2 and room.authored_sprites.stairs.size()==2 and result.world.rooms[2].authored_sprites.resident.size()==2,"Secret, stair and resident frames reach native rooms")
	var game = preload("res://scenes/main.tscn").instantiate()
	game.use_imported_world = false;game.world_definition = result.world
	root.add_child(game);game.set_physics_process(false)
	game.simulation_tick = 0
	check(game.authored_room_texture(room,"secret").get_image().get_pixel(1,1)==Color.RED,"First room object frame resolves")
	game.simulation_tick = 9
	check(game.authored_room_texture(room,"secret").get_image().get_pixel(1,1)==Color.BLUE,"Room object advances at configured ticks")
	game.queue_redraw();await process_frame;await process_frame
	game.free()
	DirAccess.remove_absolute(folder.path_join("content/art/test_art/tiles.png"))
	DirAccess.remove_absolute(folder.path_join("content/art/test_art/beast.png"))
	var missing := Adapter.compile(pack,{},folder)
	check(missing.errors.is_empty() and not missing.appearance_warnings.is_empty() and missing.world.rooms[0].tile_atlas==null and missing.world.rooms[0].authored_sprites.is_empty(),"Missing art falls back without blocking play")
	var source := Fixture.pack()
	source.appearance.room_tiles.hall = source.appearance.room_tiles.entry.duplicate(true)
	var catalog := Templates.defaults()
	for role in Templates.ROLES:
		var captured := Templates.capture(catalog,source,"hall","skinned_"+role,role,["up","right","down","left"],[])
		check(captured.errors.is_empty(),"Runtime recipe capture validates")
		if not captured.errors.is_empty(): Fixture.remove(folder);quit(1);return
		catalog = captured.catalog
	catalog.templates = catalog.templates.filter(func(t): return t.id.begins_with("skinned_"))
	# Restore the deliberately removed images before exercising generated packs.
	var restored := Fixture.create()
	var generated := Generator.new().generate(catalog,42,6)
	check(generated.errors.is_empty(),"Art-bearing native recipe is solvable")
	if generated.has("pack"):
		var native := Adapter.compile(generated.pack,{},restored)
		check(native.errors.is_empty() and native.appearance_warnings.is_empty(),"Generated art resolves through native adapter")
		for generated_room in native.world.rooms:
			check(generated_room.tile_atlas!=null and generated_room.atlas_cell_size==Vector2i(32,32),"Generated room retains source resolution")
			for spawn in generated_room.enemies: check(spawn.enemy.authored_frame_count==2,"Generated scoped enemy keeps animation frames")
	Fixture.remove(restored)
	Fixture.remove(folder)
	print("Authored graphics runtime checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
