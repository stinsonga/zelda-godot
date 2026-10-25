extends SceneTree
## Lanmola chains (Z_04 InitLamnola, UpdateLamnola). The native fixture needs no
## ROM; the imported checks run with a local import.
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Lanmola suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func fixture_room(world: Node, definition: Resource, at: Vector2i) -> Resource:
	var room: Resource = world.room.duplicate()
	room.id = &"lanmola_fixture"
	room.enemy_persistence = "overworld"
	room.persistence_enemy_count = 8
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"worms"
	spawn.enemy = definition
	spawn.position = at
	room.enemies.assign([spawn])
	world.rooms[room.id] = room
	return room

func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room := fixture_room(world, preload("res://content/enemies/lanmola.tres"), Vector2i(0x40, 0x8D - 64))
	world.enter_room(room, Vector2i(208, 125), Vector2i.UP)
	var owner: RefCounted = world.combat.enemies.back()
	var group: RefCounted = owner.family.moldorm
	check(group is LanmolaGroup and group.chains.size() == 2 and world.combat.enemies.size() == 11, "Lanmola makes two five-segment chains")
	var head: RefCounted = group.chains[0].back().get_ref()
	var neck: RefCounted = group.chains[0][3].get_ref()
	var tail: RefCounted = group.chains[0][0].get_ref()
	check(head.facing == Vector2i.UP and neck.facing == Vector2i.ZERO and not tail.body_visible(), "Heads start upward while the body waits")
	world.combat.player_invulnerability = 100000
	world.simulate_tick(Vector2i.ZERO)
	check(head.position() == Vector2i(0x40, 0x8D - 64 - 2), "Heads move chain_speed pixels a frame")
	for i in range(3): world.simulate_tick(Vector2i.ZERO)
	check(neck.facing != Vector2i.ZERO and group.chains[0][2].get_ref().facing == Vector2i.ZERO, "Each eight pixels pass the head's direction one segment back")
	var previous: Vector2i = head.facing
	var reversed := false
	var turned_off_square := false
	for i in range(400):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)
		if head.facing != previous:
			if head.facing == -previous: reversed = true
			var at: Vector2i = head.position()
			if at.x % 16 != 0 or (at.y + 64 + 3) % 16 != 0: turned_off_square = true
			previous = head.facing
	check(not reversed, "Heads never reverse")
	check(not turned_off_square, "Heads turn only on squares")
	check(tail.facing != Vector2i.ZERO, "Directions eventually reach the tail")
	# A lethal hit kills the tail in the hit segment's place.
	var middle: RefCounted = group.chains[1][2].get_ref()
	var middle_tail: RefCounted = group.chains[1][0].get_ref()
	var spot: Vector2i = middle.position()
	middle.invulnerability = 0
	middle.receive_hit(middle.health, Vector2i.RIGHT, "sword")
	check(middle.health == 2 and middle_tail.health == 0 and middle_tail.position() == spot, "The tail dies where the hit segment was, which revives")
	for chain in group.chains:
		for weak in chain:
			var part = weak.get_ref()
			if part != null: part.health = 0
	world.simulate_tick(Vector2i.ZERO)
	check(owner.health == 0, "With every segment gone the Lanmola is defeated")
	check_imported()
	print("Lanmola checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/enemies/red_lanmola.tres"): return
	check(load("res://imported/enemies/red_lanmola.tres").chain_speed == 1 and load("res://imported/enemies/blue_lanmola.tres").chain_speed == 2, "Lanmola speed is its type minus $39")
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.enter_room(world.rooms[&"l9_11"], Vector2i(32, 77), Vector2i.RIGHT)
	var heads: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.behavior == "moldorm_segment" and a.family.moldorm_is_head)
	check(heads.size() == 2 and heads.all(func(a: RefCounted) -> bool: return a.position() == Vector2i(0x40, 0x8D - 64)), "Imported Lanmolas start at ($40, $8D)")
	check(world.room.persistence_enemy_count == 8, "Lanmola rooms remember at most eight kills")
	world.free()
