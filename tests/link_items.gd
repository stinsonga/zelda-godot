extends SceneTree
## Link's bow, boomerang, recorder, and potion. Native checks need no ROM;
## the pond, whirlwind, and monster checks run with a local import.
var failures := 0
var completed := false
const Lab = preload("res://scenes/item_lab.tscn")
const Main = preload("res://scenes/main.tscn")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Saves = preload("res://scripts/save_store.gd")

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Link item suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func item(name: String) -> Resource:
	return load("res://content/items/" + name + ".tres")

func monster(definition: Resource, at: Vector2i) -> RefCounted:
	var spawn = Spawn.new()
	spawn.id = &"target"
	spawn.enemy = definition
	spawn.position = at
	spawn.spawn_ticks = 0
	var result = Actor.new()
	result.setup(spawn)
	result.spawn_remaining = 0
	return result

func thrown(world: Node, kind: String) -> RefCounted:
	for object in world.item_objects:
		if object.kind == kind: return object
	return null

func run() -> void:
	var temporary := "user://link_item_tests_%d" % Time.get_ticks_usec()
	var world = Lab.instantiate()
	world.save_store = Saves.new(temporary)
	root.add_child(world)
	world.set_physics_process(false)
	check_bow(world)
	check_boomerang(world)
	check_potion(world)
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = Main.instantiate()
		world.scroll_transitions = false
		world.save_store = Saves.new(temporary)
		root.add_child(world)
		world.set_physics_process(false)
		check_imported(world)
		world.free()
	else:
		completed = true
	check(completed, "Link item checks must run to completion")
	DirAccess.remove_absolute(temporary)
	print("Link item checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_bow(world: Node) -> void:
	world.state.take_item(item("arrows"))
	world.state.selected_item = &"arrows"
	world.player.place(Vector2i(120, 125))
	world.player.facing = Vector2i.UP
	world.state.rupees = 5
	check(not world.use_item(), "Arrows need the bow")
	world.state.take_item(item("bow"))
	check(world.use_item() and world.state.rupees_to_subtract == 1, "Each arrow costs a rupee")
	var arrow: RefCounted = thrown(world, "arrow")
	check(arrow.position == Vector2i(123, 109) and arrow.damage() == 2, "Wooden arrows start 16 pixels ahead, 3 right when vertical, and deal 2")
	check(not world.use_item(), "Only one arrow flies at a time")
	world.simulate_tick(Vector2i.ZERO)
	check(arrow.position == Vector2i(123, 106), "Arrows fly 3 pixels a frame")
	for i in range(60): world.simulate_tick(Vector2i.ZERO)
	check(thrown(world, "arrow") == null, "Arrows spark out at the room edge")
	world.state.rupees = 0
	world.state.rupees_to_subtract = 0
	check(not world.use_item(), "Arrows need a rupee")
	world.state.take_item(item("silver_arrows"))
	world.state.rupees = 5
	world.use_item()
	check(thrown(world, "arrow").damage() == 4, "Silver arrows deal 4")

func check_boomerang(world: Node) -> void:
	world.item_objects.clear()
	world.state.take_item(item("boomerang"))
	world.state.selected_item = &"boomerang"
	world.player.place(Vector2i(120, 125))
	world.player.facing = Vector2i.UP
	world.held_direction = Vector2i(1, -1)
	world.use_item()
	var boomerang: RefCounted = thrown(world, "boomerang")
	check(boomerang != null and boomerang.direction == Vector2i(1, -1), "The boomerang follows the held direction, diagonals included")
	var farthest := 0
	var came_back := false
	for i in range(80):
		world.simulate_tick(Vector2i.ZERO)
		if thrown(world, "boomerang") == null:
			came_back = true
			break
		farthest = maxi(farthest, boomerang.travelled)
	check(farthest >= 0x31 and farthest < 0x31 + 3 and came_back, "The wooden boomerang turns at $31 pixels and returns to Link")
	# Stun ordinary monsters; kill fragile ones; carry drops back.
	var target = monster(load("res://content/enemies/stout_octorok.tres"), Vector2i(120, 77))
	world.combat.enemies.clear()
	world.combat.enemies.append(target)
	world.held_direction = Vector2i.ZERO
	world.use_item()
	for i in range(30):
		world.simulate_tick(Vector2i.ZERO)
		if target.stun_ticks > 0: break
	check(target.stun_ticks > 0 and target.health == target.definition.health, "The boomerang stuns without hurting")
	var held: Vector2i = target.position()
	for i in range(20): target.tick(Vector2i(0, 0), func(_at: Vector2i) -> bool: return true)
	check(target.position() == held, "Stunned monsters stay put")
	var fragile: Resource = load("res://content/enemies/stout_octorok.tres").duplicate()
	fragile.fragile = true
	var small = monster(fragile, Vector2i(120, 77))
	world.item_objects.clear()
	world.combat.enemies.clear()
	world.combat.enemies.append(small)
	world.use_item()
	for i in range(30): world.simulate_tick(Vector2i.ZERO)
	check(small.health == 0, "The boomerang kills monsters with no health to spare")
	world.item_objects.clear()
	var reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = load("res://content/items/rupee.tres")
	reward.position = Vector2i(120, 85)
	reward.age = 40
	world.combat.rewards.append(reward)
	var rupees: int = world.state.rupees
	world.use_item()
	for i in range(40): world.simulate_tick(Vector2i.ZERO)
	check(reward.collected and world.state.rupees_to_add + world.state.rupees > rupees, "The boomerang fetches drops")

func check_potion(world: Node) -> void:
	world.item_objects.clear()
	world.state.take_item(item("red_potion"))
	world.state.selected_item = &"potion"
	world.state.max_health = 8
	world.state.health = 2
	check(world.use_item() and world.filling_hearts, "Drinking starts the refill")
	var units: int = world.state.health_units
	var enemy = monster(load("res://content/enemies/stout_octorok.tres"), Vector2i(64, 77))
	world.combat.enemies.clear()
	world.combat.enemies.append(enemy)
	var held: Vector2i = enemy.position()
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.health_units == units + 6 and enemy.position() == held, "Hearts fill six units a frame with the game paused")
	for i in range(200): world.simulate_tick(Vector2i.ZERO)
	check(world.state.health == 8 and not world.filling_hearts and world.state.item_value(&"potion") == 1, "The refill stops at full, and a red potion becomes blue")

func check_imported(world: Node) -> void:
	# Arrows always kill Pols Voice; Darknuts shrug off the boomerang's stun.
	world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 125), Vector2i.UP)
	world.combat.enemies.clear()
	var pols = monster(load("res://imported/enemies/pols_voice.tres"), Vector2i(123, 77))
	world.combat.enemies.append(pols)
	world.state.take_item(item("bow"))
	world.state.take_item(item("arrows"))
	world.state.selected_item = &"arrows"
	world.state.rupees = 10
	world.player.facing = Vector2i.UP
	world.use_item()
	for i in range(20): world.simulate_tick(Vector2i.ZERO)
	check(pols.health == 0, "One arrow kills Pols Voice")
	var darknut = monster(load("res://imported/enemies/red_darknut.tres"), Vector2i(120, 77))
	world.combat.enemies.clear()
	world.combat.enemies.append(darknut)
	world.state.take_item(item("boomerang"))
	world.state.selected_item = &"boomerang"
	world.held_direction = Vector2i.ZERO
	world.use_item()
	for i in range(20): world.simulate_tick(Vector2i.ZERO)
	check(darknut.stun_ticks == 0, "Darknuts are never stunned")
	# The recorder drains level 7's pond and opens its stairs.
	world.state.take_item(item("recorder"))
	world.state.selected_item = &"recorder"
	world.enter_room(world.rooms[&"ow_42"], world.rooms[&"ow_42"].spawn, Vector2i.UP)
	check(world.is_blocked(Vector2i(96, 88)), "The pond starts full")
	world.use_item()
	for i in range(0x98 + 12 * 8 + 2): world.simulate_tick(Vector2i.ZERO)
	check(world.secrets.revealed and world.state.flags.get("secret/ow_42", false), "The recorder drains the pond and reveals the stairs")
	check(not world.is_blocked(Vector2i(96, 88)), "The drained pond can be walked")
	world.player.place(Vector2i(96, 77))
	world.try_portal(Vector2i.ZERO)
	check(world.room.id == world.rooms[&"l7_79"].id, "The pond stairs lead into level 7")
	# The whirlwind carries Link to a level whose triforce he holds.
	world.state.flags["triforce/3"] = true
	world.enter_room(world.rooms[&"ow_77"], Vector2i(120, 77), Vector2i.RIGHT)
	world.player.facing = Vector2i.RIGHT
	world.use_item()
	for i in range(0x98 + 2): world.simulate_tick(Vector2i.ZERO)
	check(world.room.id == &"ow_74" and world.player.pixel_position().x == 0x80, "The whirlwind sets Link down at level 3's entrance")
	completed = true
