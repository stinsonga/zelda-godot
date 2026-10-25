extends SceneTree
## Dungeon monsters: Stalfos, Gels, Zols, Keese, Goriyas, and Ropes, plus kill
## triggers. Needs a local ROM import; reports a skip without one.
var failures := 0
const Main = preload("res://scenes/main.tscn")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Dungeon monster suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func definition(name: String) -> Resource:
	return load("res://imported/enemies/" + name + ".tres")

func actor(name: String, at: Vector2i, facing: Vector2i = Vector2i.RIGHT) -> RefCounted:
	var spawn = Spawn.new()
	spawn.id = StringName(name)
	spawn.enemy = definition(name)
	spawn.position = at
	spawn.facing = facing
	spawn.spawn_ticks = 0
	var result = Actor.new()
	result.setup(spawn)
	result.spawn_remaining = 0
	return result

func open(_at: Vector2i, _direction: Vector2i) -> bool: return true

func kill_all(world: Node) -> void:
	for monster in world.combat.enemies:
		monster.spawn_remaining = 0
		monster.waiting_spawn = false
		monster.health = 0
		monster.death_remaining = 0

func run() -> void:
	if not ResourceLoader.exists("res://imported/enemies/stalfos.tres"):
		print("Dungeon monster checks: SKIPPED (no local ROM import)")
		quit(0)
		return
	check_definitions()
	check_behaviors()
	var world = Main.instantiate()
	world.scroll_transitions = false
	root.add_child(world)
	world.set_physics_process(false)
	check_rooms(world)
	world.free()
	print("Dungeon monster checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_definitions() -> void:
	for name in ["stalfos", "blue_goriya", "red_goriya", "zol", "gel", "child_gel", "blue_keese", "red_keese", "black_keese", "rope"]:
		check(definition(name).validation_errors().is_empty(), "Imported " + name + " must validate")
	check(definition("stalfos").health == 2 and not definition("stalfos").shooting_enabled, "First-quest Stalfos take two hits and never shoot")
	check(definition("blue_goriya").health == 5 and definition("red_goriya").health == 3, "Goriya health must come from the ROM")
	check(definition("red_goriya").shoot_random_values == PackedInt32Array([35, 119]), "Red Goriyas throw only on random $23 or $77")
	check(definition("zol").splits_into == definition("child_gel") and definition("gel").health == 1, "Zols split into one-hit Gels")
	check(definition("blue_keese").flight_initial_speed == 0x1F and definition("red_keese").flight_initial_speed == 0x7F, "Keese start speeds follow InitBlueKeese")

func check_behaviors() -> void:
	var stalfos = actor("stalfos", Vector2i(64, 61))
	var path := 0
	for i in range(32):
		var before: Vector2i = stalfos.subposition
		stalfos.tick(Vector2i(200, 141), Callable(), open, true, {})
		path += absi(stalfos.subposition.x - before.x) + absi(stalfos.subposition.y - before.y)
	check(path == 32 * 128, "Stalfos walk half a pixel a frame")
	var gel = actor("gel", Vector2i(64, 61))
	gel.family.initialized = true
	var context := {"bounds": Rect2i(33, 30, 175, 95)}
	var waited := false
	for i in range(120):
		gel.tick(Vector2i(200, 141), Callable(), open, true, context)
		if gel.family.timer >= 5:
			var before: Vector2i = gel.position()
			gel.tick(Vector2i(200, 141), Callable(), open, true, context)
			waited = gel.position() == before
			break
	check(waited and gel.family.timer in [7, 23, 39, 55], "Gels wait at squares for one of their delays")
	var keese = actor("blue_keese", Vector2i(120, 77), Vector2i.ZERO)
	keese.source_random = 5
	keese.tick(Vector2i(0, 0), Callable(), open, true, context)
	check(keese.targetable() and keese.family.flight_speed >= 0x1F, "Keese can be hit while flying and start at their initial speed")
	for i in range(600):
		keese.source_random = (i * 37) & 255
		keese.source_next_random = (i * 91) & 255
		keese.tick(Vector2i(0, 0), Callable(), open, true, context)
		check(Rect2i(32, 29, 178, 98).has_point(keese.position()), "Keese stay inside dungeon object bounds")
		if failures > 0: break
	var rope = actor("rope", Vector2i(64, 93), Vector2i.UP)
	rope.family.initialized = true
	rope.family.timer = 60
	for i in range(40):
		rope.tick(Vector2i(144, 77), Callable(), open, true, context)
		if rope.family.rope_speed == 384: break
	check(rope.family.rope_speed == 384 and rope.facing == Vector2i.RIGHT, "Ropes rush when lined up with Link at a square")

func check_rooms(world: Node) -> void:
	# Goriya boomerang: thrown, the thrower waits, then it comes back.
	world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 141), Vector2i.UP)
	world.combat.enemies.clear()
	var goriya = actor("blue_goriya", Vector2i(64, 77))
	goriya.slot = 1
	world.combat.enemies.append(goriya)
	world.player.place(Vector2i(144, 77))
	world.combat.player_invulnerability = 100000
	var thrown := false
	for i in range(200):
		world.combat.tick(world)
		if goriya.shot_out:
			thrown = true
			break
	check(thrown and world.combat.rocks.size() == 1 and world.combat.rocks[0].kind == "boomerang", "Blue Goriyas throw boomerangs at Link")
	var held: Vector2i = goriya.position()
	var returned := false
	for i in range(200):
		world.combat.tick(world)
		check(goriya.position() == held or not goriya.shot_out, "A Goriya waits while its boomerang is out")
		if not goriya.shot_out:
			returned = true
			break
	check(returned and world.combat.rocks.is_empty(), "Boomerangs return to their thrower")
	# Zol: a surviving hit splits it in two; the room needs one more kill.
	world.combat.enemies.clear()
	world.combat.rocks.clear()
	var zol = actor("zol", Vector2i(64, 77), Vector2i.RIGHT)
	world.combat.enemies.append(zol)
	world.combat.encounter_total = 1
	check(zol.receive_hit(1, Vector2i.RIGHT) and zol.health == 1, "A Zol survives one wooden-sword hit")
	world.combat.tick(world)
	var gels: Array = world.combat.enemies.filter(func(monster: RefCounted) -> bool: return monster.definition.id == &"child_gel")
	check(gels.size() == 2 and zol.health == 0 and zol.drop_resolved and world.combat.encounter_total == 2, "A hit Zol becomes two Gels without a drop")
	check(gels[0].facing == -gels[1].facing and gels[0].facing.x == 0, "Split Gels dart apart perpendicular to the Zol")
	# Spawning, shutters, and items that wait for a clear room.
	world.enter_room(world.rooms[&"l1_52"], Vector2i(120, 77), Vector2i.UP)
	check(world.combat.enemies.size() > 0, "Keese rooms must spawn their monsters")
	for i in range(80): world.combat.tick(world)
	for monster in world.combat.enemies:
		check(world.combat.bounds.grow(1).has_point(monster.position()) or monster.waiting_spawn, "Dungeon monsters spawn inside the walls")
	var shutter: Resource = null
	for door in world.room.doors:
		if door.kind == "shutter": shutter = door
	check(shutter != null and not world.door_passable(world.room, shutter), "Shutters stay closed while monsters live")
	kill_all(world)
	check(world.door_passable(world.room, shutter), "Killing every monster opens the shutters")
	world.enter_room(world.rooms[&"l1_23"], Vector2i(120, 141), Vector2i.UP)
	var key: Resource = world.room.pickups[0]
	world.player.place(key.position)
	world.try_pickups()
	check(world.state.item_value(&"keys") == 0, "A room's reward waits until its monsters are gone")
	kill_all(world)
	world.try_pickups()
	check(world.state.item_value(&"keys") == 1, "Clearing the room releases its key")
	world.enter_room(world.rooms[&"l1_c7f"], Vector2i(48, 29), Vector2i.UP)
	check(world.combat.enemies.size() == 4 and world.combat.enemies.all(func(monster: RefCounted) -> bool: return monster.definition.id == &"blue_keese"), "Cellars hold four blue Keese")
