extends SceneTree
## PlayerController.move_frame against positions captured from the original
## (tools/movement_trace.py: walk_stop, reverse_stop, turn_mid_segment). ROM-free.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func controller(facing: Vector2i) -> RefCounted:
	var player = preload("res://scripts/player.gd").new()
	player.grid_origin = Vector2i(0, 5)
	player.place(Vector2i(120, 77))
	player.facing = facing
	return player

func walk(player: RefCounted, inputs: Array) -> Array:
	var open := func(_at: Vector2i, _direction: Vector2i) -> bool: return true
	var positions: Array = []
	for input in inputs:
		player.move_frame(input, open)
		positions.append(player.pixel_position())
	return positions

func run() -> void:
	# Right from a grid point: +1, +2 alternately, and the frame reaching x 128
	# stops there (grid offset +8) with the fraction at 0.
	var right := controller(Vector2i.UP)
	var xs := walk(right, filled(Vector2i.RIGHT, 12)).map(func(p: Vector2i) -> int: return p.x)
	check(xs == [121, 123, 124, 126, 127, 128, 129, 131, 132, 134, 135, 136], "Right: six frames per segment, stopping on grid points (%s)" % [xs])
	check(right.fraction == 0, "The frame that reaches a grid point keeps accumulating the fraction")
	# Left: the fraction runs downward, and x 104 holds fraction $80.
	var left := controller(Vector2i.UP)
	xs = walk(left, filled(Vector2i.LEFT, 12)).map(func(p: Vector2i) -> int: return p.x)
	check(xs == [118, 117, 115, 114, 112, 111, 109, 108, 106, 105, 104, 103], "Left matches the original (%s)" % [xs])
	# A perpendicular press past halfway keeps Link going to the grid point; he
	# turns on the next frame, carrying the shared fraction.
	var turn := controller(Vector2i.UP)
	var path := walk(turn, filled(Vector2i.RIGHT, 5) + filled(Vector2i.UP, 5) + filled(Vector2i.LEFT, 2))
	check(path[5] == Vector2i(128, 77) and turn.facing == Vector2i.LEFT, "The turn waits for the grid point")
	check(path.slice(5, 11) == [Vector2i(128, 77), Vector2i(128, 75), Vector2i(128, 74), Vector2i(128, 72), Vector2i(128, 71), Vector2i(128, 69)],
		"Then Link moves up, and the left press waits for the next grid point (%s)" % [path.slice(5, 11)])
	# taps: after reversing at x 127.5, the grid offset still counts from x 120, so a
	# perpendicular press at offset 6 keeps Link going left (not to the nearer point).
	var taps := controller(Vector2i.UP)
	var inputs: Array = [Vector2i.RIGHT, Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ZERO, Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ZERO,
		Vector2i.UP, Vector2i.ZERO, Vector2i.UP, Vector2i.LEFT, Vector2i.ZERO, Vector2i.ZERO, Vector2i.ZERO, Vector2i.DOWN, Vector2i.DOWN]
	var tapped := walk(taps, inputs)
	check(tapped[10] == Vector2i(126, 77) and tapped[14] == Vector2i(124, 77) and tapped[15] == Vector2i(123, 77) and taps.facing == Vector2i.LEFT,
		"A perpendicular press past halfway keeps the reversed direction (%s)" % [tapped.slice(10)])
	check(taps.grid_offset == 3, "The offset is kept across stops and reversals (%d)" % taps.grid_offset)
	# Z_05 InitLinkSpeed: on mountain stairs the quarter speed is $30, 0.75 pixels a frame.
	var climbing := controller(Vector2i.UP)
	var on_stairs := func(_at: Vector2i, _direction: Vector2i) -> bool: return true
	var open := func(_at: Vector2i, _direction: Vector2i) -> bool: return true
	var ys: Array = []
	for i in range(8):
		climbing.move_frame(Vector2i.UP, open, on_stairs)
		ys.append(climbing.pixel_position().y)
	# Moving up subtracts $30 four times from fraction 0, so the first step borrows at once.
	check(climbing.quarter_speed == 0x30 and ys == [76, 75, 74, 74, 73, 72, 71, 71], "Stairs halve Link's speed (%s)" % [ys])
	check_imported_stairs()
	print("Movement frame checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func filled(value: Vector2i, count: int) -> Array:
	var result: Array = []
	for i in range(count): result.append(value)
	return result

## Room $0E's waterfall is mountain stairs: climbing them takes twice as long.
func check_imported_stairs() -> void:
	if not ResourceLoader.exists("res://imported/rooms/ow_0e.tres"): return
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.enter_room(world.rooms[&"ow_0e"], Vector2i(80, 157), Vector2i.UP)
	world.combat.enemies.clear()
	var frames := 0
	while world.player.pixel_position().y > 141 and frames < 100:
		world.simulate_tick(Vector2i.UP)
		frames += 1
	check(frames >= 20 and frames <= 23, "Sixteen pixels of stairs take about 21 frames (%d)" % frames)
	world.free()
