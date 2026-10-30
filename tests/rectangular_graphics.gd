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
	var folder := Fixture.create();Fixture.add_tall(folder)
	var source := Fixture.pack()
	source.appearance.enemy_sprites.crawler = "art/test_art/tall"
	for room in source.appearance.room_sprites:
		for slot in source.appearance.room_sprites[room]: source.appearance.room_sprites[room][slot] = "art/test_art/tall"
	var plain: Dictionary = source.duplicate(true);plain.erase("appearance")
	var before := Adapter.compile(plain);var result := Adapter.compile(source,{},folder)
	check(result.errors.is_empty() and result.appearance_warnings.is_empty(),"Rectangular art compiles into native resources")
	var enemy: Resource = result.world.rooms[1].enemies[0].enemy
	var original: Resource = before.world.rooms[1].enemies[0].enemy
	check(enemy.authored_draw_size==Vector2(16,24) and enemy.authored_draw_offset==Vector2(-2,-8),"Enemy retains drawing geometry")
	check(enemy.collision_size==original.collision_size and enemy.collision_offset==original.collision_offset and enemy.speed_subpixels==original.speed_subpixels and enemy.health==original.health,"Sprite layout leaves collisions, speed and health unchanged")
	check(result.world.visual_theme.sprites[&"__editor_crawler_left_1"].get_size()==Vector2(32,48),"Native animation retains source resolution and aspect")
	var room: Resource = result.world.rooms[0]
	check(room.authored_sprite_layouts.secret==Rect2(-2,-8,16,24) and room.authored_sprite_layouts.stairs==Rect2(-2,-8,16,24) and result.world.rooms[2].authored_sprite_layouts.resident==Rect2(-2,-8,16,24),"All room-feature slots retain drawing geometry")
	check(room.tiles==before.world.rooms[0].tiles and room.secret.cell==before.world.rooms[0].secret.cell and room.portals[0].area==before.world.rooms[0].portals[0].area,"Room art leaves terrain, secret and stair interaction positions intact")
	result.world.start_room = &"hall"
	var game = preload("res://scenes/main.tscn").instantiate();game.use_imported_world = false;game.world_definition = result.world
	root.add_child(game);game.set_physics_process(false)
	check(game.authored_room_rect(room,"secret",Vector2(80,128))==Rect2(78,120,16,24),"Native object anchor plus offset matches editor geometry")
	check(game.authored_room_rect(room,"unbound",Vector2(80,128))==Rect2(80,128,16,16),"Unbound geometry keeps native defaults")
	for i in range(80): game.simulate_tick(Vector2i.ZERO)
	for actor in game.combat.enemies:
		check(actor.size()==Vector2i(16,16) and actor.collision_size()==Vector2i(16,16) and actor.hit_position()==actor.position(),"Live enemy hitbox ignores enlarged and shifted drawing")
	game.queue_redraw();await process_frame;await process_frame
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/zelda-rect-game.png")
	for actor in game.combat.enemies: actor.source.tile_probe = Callable()
	game.combat.enemies.clear();game.combat.encounter_room = null;game.free()
	var catalog := Templates.defaults()
	for role in Templates.ROLES:
		var captured := Templates.capture(catalog,source,"hall","tall_"+role,role,["up","right","down","left"],[])
		check(captured.errors.is_empty(),"Tall enemy art captures into template")
		if not captured.errors.is_empty(): Fixture.remove(folder);quit(1);return
		catalog = captured.catalog
	catalog.templates = catalog.templates.filter(func(t): return t.id.begins_with("tall_"))
	var generated := Generator.new().generate(catalog,42,6)
	check(generated.errors.is_empty(),"Tall-skinned dungeon still passes progression checks")
	if generated.has("pack"):
		var native := Adapter.compile(generated.pack,{},folder)
		check(native.errors.is_empty() and native.appearance_warnings.is_empty(),"Generated bindings resolve rectangular art")
		for generated_room in native.world.rooms:
			for spawn in generated_room.enemies: check(spawn.enemy.authored_draw_size==Vector2(16,24) and spawn.enemy.authored_draw_offset==Vector2(-2,-8),"Template generation preserves library draw geometry")
	Fixture.remove(folder)
	print("Rectangular graphics runtime checks: ","PASS" if failures==0 else "FAIL");call_deferred("finish")
func finish() -> void: quit(0 if failures==0 else 1)
