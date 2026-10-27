extends SceneTree
const Pack = preload("res://editor/shared/room_pack.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Authored pack test timed out"); quit(1))
	call_deferred("run")
func check(value: bool, text: String) -> void:
	if not value: failures += 1; push_error(text)
func walk(direction: Vector2i, target: StringName, limit: int = 300) -> bool:
	for i in range(limit):
		world.combat.player_invulnerability = 1000
		world.simulate_tick(direction)
		if world.room.id == target and world.entry_walk_remaining == 0 and world.transition == null and world.settle_ticks == 0: return true
	return false
func run() -> void:
	var loaded := Pack.read("res://content/packs/lantern_vault.json")
	check(loaded.errors.is_empty(),"Shared sample validates")
	var result := Adapter.compile(loaded.pack)
	check(result.errors.is_empty(),"Pack compiles into native definitions")
	if not result.errors.is_empty(): quit(1); return
	for room in result.world.rooms:
		check(room.tile_atlas == null and room.tile_indices.is_empty(),"No imported art in editor-authored rooms")
		check(room.validation_errors().is_empty(),"Native room validation passes")
	world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false
	world.world_definition = result.world
	root.add_child(world)
	world.set_physics_process(false)
	world.scroll_transitions = false
	world.state.take_item(load("res://content/items/wooden_sword.tres"))
	check(world.room.id == &"entry" and world.world_id == "authored/lantern_vault","Pack starts independently of imported world")
	for i in range(100): world.simulate_tick(Vector2i.ZERO)
	world.player.place(Vector2i(120,45))
	check(not walk(Vector2i.UP,&"hall",60),"Editor key door blocks without a key")
	world.player.place(Vector2i(64,77))
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.item_value(&"keys") == 1,"Editor-placed key can be collected")
	world.player.place(Vector2i(120,45))
	check(walk(Vector2i.UP,&"hall"),"Key opens authored connection and reaches hall")
	check(world.state.item_value(&"keys") == 0,"Authored key door spends its key")
	check(world.combat.enemies.size() == 2,"Editor placements instantiate both guards")
	var right_door: Resource
	for door in world.room.doors:
		if door.direction == Vector2i.RIGHT: right_door = door
	check(not world.door_passable(world.room,right_door),"Guard hall shutter starts closed")
	for i in range(60): world.simulate_tick(Vector2i.ZERO)
	for enemy in world.combat.enemies:
		enemy.invulnerability = 0
		enemy.receive_hit(enemy.health,Vector2i.UP,"sword")
	for i in range(80): world.simulate_tick(Vector2i.ZERO)
	check(world.door_passable(world.room,right_door),"Clearing authored guards opens shutter")
	world.player.place(Vector2i(192,77))
	check(walk(Vector2i.RIGHT,&"vault"),"Open shutter leads into vault")
	world.player.place(Vector2i(120,77))
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.has_collected(&"vault",&"reward"),"Authored reward can be collected")
	world.free()
	var variant: Dictionary = loaded.pack.duplicate(true)
	variant.enemy_types.crawler.health = 7
	variant.enemy_types.crawler.speed_subpixels = 64
	var changed := Adapter.compile(variant)
	check(changed.world.rooms[1].enemies[0].enemy.health == 7 and changed.world.rooms[1].enemies[0].enemy.speed_subpixels == 64,"Edited variant values reach native actors")
	variant.rooms[0].pickups[0].item = "../bad"
	check(not Adapter.compile(variant).errors.is_empty(),"Runtime refuses invalid pack before resource loading")
	print("Authored pack checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
