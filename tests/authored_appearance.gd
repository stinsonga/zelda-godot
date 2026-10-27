extends SceneTree
const Pack = preload("res://editor/shared/room_pack.gd")
const Art = preload("res://editor/shared/appearance.gd")
const Fixture = preload("res://editor/tests/appearance_fixture.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
var failures := 0
var world: Node
func check(ok: bool, text: String) -> void:
	if not ok: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func walk(direction: Vector2i, target: StringName, limit: int = 300) -> bool:
	for i in range(limit):
		world.combat.player_invulnerability = 1000
		world.simulate_tick(direction)
		if world.room.id == target and world.entry_walk_remaining == 0 and world.transition == null and world.settle_ticks == 0: return true
	return false
func run() -> void:
	var fixture := Fixture.create()
	var pack := Pack.sample()
	var overlay := Art.fresh(pack.id)
	overlay.enemy_sprites.crawler = "rom/us_prg0/test_beast"
	var indices: Array = []
	indices.resize(176);indices.fill(-1)
	indices[51] = 1
	indices[0] = 0
	overlay.room_tiles.entry = {"atlas":"rom/us_prg0/levels/test","indices":indices}
	var plain := Adapter.compile(pack)
	var painted := Adapter.compile(pack,overlay,fixture)
	check(painted.errors.is_empty() and painted.appearance_warnings.is_empty(),"Local appearance compiles into valid native resources")
	check(painted.world.rooms[0].tile_atlas.get_image().get_pixel(49,49) == Color.BLUE,"Runtime paints the same source pixels as editor")
	for i in range(pack.rooms.size()):
		var before: Resource = plain.world.rooms[i]
		var after: Resource = painted.world.rooms[i]
		check(after.tiles == before.tiles and after.collision_tiles == before.collision_tiles and after.movement_bounds == before.movement_bounds,"Appearance leaves room collision and movement bounds intact")
		check(after.is_pixel_solid(Vector2i(1,1)) and not after.is_pixel_solid(Vector2i(49,49)),"Painted wall stays solid and painted floor stays walkable")
	var before_enemy: Resource = plain.world.rooms[1].enemies[0].enemy
	var after_enemy: Resource = painted.world.rooms[1].enemies[0].enemy
	check(after_enemy.health == before_enemy.health and after_enemy.speed_subpixels == before_enemy.speed_subpixels and after_enemy.behavior == before_enemy.behavior and after_enemy.contact_damage == before_enemy.contact_damage,"Skins leave enemy mechanics unchanged")
	check(painted.world.visual_theme.sprites.has(&"__editor_crawler_down_1"),"Runtime theme contains selected animation frames")
	check(load("res://content/themes/default.tres").sprites.is_empty(),"Runtime skin compilation never modifies shared default theme")
	world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false
	world.world_definition = painted.world
	root.add_child(world)
	world.set_physics_process(false)
	world.scroll_transitions = false
	check(not world.can_occupy(Vector2i(0,0)) and world.can_occupy(Vector2i(48,45)),"Actual world collision agrees after art assignment")
	for i in range(100): world.simulate_tick(Vector2i.ZERO)
	world.player.place(Vector2i(64,77))
	world.simulate_tick(Vector2i.ZERO)
	world.player.place(Vector2i(120,45))
	check(walk(Vector2i.UP,&"hall"),"Skinned room key door still leads to its neighbour")
	for i in range(60): world.simulate_tick(Vector2i.ZERO)
	for actor in world.combat.enemies:
		actor.invulnerability = 0
		actor.receive_hit(actor.health,Vector2i.UP,"sword")
	for i in range(80): world.simulate_tick(Vector2i.ZERO)
	world.player.place(Vector2i(192,77))
	check(walk(Vector2i.RIGHT,&"vault"),"Skinning does not change enemy-clear shutter progression")
	world.combat.encounter_room = null
	world.free()
	DirAccess.remove_absolute(fixture.path_join("imported/levels/test.png"))
	DirAccess.remove_absolute(fixture.path_join("imported/test_beast_down_0.png"))
	var missing := Adapter.compile(pack,overlay,fixture)
	check(missing.errors.is_empty() and not missing.appearance_warnings.is_empty() and missing.world.rooms[0].tile_atlas == null,"Missing images retain playable placeholder resources and diagnostics")
	overlay.source_sha1 = "bad"
	var invalid := Adapter.compile(pack,overlay,fixture)
	check(invalid.errors.is_empty() and not invalid.appearance_warnings.is_empty(),"Wrong revision art is ignored without breaking content")
	Fixture.remove(fixture)
	print("Appearance runtime checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
