extends SceneTree
const Store = preload("res://scripts/save_store.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: push_error("Ladder suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func ticks(direction: Vector2i, count: int) -> void:
	for i in range(count): world.simulate_tick(direction)
func place(at: Vector2i, facing: Vector2i) -> void:
	world.ladder.reset()
	world.player.place(at)
	world.player.facing = facing
func run() -> void:
	world = preload("res://scenes/ladder_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.scroll_transitions = false
	world.save_store = Store.new(OS.get_temp_dir().path_join("zelda-ladder-%d" % OS.get_process_id()))
	check(world.room.validation_errors().is_empty(), "Authored ladder lab validates")
	place(Vector2i(64,109), Vector2i.UP)
	ticks(Vector2i.UP,40)
	check(world.player.pixel_position().y == 85 and not world.ladder.active, "Without the ladder Link stops at water")
	world.state.take_item(preload("res://content/items/ladder.tres"))
	ticks(Vector2i.UP,1)
	check(world.ladder.active and world.ladder.direction == Vector2i.UP, "Walking toward water automatically deploys upward ladder")
	check(world.ladder.anchor == Vector2i(64,77), "Upward ladder uses original eight-pixel anchor offset")
	check(not world.save_game(), "Checkpoint does not strand Link on a transient ladder")
	var at: Vector2i = world.player.pixel_position()
	ticks(Vector2i.RIGHT,12)
	check(world.player.pixel_position() == at, "Perpendicular movement cannot leave a deployed ladder")
	ticks(Vector2i.ZERO,12)
	check(world.ladder.active and world.player.pixel_position() == at, "Standing still retains the crossing")
	ticks(Vector2i.UP,25)
	check(world.player.pixel_position().y < 64 and not world.ladder.active, "Upward crossing reaches shore and puts ladder away")
	check(world.save_game() and world.load_game() and world.state.item_value(&"ladder") == 1, "Ladder ownership survives checkpoint without deployed object")
	place(Vector2i(64,61), Vector2i.DOWN)
	ticks(Vector2i.DOWN,1)
	check(world.ladder.active and world.ladder.anchor == Vector2i(64,77), "Downward deployment uses sixteen-pixel anchor offset")
	ticks(Vector2i.DOWN,26)
	check(world.player.pixel_position().y > 95 and not world.ladder.active, "Downward crossing reaches shore")
	place(Vector2i(112,37), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,1)
	check(world.ladder.active and world.ladder.anchor == Vector2i(128,37), "Rightward ladder deploys")
	ticks(Vector2i.RIGHT,25)
	check(world.player.pixel_position().x > 144 and not world.ladder.active, "Rightward crossing reaches shore")
	place(Vector2i(144,37), Vector2i.LEFT)
	ticks(Vector2i.LEFT,26)
	check(world.player.pixel_position().x < 112 and not world.ladder.active, "Leftward crossing reaches shore")
	place(Vector2i(112,37), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,7)
	ticks(Vector2i.LEFT,12)
	check(world.player.pixel_position().x < 112 and not world.ladder.active, "Link can retreat to the starting bank")
	place(Vector2i(144,117), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,50)
	check(world.player.pixel_position().x == 160 and world.ladder.active, "Ladder cannot chain across two-tile-deep water")
	ticks(Vector2i.LEFT,20)
	check(world.player.pixel_position().x < 144 and not world.ladder.active, "Deep water still allows retreat")
	world.room = world.room.duplicate(true)
	world.room.ladder_allowed = false
	place(Vector2i(112,37), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,20)
	check(world.player.pixel_position().x == 112 and not world.ladder.active, "Room can disable ladder deployment")
	world.room.ladder_allowed = true
	place(Vector2i(16,37), Vector2i.LEFT)
	ticks(Vector2i.LEFT,20)
	check(world.player.pixel_position().x == 16 and not world.ladder.active, "Ladder never bridges ordinary walls")
	var invalid = world.room.duplicate()
	invalid.ladder_water = PackedByteArray([1])
	check(not invalid.validation_errors().is_empty(), "Malformed fine water masks are rejected")
	place(Vector2i(112,37), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,1)
	world.enter_room(world.room,Vector2i(64,125),Vector2i.UP)
	check(not world.ladder.active and world.state.item_value(&"ladder") == 1, "Room entry clears deployment and retains ownership")
	var decoration = preload("res://scripts/decoration_definition.gd").new()
	decoration.blocking_area = Rect2i(128,32,16,32)
	world.room.decorations.assign([decoration])
	place(Vector2i(112,37), Vector2i.RIGHT)
	ticks(Vector2i.RIGHT,20)
	check(world.player.pixel_position().x == 112 and not world.ladder.active, "Blocking decoration over water prevents deployment")
	if ResourceLoader.exists("res://imported/deployed_ladder.png"):
		world.enter_room(load("res://imported/rooms/ow_5f.tres"),Vector2i(128,77),Vector2i.RIGHT)
		world.combat.enemies.clear()
		world.combat.player_invulnerability = 10000
		for i in range(60):
			if world.player.pixel_position().x >= 192: break
			world.simulate_tick(Vector2i.RIGHT)
		check(world.player.pixel_position().x >= 192, "Original coast reaches heart island via two separate crossings")
		world.enter_room(load("res://imported/rooms/l1_23.tres"),Vector2i(32,53),Vector2i.RIGHT)
		world.combat.enemies.clear()
		world.combat.player_invulnerability = 10000
		# 32 pixels at six frames per eight-pixel segment (MoveObject), plus slack.
		ticks(Vector2i.RIGHT,26)
		check(world.player.pixel_position().x >= 64 and not world.ladder.active, "Original dungeon F4 water supports a complete crossing")
	world.free()
	print("Ladder checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
