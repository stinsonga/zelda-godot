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
	var args := OS.get_cmdline_user_args()
	for label in ["scroll_right", "scroll_left", "scroll_up", "scroll_down"]:
		if not args.has(label): continue
		var direction := Vector2i.RIGHT
		var id: StringName = &"ow_77"
		var at := Vector2i(240, 77)
		match label:
			"scroll_left":
				id = &"ow_78"
				at = Vector2i(0, 77)
				direction = Vector2i.LEFT
			"scroll_up":
				at = Vector2i(120, -3)
				direction = Vector2i.UP
			"scroll_down":
				id = &"ow_67"
				at = Vector2i(120, 157)
				direction = Vector2i.DOWN
		world.enter_room(world.rooms[id], at, direction)
		world.try_exit(direction)
		assert(world.transition != null, "Preview exit is blocked")
		for tick in range(32 if direction.x != 0 else 22): world.simulate_tick(Vector2i.ZERO)
		world.queue_redraw()
		return
	if args.has("combat") or args.has("beam") or args.has("burst") or args.has("health") or args.has("saved"):
		world.enter_room(world.rooms[&"ow_78"], Vector2i(120, 77), Vector2i.UP)
		world.state.equipped_weapon = preload("res://content/items/wooden_sword.tres")
		world.state.health = 4
		world.state.rupees = 13
		if args.has("saved"): world.show_status("GAME SAVED")
		if args.has("health"):
			world.state.health = world.state.max_health
			world.combat.hurt_player(world, 1, Vector2i(100, 77))
		for i in range(world.combat.enemies.size()):
			var actor = world.combat.enemies[i]
			actor.spawn_remaining = 0
			actor.facing = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN][i % 4]
			actor.animation_ticks = (i % 2) * 6
		var reward = preload("res://scripts/dropped_reward.gd").new()
		reward.definition = preload("res://content/items/heart.tres")
		reward.position = Vector2i(80, 80)
		reward.age = 40
		world.combat.rewards.append(reward)
		reward = preload("res://scripts/dropped_reward.gd").new()
		reward.definition = preload("res://content/items/rupee.tres")
		reward.position = Vector2i(128, 112)
		reward.age = 40
		world.combat.rewards.append(reward)
		if args.has("beam") or args.has("burst"):
			world.state.health = 6
			world.player.place(Vector2i(120, 93))
			world.player.facing = Vector2i.RIGHT
			world.sword.start(world.state.equipped_weapon, Vector2i.RIGHT)
			world.combat.launch_beam(world)
			world.sword.phase = -1
			world.combat.beam.position = Vector2i(160, 93)
			world.simulation_tick = 1
			if args.has("burst"):
				world.combat.beam.impact()
				world.combat.beam.burst_remaining = 12
		world.queue_redraw()
		return
	world.enter_room(world.rooms[&"sword_cave"], Vector2i(112, 109), Vector2i.UP)
	world.dialogue_elapsed = 10000
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
