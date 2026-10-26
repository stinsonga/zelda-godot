extends SceneTree
## Overworld actors outside the encounter lists: Zora (Z_04 CheckZora,
## UpdateZora) and Armos (Z_01 CheckPassiveTileObjects, Z_04
## InitArmosOrFlyingGhini, UpdateArmos), and Ghini (UpdateGhini,
## UpdateFlyingGhini). The fixtures need no ROM; the imported checks run with a
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
	check_ghini()
	check_boulders()
	check_pond_fairy()
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

func check_ghini() -> void:
	var room: Resource = statue_room("")
	room.id = &"graveyard_fixture"
	room.armos = null
	room.armos_cells = PackedVector2Array()
	room.ghost = load("res://content/enemies/lab_ghost.tres")
	room.grave_cells = PackedVector2Array([Vector2(3, 4), Vector2(9, 4)])
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"keeper"
	spawn.enemy = load("res://content/enemies/lab_ghost_keeper.tres")
	spawn.position = Vector2i(192, 125)
	spawn.spawn_ticks = 0
	room.enemies.assign([spawn])
	room.enemy_persistence = "reset"
	world.rooms[room.id] = room
	world.enter_room(room, Vector2i(48, 93), Vector2i.UP)
	for i in range(20): world.simulate_tick(Vector2i.UP)
	var ghosts: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_ghost")
	check(ghosts.size() == 1 and ghosts[0].position() == Vector2i(48, 64), "Pressing into a gravestone raises a ghost on it")
	check(world.is_blocked(Vector2i(48, 72)), "The gravestone stays")
	var ghost: RefCounted = ghosts[0]
	tick(80)
	check(ghost.position() != Vector2i(48, 64) and ghost.alive(), "The ghost flies off once faded in")
	check(not ghost.targetable() and ghost.can_touch_player(), "It cannot be struck, only touched")
	check(not ghost.receive_hit(9, Vector2i.UP, "sword"), "Weapons pass through it")
	world.player.place(Vector2i(48, 77))
	for i in range(12): world.simulate_tick(Vector2i.UP)
	check(world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_ghost").size() == 2, "Touching the stone again raises another")
	var keeper: RefCounted = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_ghost_keeper")[0]
	keeper.invulnerability = 0
	keeper.receive_hit(keeper.health, Vector2i.UP, "sword")
	tick(2)
	check(world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_ghost").all(func(a: RefCounted) -> bool: return a.health == 0), "Defeating the Ghini takes every ghost with it")

func check_boulders() -> void:
	var room: Resource = lake_room()
	room.id = &"slope_fixture"
	room.zora = null
	var rows: PackedStringArray = []
	for y in range(11): rows.append("#" + ".".repeat(14) + "#")
	room.tiles = "\n".join(rows)
	room.enemy_persistence = "reset"
	var spawns: Array = []
	for i in range(2):
		var spawn = preload("res://scripts/enemy_spawn.gd").new()
		spawn.id = StringName("slide_%d" % i)
		spawn.enemy = load("res://content/enemies/lab_rock_slide.tres")
		spawn.position = Vector2i(32 + i * 16, 29)
		spawn.spawn_ticks = 0
		spawns.append(spawn)
	room.enemies.assign(spawns)
	world.rooms[room.id] = room
	world.enter_room(room, Vector2i(48, 125), Vector2i.UP)
	var slides: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.behavior == "boulder_set")
	check(slides.size() == 2 and slides.all(func(a: RefCounted) -> bool: return not a.body_visible() and not a.targetable() and not a.can_touch_player()), "Boulder sets are invisible and untouchable")
	var most := 0
	var first_spot := Vector2i(-1, -1)
	var chase_half := -1
	var reached_bottom := false
	var tracked: RefCounted = null
	var lowest := -1
	for i in range(600):
		tick()
		var rocks: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_rock" and a.health > 0)
		most = maxi(most, rocks.size())
		if tracked == null and not rocks.is_empty():
			tracked = rocks[0]
			first_spot = tracked.position()
			chase_half = 1 if world.combat.chase_target.x >= 0x80 else 0
		if tracked != null:
			if tracked.health > 0: lowest = maxi(lowest, tracked.position().y)
			elif lowest >= 0xF0 - 64 - 4: reached_bottom = true
	check(most == 3, "At most three boulders fall at once (%d)" % most)
	# The chase target is Link or, at times, his mirror image (update_chase_target).
	check(first_spot.y == 0 and (1 if first_spot.x >= 0x80 else 0) == chase_half, "A boulder starts at the top, in the chase target's half (%s)" % first_spot)
	check(reached_bottom, "Boulders fall to the bottom and vanish (lowest %d)" % lowest)
	var falling: Array = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.id == &"lab_rock" and a.health > 0)
	check(not falling.is_empty() and falling.all(func(a: RefCounted) -> bool: return not a.targetable() and a.can_touch_player()), "Boulders hurt but cannot be struck")
	check(falling.all(func(a: RefCounted) -> bool: return a.position().x >= 0 and a.position().x <= 240), "Boulders stay within the sides")

func check_pond_fairy() -> void:
	var room: Resource = lake_room()
	room.id = &"pond_fixture"
	room.zora = null
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"fairy"
	spawn.enemy = load("res://content/enemies/lab_pond_spirit.tres")
	spawn.position = Vector2i(0x78, 0x7D - 64)
	spawn.spawn_ticks = 0
	room.enemies.assign([spawn])
	room.enemy_persistence = "reset"
	var rows: PackedStringArray = []
	for y in range(11): rows.append("#" + ".".repeat(14) + "#")
	room.tiles = "\n".join(rows)
	world.rooms[room.id] = room
	world.enter_room(room, Vector2i(48, 125), Vector2i.UP)
	var fairy: RefCounted = world.combat.enemies[0]
	world.state.health_units = world.state.HEALTH_UNITS
	tick(10)
	check(fairy.family.pond_phase == 0 and not fairy.targetable() and not fairy.can_touch_player(), "The fairy waits, neither struck nor harmful")
	world.player.place(Vector2i(0x78, 0xAD - 64))
	var before: int = world.state.health_units
	world.simulate_tick(Vector2i.ZERO)
	world.simulate_tick(Vector2i.LEFT)
	check(fairy.family.pond_phase == 1 and world.combat.holds_player() and world.player.pixel_position() == Vector2i(0x78, 0xAD - 64), "At the pond's edge Link is held")
	check(world.state.health_units == before + 6, "Hearts refill six units a frame (%d)" % (world.state.health_units - before))
	var most := 0
	var frames := 0
	while fairy.family.pond_phase == 1 and frames < 2000:
		world.simulate_tick(Vector2i.ZERO)
		frames += 1
		most = maxi(most, fairy.family.hearts.filter(func(h: Array) -> bool: return h[0] == 1).size())
	check(world.state.health_units == world.state.max_health * world.state.HEALTH_UNITS, "Every heart is restored")
	check(most == 8, "Eight hearts circle the fairy (%d)" % most)
	var first: Array = fairy.family.hearts[0]
	var gap := Vector2(floori(first[2].x / 256.0), floori(first[2].y / 256.0)) - Vector2(fairy.position())
	# They start $1C above her; a $60 step with six bits draws a ring about 54
	# pixels in radius that is centred below her, toward Link.
	check(gap.length() > 8 and gap.length() < 100, "They circle near her (%.1f)" % gap.length())
	var linger := 0
	while world.combat.holds_player() and linger < 200:
		world.simulate_tick(Vector2i.ZERO)
		linger += 1
	check(linger >= 0x4F and linger <= 0x51, "Link stays $50 frames more (%d)" % linger)
	world.state.health_units = world.state.HEALTH_UNITS
	world.player.place(Vector2i(0x78, 0xAD - 64))
	tick(5)
	check(world.state.health_units == world.state.HEALTH_UNITS and fairy.family.pond_phase == 3, "She helps once a visit")

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
	var graveyard: Resource = world.rooms[&"ow_21"]
	var slopes: Array = world.room_resources.filter(func(r: Resource) -> bool: return r.enemies.any(func(e: Resource) -> bool: return e.enemy.behavior == "boulder_set"))
	var ponds: Array = world.room_resources.filter(func(r: Resource) -> bool: return r.enemies.any(func(e: Resource) -> bool: return e.enemy.behavior == "pond_fairy"))
	check(ponds.size() == 2 and ponds.all(func(r: Resource) -> bool: return r.enemies[0].position == Vector2i(0x78, 0x7D - 64)), "Two ponds hold a fairy at ($78, $7D)")
	check(ponds.all(func(r: Resource) -> bool: return not r.is_pixel_solid(Vector2i(0x78, 0xAD - 64 + 11))), "Link can reach each pond's edge")
	check(slopes.size() == 6 and slopes[0].enemies[0].enemy.spawns.id == &"boulder", "Six rooms drop boulders")
	check(graveyard.grave_cells.size() == 12 and graveyard.ghost.untouchable and graveyard.enemies.any(func(s: Resource) -> bool: return s.enemy.defeat_takes == &"flying_ghini"), "Graveyards hold the Ghini and twelve stones of ghosts")
	world.free()
