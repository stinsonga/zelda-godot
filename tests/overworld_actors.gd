extends SceneTree
## Overworld actors outside the encounter lists: Zora (Z_04 CheckZora,
## UpdateZora) and Armos (Z_01 CheckPassiveTileObjects, Z_04
## InitArmosOrFlyingGhini, UpdateArmos). The fixtures need no ROM; the imported checks run with a
## local import.
var failures := 0
var world: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Overworld actors suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func tick(count := 1) -> void:
	for i in range(count):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)

func zora() -> RefCounted:
	var found: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.behavior == "zora" and a.health > 0)
	return found[0] if not found.is_empty() else null

func run() -> void:
	world = preload("res://scenes/item_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_zora()
	check_armos()
	world.free()
	check_imported()
	print("Overworld actor checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func lake_room() -> Resource:
	var room: Resource = world.rooms[&"lab_grove"].duplicate()
	room.id = &"lake_fixture"
	var rows: PackedStringArray = []
	for y in range(11): rows.append("#" + ("~".repeat(14) if y >= 3 and y <= 8 else ".".repeat(14)) + "#")
	room.tiles = "\n".join(rows)
	room.tile_atlas = null
	room.tile_indices = PackedInt32Array()
	room.collision_tiles = PackedByteArray()
	room.ladder_water = PackedByteArray()
	room.secret = null
	room.portals = Array([], TYPE_OBJECT, "Resource", null)
	room.enemies = Array([], TYPE_OBJECT, "Resource", null)
	room.zora = load("res://content/enemies/lab_lurker.tres")
	world.rooms[room.id] = room
	return room

func check_zora() -> void:
	var room := lake_room()
	world.enter_room(room, Vector2i(120, 13), Vector2i.UP)
	var first: RefCounted = null
	for i in range(30):
		tick()
		first = zora()
		if first != null: break
	check(first != null, "A Zora rises in a water room")
	if first == null: return
	var at: Vector2i = first.position()
	check(at.x % 16 == 0 and (at.y + 64) % 16 == 0x0D and room.is_ladder_water(at + Vector2i(0, 0x0B)), "It surfaces on a $10-aligned water spot (%s)" % at)
	check(first.family.phase == 0 or first.family.phase == 1, "It starts as a ripple")
	# Ripple $20, surfaced $0F, then state 3 shoots two frames in.
	var phases: Array = []
	var shot_at := -1
	for i in range(0x20 + 0x0F + 3):
		var rocks: int = world.combat.rocks.size()
		tick()
		if first.family.phase not in phases: phases.append(first.family.phase)
		if world.combat.rocks.size() > rocks and shot_at < 0: shot_at = i
	check(phases == [1, 2, 3], "Ripple, then surfaced (%s)" % [phases])
	check(shot_at >= 0 and first.family.timer <= 0x20, "A fireball leaves early in state 3, and the timer drops to $20")
	check(first.targetable() and first.can_touch_player(), "Surfaced, it can be struck and hurts")
	# Let it finish: state 4, sinking, then gone and replaced.
	for i in range(0x20 + 0x10 + 0x60 + 2):
		tick()
		if first.family.zora_gone: break
	tick()
	var second: RefCounted = zora()
	check(first.family.zora_gone and second != null and second != first, "Sinking ends it and another rises at once")
	# A killed Zora stays dead until the room is entered again.
	while second.family.phase not in [2, 3, 4]: tick()
	second.invulnerability = 0
	second.receive_hit(second.health, Vector2i.UP, "sword")
	tick(120)
	check(zora() == null, "A killed Zora does not come back")
	world.enter_room(world.rooms[&"item_lab"], Vector2i(120, 125), Vector2i.UP)
	world.enter_room(room, Vector2i(120, 13), Vector2i.UP)
	tick(5)
	check(zora() != null, "Re-entering raises a Zora again")
	# The clock holds it still.
	var held: RefCounted = zora()
	var phase: int = held.family.phase
	var left: int = held.family.timer
	world.state.clock_active = true
	tick(40)
	# Object timers still count down globally; the Zora's own update does not run.
	check(held.family.phase == phase and held.family.timer <= left, "The clock freezes it")
	world.state.clock_active = false

func statue_room(secret_kind: String) -> Resource:
	var room: Resource = lake_room()
	room.id = StringName("statue_fixture_" + secret_kind)
	room.zora = null
	var rows: PackedStringArray = []
	for y in range(11): rows.append("#" + ("..#.....#....." if y == 4 else ".".repeat(14)) + "#")
	room.tiles = "\n".join(rows)
	room.armos = load("res://content/enemies/lab_statue.tres")
	room.armos_cells = PackedVector2Array([Vector2(3, 4), Vector2(9, 4)])
	room.armos_floor_tiles = PackedInt32Array([-1, -1])
	room.pickups = Array([], TYPE_OBJECT, "Resource", null)
	if secret_kind != "":
		var secret = preload("res://scripts/secret_definition.gd").new()
		secret.trigger = "armos"
		secret.cell = Vector2i(9, 4)
		secret.reveal_cell = Vector2i(9, 4)
		secret.reveal_kind = secret_kind
		secret.persistent = false
		room.secret = secret
		if secret_kind == "item":
			var pickup = preload("res://scripts/pickup_definition.gd").new()
			pickup.id = &"item"
			pickup.item = load("res://content/items/power_bracelet.tres")
			pickup.position = Vector2i(144, 61)
			pickup.tolerance = Vector2i(8, 8)
			pickup.lift_ticks = 0
			pickup.requires_secret = true
			room.pickups.assign([pickup])
	world.rooms[room.id] = room
	return room

func statue() -> RefCounted:
	var found: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_statue" and a.health > 0)
	return found[0] if not found.is_empty() else null

func check_armos() -> void:
	var room := statue_room("")
	world.enter_room(room, Vector2i(48, 93), Vector2i.UP)
	check(world.is_blocked(Vector2i(48, 72)), "A statue square is solid")
	for i in range(20): world.simulate_tick(Vector2i.UP)
	var armos: RefCounted = statue()
	check(armos != null and armos.position() == Vector2i(48, 64), "Pressing into the statue wakes it on its square")
	if armos == null: return
	check(not armos.targetable() and armos.can_touch_player(), "Fading in, it hurts but cannot be struck")
	var shown := 0
	for i in range(10):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)
		if armos.body_visible(): shown += 1
	check(shown == 5, "It is drawn every other frame while fading in (%d)" % shown)
	check(world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_statue").size() == 1, "Pushing on does not wake a second one")
	while armos.wake_remaining > 0: tick()
	check(armos.targetable() and armos.facing == Vector2i.DOWN and armos.source.move_speed in [128, 384], "Then it walks, down first, at one of two speeds")
	check(not world.is_blocked(Vector2i(48, 72)), "Its square turns to floor")
	tick(30)
	check(armos.position() != Vector2i(48, 64), "It walks away")
	world.enter_room(world.rooms[&"item_lab"], Vector2i(120, 125), Vector2i.UP)
	world.enter_room(room, Vector2i(48, 93), Vector2i.UP)
	check(statue() == null and world.is_blocked(Vector2i(48, 72)), "Re-entering restores the statues")
	# A secret Armos reveals stairs; the bracelet room reveals its item.
	var stairs := statue_room("entrance")
	world.enter_room(stairs, Vector2i(144, 93), Vector2i.UP)
	for i in range(20): world.simulate_tick(Vector2i.UP)
	tick(70)
	check(world.secrets.revealed and world.overrides.get(Vector2i(9, 4), [0, 0, ""])[2] == "entrance", "The secret Armos leaves stairs")
	var bracelet := statue_room("item")
	world.enter_room(bracelet, Vector2i(144, 93), Vector2i.UP)
	check(not world.room.pickups.is_empty() and world.state.item_value(&"bracelet") == 0, "The item waits under its Armos")
	for i in range(20): world.simulate_tick(Vector2i.UP)
	tick(70)
	world.player.place(Vector2i(144, 64))
	tick()
	check(world.state.item_value(&"bracelet") == 1, "Once it wakes, the item can be taken")

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/enemies/zora.tres"): return
	world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var lakes: Array = world.room_resources.filter(func(r: Resource) -> bool: return r.zora != null)
	check(lakes.size() == 37, "37 overworld rooms raise a Zora (%d)" % lakes.size())
	world.enter_room(lakes[0], lakes[0].spawn, Vector2i.UP)
	var raised := false
	for i in range(200):
		tick()
		var found: RefCounted = zora()
		if found != null:
			raised = lakes[0].is_ladder_water(found.position() + Vector2i(0, 0x0B))
			break
	check(raised, "An imported lake raises its Zora on water")
	var armos_rooms: Array = world.room_resources.filter(func(r: Resource) -> bool: return not r.armos_cells.is_empty())
	check(armos_rooms.size() == 12 and armos_rooms.map(func(r: Resource) -> int: return r.armos_cells.size()).reduce(func(a: int, b: int) -> int: return a + b) == 90, "Twelve rooms hold the 90 Armos statues")
	var bracelet_room: Resource = world.rooms[&"ow_24"]
	check(bracelet_room.secret.trigger == "armos" and bracelet_room.pickups[0].item.id == &"power_bracelet", "Room $24 hides the power bracelet under an Armos")
	var cave_room: Resource = world.rooms[&"ow_1c"]
	check(cave_room.portals.any(func(p: Resource) -> bool: return p.target_room == &"cave_1c" and p.requires_secret), "Room $1C's Armos hides a cave")
	world.free()
