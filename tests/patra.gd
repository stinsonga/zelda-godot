extends SceneTree
## Patra (Z_04 InitPatra, UpdatePatra, UpdatePatraChild). The native fixture
## needs no ROM; the imported checks run with a local import.
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Patra suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func fixture_room(world: Node, definition: Resource) -> Resource:
	var room: Resource = world.room.duplicate()
	room.id = &"patra_fixture"
	room.enemy_persistence = "overworld"
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"eye"
	spawn.enemy = definition
	spawn.position = Vector2i(0x80, 0x70 - 64)
	room.enemies.assign([spawn])
	world.rooms[room.id] = room
	return room

func tick(world: Node) -> void:
	world.combat.player_invulnerability = 100000
	world.simulate_tick(Vector2i.ZERO)

func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room := fixture_room(world, preload("res://content/enemies/patra.tres"))
	world.enter_room(room, Vector2i(32, 125), Vector2i.UP)
	var patra: RefCounted = world.combat.enemies[0]
	var group: RefCounted = patra.family.patra
	var children: Array = world.combat.enemies.slice(1)
	check(group is PatraGroup and children.size() == 8 and patra.slot == 1 and children[7].slot == 9, "Patra keeps slot 1 and fills slots 2-9 with children")
	check(world.combat.encounter_total == 1, "Only the parent counts for the room")
	check(not children.any(func(c: RefCounted) -> bool: return c.body_visible()), "Children start hidden")
	check(patra.facing == Vector2i.UP or patra.family.initialized == false, "Patra starts facing up")
	tick(world)
	check(group.maneuver == 1 and group.maneuver_timer == 255, "With slot 3 at angle 0 and the timer clear, the maneuver flips at once")
	check(not children[0].body_visible(), "The first update only initializes the children")
	var parent_before: Vector2i = patra.position()
	tick(world)
	check(children[0].body_visible() and children[0].family.patra_angle >> 8 == 0x18, "Slot 2 appears at angle $18 (north)")
	check(children[0].position() == parent_before - Vector2i(0, 44), "It appears its radius above the parent's last position")
	check(not children[1].body_visible(), "Later children wait for their start angle")
	var order: Array[int] = []
	for i in range(80):
		tick(world)
		for c in children:
			if c.body_visible() and c.family.patra_index not in order: order.append(c.family.patra_index)
		if group.all_shown: break
	check(order == [0, 1, 2, 3, 4, 5, 6, 7], "Children appear one at a time in slot order")
	check(group.all_shown and children.all(func(c: RefCounted) -> bool: return c.targetable()), "Every child collides once the last has appeared")
	check(not patra.targetable() and patra.can_touch_player(), "Patra cannot be hurt while children remain, but can hurt Link")
	# In maneuver 0 the children circle the parent at about their radius. (In
	# maneuver 1 child 1 moves half as far vertically, flattening the ring.)
	group.maneuver = 0
	group.maneuver_timer = 1000
	# Positions are integrated, so the ring's centre may drift from the parent.
	var ring := Rect2i(children[0].position() - patra.position(), Vector2i.ZERO)
	for i in range(80):
		tick(world)
		ring = ring.expand(children[0].position() - patra.position())
	check(absi(ring.size.x - 88) <= 6 and absi(ring.size.y - 88) <= 6, "Children circle the moving parent at their radius (%s)" % ring.size)
	# Flight: speed up to $40, then only chase and wander.
	check(patra.family.flight_speed == 64 and patra.family.phase in [1, 2, 3], "Patra flies at full speed, never resting")
	group.maneuver_timer = 0
	var flips := 0
	var last: int = group.maneuver
	for i in range(600):
		tick(world)
		check(patra.family.phase in [1, 2, 3], "Patra never slows down")
		if group.maneuver != last:
			flips += 1
			last = group.maneuver
			check(group.whole_angle(1) == 0 and group.maneuver_timer == 255, "Maneuvers switch with slot 3 at angle 0")
	check(flips >= 1 and flips <= 3, "Maneuvers switch no more often than every 255 frames (%d)" % flips)
	# Only the sword hurts the children and, once they are gone, Patra.
	var child: RefCounted = children[3]
	check(not child.receive_hit(1, Vector2i.UP, "arrow") and child.parried_hit, "Arrows do not hurt children")
	check(child.receive_hit(child.health, Vector2i.UP, "sword") and child.health == 0 and child.shove_remaining == 0, "The sword kills a child without knockback")
	for c in children:
		c.invulnerability = 0
		if c.health > 0: c.receive_hit(c.health, Vector2i.UP, "sword")
	check(patra.targetable(), "With every child gone Patra can be hurt")
	check(not patra.receive_hit(1, Vector2i.UP, "bomb"), "Bombs do not hurt Patra")
	check(patra.receive_hit(patra.health, Vector2i.UP, "beam") and patra.health == 0, "The sword beam counts as the sword")
	for i in range(30): tick(world)
	check(world.combat.encounter_kills == 1 and world.room_clear(), "Defeating Patra finishes the encounter")
	# Editable variant: fewer, slower children on a smaller orbit.
	var variant: Resource = room.enemies[0].enemy.duplicate()
	variant.patra_child_count = 3
	variant.patra_child = variant.patra_child.duplicate()
	variant.patra_child.orbit_radius = 24
	room.enemies[0].enemy = variant
	world.state.room_records.clear()
	world.combat.encounter_room = null
	world.enter_room(room, Vector2i(32, 125), Vector2i.UP)
	check(world.combat.enemies.size() == 4, "Child count is editable")
	var first: RefCounted = world.combat.enemies[1]
	var origin: Vector2i = world.combat.enemies[0].position()
	tick(world)
	origin = world.combat.enemies[0].position()
	tick(world)
	check(first.position() == origin - Vector2i(0, 24), "Orbit radius is editable")
	world.free()
	check_imported()
	print("Patra checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/enemies/patra_1.tres"): return
	var first: Resource = load("res://imported/enemies/patra_1.tres")
	var second: Resource = load("res://imported/enemies/patra_2.tres")
	check(first.patra_child.orbit_radius == 0x2C and first.patra_child.orbit_angle_step == 0x70 and first.patra_child.orbit_x_bits == PackedInt32Array([6, 6]) and first.patra_child.orbit_y_bits == PackedInt32Array([6, 5]), "Patra $47 children: wide circle, then a wobbling ring")
	check(second.patra_child.orbit_radius == 0x18 and second.patra_child.orbit_angle_step == 0x60 and second.patra_child.orbit_x_bits == PackedInt32Array([5, 6]), "Patra $48 children: small circle, then a large one")
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var found := 0
	for candidate in world.room_resources:
		if not candidate.enemies.any(func(s: Resource) -> bool: return s.enemy.behavior == "patra"): continue
		world.enter_room(candidate, candidate.spawn, Vector2i.UP)
		var patra: RefCounted = world.combat.enemies[0]
		check(patra.definition.behavior == "patra" and world.combat.enemies.size() == 9, "Imported Patra makes eight children")
		check(patra.position() == Vector2i(0x80, 0x70 - 64), "Imported Patra starts at ($80, $70)")
		for i in range(400): tick(world)
		check(patra.family.patra.all_shown, "Every imported child appears")
		found += 1
	check(found == 5, "Level 9 has five Patra rooms (%d)" % found)
	world.free()
