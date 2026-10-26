extends SceneTree
## Can a game be finished? From the start with nothing, walk Link's 8-pixel grid
## through every room with the world's own collision, opening what the items
## held allow, collecting room items and cave wares, until nothing new is found.
## Then every treasure, Triforce piece, and Zelda must have been reached.
##
## Approximations: key counts are not modeled (key doors open); the ladder
## crosses any water the room allows it on; mazes don't repeat; shops cost nothing.
## Skips without an import.
const ROOM_SIZE := Vector2i(241, 161)
const TREASURES := [&"wooden_sword", &"bow", &"raft", &"ladder", &"recorder", &"magic_rod", &"book", &"red_candle", &"silver_arrows",
	&"magic_key", &"red_ring", &"boomerang", &"magical_boomerang", &"power_bracelet", &"triforce_of_power", &"bombs", &"arrows", &"bait"]
## Monsters that need more than a sword: Z_04 UpdateGohma (arrows), UpdateDigdogger
## (recorder), UpdateDodongo (bombs), Ganon (silver arrows).
const BOSS_NEEDS := {"gohma": [&"bow", &"arrows"], "digdogger": [&"recorder"], "dodongo": [&"bombs"], "ganon": [&"bow", &"silver_arrows"]}
const TRIGGER_NEEDS := {"bomb": [&"bombs"], "fire": [&"candle"], "recorder": [&"recorder"], "bracelet_push": [&"power_bracelet"]}
var failures := 0
var world: Node
var items := {}
var grids := {}

func _initialize() -> void:
	create_timer(900).timeout.connect(func() -> void: push_error("Reachability suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	if not ResourceLoader.exists("res://imported/world_q2.tres"):
		print("Reachability checks: SKIP (no local import)")
		quit(0)
		return
	for path in ["res://imported/world.tres", "res://imported/world_q2.tres"]: solve(path)
	print("Reachability checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func has(names: Array) -> bool:
	return names.all(func(name: StringName) -> bool: return items.has(name))

## Whether everything in a room can be beaten with what Link holds.
func clearable(definition: Resource) -> bool:
	if definition.enemies.is_empty(): return true
	if not items.has(&"wooden_sword"): return false
	for spawn in definition.enemies:
		if not has(BOSS_NEEDS.get(spawn.enemy.behavior, [])): return false
	return true

func secret_open(definition: Resource) -> bool:
	if definition.secret == null: return false
	if definition.secret.trigger == "block" and not clearable(definition): return false
	return has(TRIGGER_NEEDS.get(definition.secret.trigger, []))

## Sets the room up as the solver allows and returns its standable grid points.
func open_grid(definition: Resource) -> Dictionary:
	world.room = definition
	var state: RefCounted = world.state
	state.flags.clear()
	if secret_open(definition): state.flags[world.secrets.flag_key(definition)] = true
	for door in definition.doors:
		if door.kind == "key" or (door.kind == "bombable" and items.has(&"bombs")):
			state.flags[world.door_key(definition, door.direction)] = true
	# The Triforce gate opens for all eight pieces; a hungry Goriya for bait.
	var gated: bool = definition.cave != null and ((definition.cave.triforce_gate and triforces() < 8) or (definition.cave.accepts_bait and not items.has(&"bait")))
	if clearable(definition) and not gated: state.flags["shutters/" + String(definition.id)] = true
	world.overrides = world.compute_overrides(definition)
	# A pushed block, rock, or gravestone leaves its cell once it may be moved.
	if definition.secret != null and definition.secret.trigger in ["block", "push", "bracelet_push"] and secret_open(definition):
		world.overrides[definition.secret.cell] = [definition.secret.floor_tile, PackedByteArray([0, 0, 0, 0]), "floor"]
	# Each grid point's open directions, by the world's leading-edge probes
	# (Z_07 GetCollidableTile); the ladder lets them over water it may span.
	var ladder: bool = items.has(&"ladder") and definition.ladder_allowed
	var grid := {}
	for y in range(-3, ROOM_SIZE.y, 8):
		for x in range(0, ROOM_SIZE.x, 8):
			var at := Vector2i(x, y)
			var open: Array[Vector2i] = []
			for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
				var target: Vector2i = at + direction * 8
				if target.x < 0 or target.x > 240 or target.y < -3 or target.y > 157: continue
				if world.movement_probes(at, direction).all(func(probe: Vector2i) -> bool: return not world.is_blocked(probe) or (ladder and world.ladder_water_at(probe))):
					open.append(direction)
			grid[at] = open
	return grid

func triforces() -> int:
	var count := 0
	for level in range(1, 9):
		if items.has(StringName("triforce/%d" % level)): count += 1
	return count

func take(item: Resource, definition: Resource) -> bool:
	var name: StringName = item.id
	if name == &"triforce": name = StringName("triforce/%d" % definition.dungeon_level)
	if name in [&"blue_candle", &"red_candle"]: items[&"candle"] = true
	if items.has(name): return false
	items[name] = true
	return true

func solve(path: String) -> void:
	world = preload("res://scenes/main.tscn").instantiate()
	world.world_definition = load(path)
	root.add_child(world)
	world.set_physics_process(false)
	items = {}
	var start: Resource = world.start_room
	var reached := {}
	var found := true
	var passes := 0
	while found and passes < 40:
		found = false
		passes += 1
		grids.clear()
		reached.clear()
		var pending: Array = [[start.id, start.spawn]]
		while not pending.is_empty():
			var entry: Array = pending.pop_back()
			var id: StringName = entry[0]
			var definition: Resource = world.rooms[id]
			if not grids.has(id): grids[id] = open_grid(definition)
			var grid: Dictionary = grids[id]
			var at: Vector2i = snap(entry[1])
			var seen: Dictionary = reached.get_or_add(id, {})
			if seen.has(at): continue
			# Flood the room from this point.
			var queue: Array[Vector2i] = [at]
			seen[at] = true
			var fresh: Array[Vector2i] = []
			while not queue.is_empty():
				var p: Vector2i = queue.pop_back()
				fresh.append(p)
				for direction in grid[p]:
					var q: Vector2i = p + direction * 8
					if not seen.has(q):
						seen[q] = true
						queue.append(q)
			for p in fresh: pending += leave(definition, p)
			if definition.cave != null and (not definition.cave.requires_letter or items.has(&"letter")):
				for ware in definition.cave.wares:
					if ware != null and take(ware.item, definition): found = true
			for pickup in definition.pickups:
				if pickup.requires_secret and not secret_open(definition): continue
				if pickup.requires_clear and not clearable(definition): continue
				var spot: Vector2i = world.pickup_position(pickup)
				if fresh.any(func(p: Vector2i) -> bool: return absi(p.x - spot.x) < 9 + 8 and absi(p.y - spot.y) < 9 + 8):
					if take(pickup.item, definition): found = true
	var missing: Array = TREASURES.filter(func(name: StringName) -> bool: return not items.has(name))
	check(missing.is_empty(), "%s: treasures out of reach: %s" % [world.world_id, missing])
	check(triforces() == 8, "%s: %d Triforce pieces reachable" % [world.world_id, triforces()])
	var zelda := false
	for id in reached:
		if world.rooms[id].enemies.any(func(spawn: Resource) -> bool: return spawn.enemy.behavior == "zelda"): zelda = true
	check(zelda, "%s: Zelda's room is out of reach" % world.world_id)
	# Unresolved (docs/STATUS.md): room $0F and its cave have no way in. The original's
	# own layout routine gives the same tiles, so this appears to be faithful.
	var unreached: Array = world.rooms.keys().filter(func(id: StringName) -> bool: return not reached.has(id)).map(func(id: StringName) -> String: return String(id))
	unreached.sort()
	check(unreached == ["cave_0f", "ow_0f"], "%s: unreachable rooms %s" % [world.world_id, unreached])
	print("%s: %d rooms reached in %d passes, %d items" % [world.world_id, reached.size(), passes, items.size()])
	if OS.get_environment("REACH_DEBUG") != "":
		var per_level := {}
		var totals := {}
		for id in world.rooms:
			var level: int = world.rooms[id].dungeon_level
			totals[level] = totals.get(level, 0) + 1
			if reached.has(id): per_level[level] = per_level.get(level, 0) + 1
		print("  reached per level ", per_level, " of ", totals)
		for id in reached:
			for pickup in world.rooms[id].pickups:
				if not items.has(pickup.item.id) and pickup.item.id != &"triforce": print("  untaken ", id, " ", pickup.item.id, " clear=", pickup.requires_clear, " secret=", pickup.requires_secret)
		print("  items ", items.keys())
		print("  unreached ", world.rooms.keys().filter(func(id: StringName) -> bool: return not reached.has(id)))
	world.free()

func snap(at: Vector2i) -> Vector2i:
	return Vector2i(clampi(roundi(at.x / 8.0) * 8, 0, 240), clampi(roundi((at.y + 3) / 8.0) * 8 - 3, -3, 157))

## Where Link can go from a standable point: room edges, portals, and the raft.
func leave(definition: Resource, p: Vector2i) -> Array:
	var out: Array = []
	var edges := {"left": p.x == 0, "right": p.x == 240, "up": p.y == -3, "down": p.y == 157}
	for edge in edges:
		if not edges[edge] or not definition.exits.has(edge): continue
		var destination := p
		match edge:
			"left": destination.x = 240
			"right": destination.x = 0
			"up": destination.y = 157
			"down": destination.y = -3
		out.append([StringName(definition.exits[edge]), destination])
	for portal in definition.portals:
		if portal.requires_secret and not secret_open(definition): continue
		var area: Rect2i = portal.area
		if Rect2i(area.position - Vector2i(4, 4), area.size + Vector2i(8, 8)).has_point(p):
			out.append([portal.target_room, portal.target_position])
	if definition.raft_route != null and items.has(&"raft") and p.distance_to(definition.raft_route.dock_position) < 12 and definition.exits.has("up"):
		out.append([StringName(definition.exits["up"]), definition.raft_route.landing_position])
	return out
