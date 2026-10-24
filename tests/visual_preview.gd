extends SceneTree
## Render deterministic cave, lifting, or sword views for screenshot review.
func _initialize() -> void:
	call_deferred("preview")

func preview() -> void:
	var world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	if not world.rooms.has(&"sword_cave"):
		push_error("Visual previews require a local ROM import")
		quit(1)
		return
	world.enter_room(world.rooms[&"sword_cave"], Vector2i(112, 109), Vector2i.UP)
	world.dialogue_elapsed = 10000
	var args := OS.get_cmdline_user_args()
	if args.has("lift") or args.has("sword"):
		world.player.place(Vector2i(120, 93))
		world.try_pickups()
	if args.has("sword"):
		world.lift_remaining = 0
		world.simulation_tick = 100
		world.player.facing = Vector2i.RIGHT
		world.sword.start(world.state.equipped_weapon, Vector2i.RIGHT)
		for tick in range(5): world.sword.tick()
	world.queue_redraw()
