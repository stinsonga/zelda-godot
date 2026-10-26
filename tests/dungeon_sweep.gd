extends SceneTree
## Every dungeon room of both imported quests, entered and run briefly: each
## monster and room item has a sprite. Skips without an import.
var failures := 0

func _initialize() -> void:
	create_timer(300).timeout.connect(func() -> void: push_error("Dungeon sweep timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	if not ResourceLoader.exists("res://imported/world_q2.tres"):
		print("Dungeon sweep checks: SKIP (no local import)")
		quit(0)
		return
	for path in ["res://imported/world.tres", "res://imported/world_q2.tres"]: sweep(path)
	print("Dungeon sweep checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func has_sprite(world: Node, level: int, name: StringName) -> bool:
	var sprites: Dictionary = world.visual_theme.sprites
	return sprites.has(StringName("l%d_%s" % [level, name])) or sprites.has(name)

func sweep(path: String) -> void:
	var world = preload("res://scenes/main.tscn").instantiate()
	world.world_definition = load(path)
	root.add_child(world)
	world.set_physics_process(false)
	var ids: Array = world.rooms.keys()
	ids.sort()
	var missing := {}
	var rooms := 0
	for id in ids:
		var definition: Resource = world.rooms[id]
		if definition.dungeon_level == 0: continue
		rooms += 1
		world.enter_room(definition, definition.spawn, Vector2i.UP)
		for i in range(120):
			world.state.health = world.state.max_health
			world.simulate_tick(Vector2i.ZERO)
		for actor in world.combat.enemies:
			# Spawning monsters show only the cloud.
			if not actor.alive() or actor.definition.behavior == "native" or actor.waiting_spawn or actor.spawn_remaining > 0: continue
			var name: StringName = actor.sprite_name()
			if not has_sprite(world, definition.dungeon_level, name) and actor.body_visible(): missing["%s %s %s" % [id, name, actor.definition.behavior]] = true
		for pickup in definition.pickups:
			# Animated items are drawn from their first frame.
			var sprite: StringName = world.item_sprite(pickup.item)
			if not world.visual_theme.sprites.has(sprite) and not world.visual_theme.sprites.has(StringName(String(sprite) + "_0")): missing["%s item %s" % [id, sprite]] = true
	check(missing.is_empty(), "%s: missing sprites %s" % [world.world_id, missing.keys().slice(0, 12)])
	check(rooms > 250, "%s: %d dungeon rooms swept" % [world.world_id, rooms])
	world.free()
