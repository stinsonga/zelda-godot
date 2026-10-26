extends SceneTree

const Player = preload("res://scripts/player.gd")
const Main = preload("res://scenes/main.tscn")
var failures := 0
var combat_checks_completed := false
var cave_checks_completed := false
var reward_checks_completed := false
var encounter_checks_completed := false
var beam_checks_completed := false
var scroll_checks_completed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var player = Player.new()
	player.place(Vector2i(0, 0))
	for tick in range(60):
		player.step(Vector2i.RIGHT, func(_at: Vector2i) -> bool: return true)
	check(player.pixel_position() == Vector2i(90, 0), "Normal speed must be 90 pixels over 60 ticks")
	player.place(Vector2i(0, 0))
	for tick in range(20):
		player.step(Vector2i.RIGHT, func(at: Vector2i) -> bool: return at.x < 8)
	check(player.pixel_position().x == 7, "Collision must prevent crossing a blocked coordinate")
	player.place(Vector2i(0, 0))
	player.step(Vector2i.RIGHT, func(_at: Vector2i) -> bool: return true)
	for tick in range(8):
		player.step(Vector2i.DOWN, func(_at: Vector2i) -> bool: return true)
	check(player.pixel_position().x == 0 and player.pixel_position().y > 0, "Early turn must return to the nearer grid boundary")
	var world = Main.instantiate()
	world.use_imported_world = false
	world.scroll_transitions = false
	root.add_child(world)
	world.set_physics_process(false)
	check(world.can_occupy(Vector2i(120, 96)), "Room spawn must be walkable")
	check(not world.can_occupy(Vector2i(0, 0)), "Wall must block the player")
	world.player.place(Vector2i(240, 80))
	world.try_exit(Vector2i.RIGHT)
	check(world.room.id == &"expansion_field", "East exit must load the custom room")
	check(world.player.pixel_position() == Vector2i(0, 80), "Exit must preserve the matching edge coordinate")
	world.try_exit(Vector2i.LEFT)
	check(world.room.id == &"test_field", "Return exit must load the first room")
	world.player.place(Vector2i(120, 96))
	world.try_exit(Vector2i.RIGHT)
	check(world.room.id == &"test_field", "An exit must not trigger inside a room")
	# A 16-pixel gap between bushes, with a wall across its far end.
	# The old continuous rectangle could stop off-grid and lock a turn.
	var corridor = preload("res://scripts/room_definition.gd").new()
	corridor.id = &"collision_fixture"
	corridor.tiles = "\n".join(PackedStringArray([
		"................", "................", "................",
		"................", "................", "................",
		"................", "................", "................",
		"................", "................"]))
	corridor.grid_origin = Vector2i(0, 5)
	corridor.movement_bounds = Rect2i(0, -3, 241, 161)
	corridor.collision_tiles.resize(704)
	for y in range(6, 14):
		for x in [8, 9, 12, 13]:
			corridor.collision_tiles[y * 32 + x] = 1
	for x in range(32):
		corridor.collision_tiles[16 * 32 + x] = 1
	world.room = corridor
	world.player.grid_origin = corridor.grid_origin
	world.player.facing = Vector2i.DOWN
	world.player.place(Vector2i(80, 29))
	for tick in range(100):
		world.player.step(Vector2i.DOWN, world.can_occupy, world.can_enter_segment)
	check(world.player.pixel_position() == Vector2i(80, 109), "Bush passage must stay traversable and stop on-grid at its end")
	for tick in range(20):
		world.player.step(Vector2i.RIGHT, world.can_occupy, world.can_enter_segment)
	check(world.player.pixel_position() == Vector2i(110, 109), "Player must turn freely after reaching a blocked segment")
	world.player.place(Vector2i(80, 77))
	for direction in [Vector2i.LEFT, Vector2i.RIGHT]:
		world.player.facing = direction
		for tick in range(10):
			world.player.step(direction, world.can_occupy, world.can_enter_segment)
		check(world.player.pixel_position() == Vector2i(80, 77), "Side bushes must remain solid")
	world.player.facing = Vector2i.UP
	for tick in range(32):
		world.player.step(Vector2i.UP, world.can_occupy, world.can_enter_segment)
	check(world.player.pixel_position() == Vector2i(80, 29), "Player must be able to back out of a narrow bush passage")
	world.player.place(Vector2i(80, 29))
	world.player.facing = Vector2i.RIGHT
	world.player.step(Vector2i.RIGHT, world.can_occupy, world.can_enter_segment)
	for tick in range(6):
		world.player.step(Vector2i.DOWN, world.can_occupy, world.can_enter_segment)
	check(world.player.pixel_position().x == 80 and world.player.pixel_position().y > 29, "Early perpendicular input must return to a nearby open lane")
	world.free()
	check_scrolling()
	check(scroll_checks_completed, "Scrolling suite must run to completion")
	check_health_display()
	check_beams()
	check(beam_checks_completed, "Beam suite must run to completion")
	check_rewards()
	check(reward_checks_completed, "Reward suite must run to completion")
	check_combat()
	check(combat_checks_completed, "Combat suite must run to completion")
	if ResourceLoader.exists("res://imported/world.tres"):
		var imported = Main.instantiate()
		imported.scroll_transitions = false
		root.add_child(imported)
		imported.set_physics_process(false)
		check(imported.rooms.size() == 446, "Imported world must contain 128 overworld rooms, 63 reachable caves, and 255 level rooms")
		check(imported.room.id == &"ow_77", "Import must start at the original first-quest room")
		check(imported.player.pixel_position() == Vector2i(120, 77), "Original starting position must come from level info")
		check(imported.can_occupy(imported.player.pixel_position()), "Imported start must be walkable")
		check(not imported.can_occupy(Vector2i(0, 0)), "Imported cliffs must block movement")
		for definition in imported.room_resources:
			check(definition.validation_errors().is_empty(), "Invalid imported room: " + String(definition.id))
		# Walk across a full corridor, not just an already-positioned edge.
		for tick in range(100):
			imported.player.step(Vector2i.RIGHT, imported.can_occupy, imported.can_enter_segment)
			imported.try_exit(Vector2i.RIGHT)
		check(imported.room.id == &"ow_78", "Starting-room east corridor must lead to room 78")
		for tick in range(100):
			imported.player.step(Vector2i.LEFT, imported.can_occupy, imported.can_enter_segment)
			imported.try_exit(Vector2i.LEFT)
		check(imported.room.id == &"ow_77", "Walking west must return to the starting room")
		check(imported.player.grid_origin == Vector2i(0, 5), "Imported rooms must retain original Y grid alignment")
		imported.room = imported.rooms[&"ow_77"]
		imported.player.place(Vector2i(120, 77))
		imported.player.facing = Vector2i.UP
		for tick in range(60):
			imported.player.step(Vector2i.UP, imported.can_occupy, imported.can_enter_segment)
			imported.try_exit(Vector2i.UP)
		check(imported.room.id == &"ow_67", "Grid-aligned upper boundary must allow the north exit")
		check_cave_sequence(imported)
		check(cave_checks_completed, "Cave suite must run to completion")
		check_first_encounter(imported)
		check(encounter_checks_completed, "First encounter suite must run to completion")
		imported.free()
	print("Foundation checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_cave_sequence(world: Node) -> void:
	world.enter_room(world.rooms[&"ow_77"], Vector2i(120, 77), Vector2i.LEFT)
	world.simulate_tick(Vector2i.ZERO, true)
	check(not world.sword.active(), "Sword must be unavailable before collecting it")
	for tick in range(38):
		world.simulate_tick(Vector2i.LEFT)
	for tick in range(80):
		world.simulate_tick(Vector2i.UP)
		if world.room.id == &"cave_77": break
	check(world.room.id == &"cave_77", "Walking into the visible opening must enter the sword cave")
	for tick in range(32):
		world.simulate_tick(Vector2i.ZERO)
	check(world.entry_walk_remaining == 0 and world.player.pixel_position() == Vector2i(112, 109), "Cave entry must walk exactly 48 pixels")
	var before: Vector2i = world.player.pixel_position()
	world.simulate_tick(Vector2i.UP, true)
	check(world.player.pixel_position() == before and not world.sword.active(), "Dialogue must halt movement and attacks")
	for tick in range(300):
		world.simulate_tick(Vector2i.ZERO)
	for tick in range(6):
		world.simulate_tick(Vector2i.RIGHT)
	for tick in range(60):
		world.simulate_tick(Vector2i.UP)
		if world.state.equipped_weapon != null: break
	check(world.state.equipped_weapon != null, "Touching the cave gift must grant the sword")
	check(world.lift_remaining == 128, "Gift must start the original 128-frame lifting pose")
	before = world.player.pixel_position()
	for tick in range(128):
		world.simulate_tick(Vector2i.LEFT, true)
	check(world.player.pixel_position() == before and not world.sword.active(), "Lifting an item must halt movement and attacks")
	check(world.state.has_collected(world.room.id, &"taken") and not world.cave_session.ware_visible(1), "The same gift cannot be collected twice")
	world.player.facing = Vector2i.RIGHT
	world.simulate_tick(Vector2i.ZERO, true)
	check(world.sword.active(), "Collected sword must be usable")
	var counts := [0, 0, 0, 0, 0]
	for tick in range(16):
		if world.sword.active(): counts[world.sword.phase] += 1
		world.simulate_tick(Vector2i.LEFT)
	check(counts == [5, 8, 1, 1, 1], "Sword phases must match original timing")
	check(not world.sword.active() and world.player.pixel_position() == before, "Sword must recover after 16 frames without moving Link")
	for tick in range(55):
		world.simulate_tick(Vector2i.DOWN)
		if world.room.id == &"ow_77": break
	check(world.room.id == &"ow_77", "Walking out must return from cave to its source room")
	check(world.player.pixel_position() == Vector2i(64, 29) and world.player.facing == Vector2i.DOWN, "Cave exit must start 16 pixels below the doorway, facing down")
	for tick in range(64):
		world.simulate_tick(Vector2i.ZERO)
	check(world.player.pixel_position() == Vector2i(64, 13) and world.room.id == &"ow_77", "Link must rise into the doorway without re-entering the cave")
	world.simulate_tick(Vector2i.ZERO)
	check(world.room.id == &"ow_77", "Standing in the arrival doorway must not trigger the entrance")
	check(world.state.equipped_weapon != null, "Sword ownership must survive room changes")
	world.enter_room(world.rooms[&"ow_77"], Vector2i(64, 13), Vector2i.UP)
	check(world.try_portal(Vector2i.UP), "Cave must support revisiting")
	for tick in range(32):
		world.simulate_tick(Vector2i.ZERO)
	check(not world.dialogue_visible(), "A collected cave gift must not restart its dialogue")
	check(not world.cave_session.person_visible(), "The old man must be gone on revisit after the gift")

	cave_checks_completed = true

func check_combat() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check(world.combat.enemies.size() == 2, "Native lab must spawn base and custom enemy resources without imported assets")
	var actor = world.combat.enemies[0]
	var variant = world.combat.enemies[1]
	check(actor.health == 1 and variant.health == 3, "Custom variant must change health through data")
	world.state.collect(world.room.id, world.room.pickups[0])
	world.combat.enemies.clear()
	world.combat.enemies.append(actor)
	actor.spawn_remaining = 0
	actor.subposition = Vector2i(104, 77) * 256
	actor.facing = Vector2i.LEFT
	world.player.place(Vector2i(80, 77))
	world.player.facing = Vector2i.RIGHT
	world.simulate_tick(Vector2i.ZERO, true)
	for tick in range(4): world.simulate_tick(Vector2i.ZERO)
	check(actor.health == 1, "Sword startup must not damage an enemy")
	world.simulate_tick(Vector2i.ZERO)
	check(actor.health == 0, "Fully extended wooden sword must defeat a red Octorok")
	check(world.state.defeated.has("combat_lab/red"), "Defeated state must use stable room and spawn IDs")
	check(actor.definition.health == 1, "Combat must not mutate the enemy definition")
	world.enter_room(world.room, Vector2i(80, 77), Vector2i.RIGHT)
	check(world.combat.enemies.size() == 1 and world.combat.enemies[0].id == &"stout", "Room revisit must preserve defeated enemies for the session")
	variant.spawn_remaining = 0
	check(variant.receive_hit(1, Vector2i.RIGHT) and variant.health == 2, "Custom enemy must survive the first hit")
	check(not variant.receive_hit(1, Vector2i.RIGHT), "An invulnerable enemy must reject repeated sword damage")
	for hit in range(2):
		for tick in range(32): variant.tick(Vector2i.ZERO, func(_at: Vector2i) -> bool: return true)
		check(variant.receive_hit(1, Vector2i.RIGHT), "Enemy must become vulnerable again after the damage interval")
	check(variant.health == 0 and variant.definition.health == 3, "Custom enemy must require three distinct hits")
	var shooting = preload("res://scripts/enemy_actor.gd").new()
	shooting.setup(world.room.enemies[0])
	shooting.definition = shooting.definition.duplicate()
	shooting.definition.turn_chance = 255
	shooting.definition.shoot_windup = 2
	shooting.cooldown = 0
	shooting.spawn_remaining = 0
	shooting.subposition = Vector2i(64, 45) * 256
	check(not shooting.tick(Vector2i(128, 45), func(_at: Vector2i) -> bool: return true), "Aligned enemy must wind up before shooting")
	check(shooting.windup == 2, "Shooting windup must come from enemy data")
	check(not shooting.tick(Vector2i(128, 45), func(_at: Vector2i) -> bool: return true), "Windup must not fire early")
	check(shooting.tick(Vector2i(128, 45), func(_at: Vector2i) -> bool: return true), "Windup must emit exactly one shot at completion")
	world.combat.enemies.clear()
	world.combat.player_invulnerability = 0
	world.player.place(Vector2i(80, 77))
	world.player.facing = Vector2i.RIGHT
	var rock = preload("res://scripts/rock_projectile.gd").new()
	rock.subposition = Vector2i(96, 77) * 256
	rock.direction = Vector2i.LEFT
	world.combat.rocks.append(rock)
	for tick in range(8): world.combat.tick(world)
	check(world.state.health == 6 and world.combat.rocks.is_empty(), "Facing shield must block an incoming rock")
	rock = preload("res://scripts/rock_projectile.gd").new()
	rock.subposition = Vector2i(96, 77) * 256
	rock.direction = Vector2i.LEFT
	world.player.facing = Vector2i.LEFT
	world.combat.rocks.append(rock)
	for tick in range(8): world.combat.tick(world)
	check(world.state.health == 5 and world.combat.shove_remaining == 32, "Undefended rock must remove half a heart and begin knockback")
	check(not world.combat.hurt_player(world, 1, Vector2i(80, 77)), "Player invulnerability must prevent repeated contact damage")
	world.player.place(Vector2i(32, 77))
	world.combat.shove_direction = Vector2i.LEFT
	world.combat.shove_remaining = 32
	for tick in range(10): world.combat.move_shoved_player(world)
	check(world.player.pixel_position().x == 16 and world.combat.shove_remaining == 0, "Wall must stop knockback at a traversable grid point")
	world.combat.player_invulnerability = 0
	world.state.health = 1
	check(world.combat.hurt_player(world, 1, Vector2i(32, 77)), "Final half-heart must be damageable")
	var before: Vector2i = world.player.pixel_position()
	world.simulate_tick(Vector2i.RIGHT, true)
	check(world.state.health == 0 and world.player.pixel_position() == before, "Death must freeze movement and attacks")
	var retry := InputEventKey.new()
	retry.physical_keycode = KEY_ENTER
	retry.pressed = true
	world._input(retry)
	check(world.state.health == 6 and world.state.equipped_weapon != null, "Retry must restore health and retain session inventory")
	world.free()
	combat_checks_completed = true

func check_rewards() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.combat.enemies.clear()
	var reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/heart.tres")
	reward.position = Vector2i(80, 80)
	world.player.place(Vector2i(80, 77))
	world.state.health = 3
	world.combat.rewards.append(reward)
	for tick in range(31): world.combat.tick(world)
	check(world.state.health == 3 and not reward.available(), "Fresh drops must wait 32 ticks before collection")
	world.combat.tick(world)
	check(world.state.health == 5 and world.combat.rewards.is_empty(), "Heart must restore one heart and disappear exactly once")
	reward.take(world.state)
	check(world.state.health == 5, "A collected reward cannot apply twice")
	reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/heart.tres")
	reward.position = Vector2i(80, 80)
	reward.age = 32
	world.combat.rewards.append(reward)
	world.combat.tick(world)
	check(world.state.health == 6, "Heart restoration must clamp at maximum health")
	reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/five_rupees.tres")
	reward.position = Vector2i(80, 80)
	reward.age = 32
	world.state.rupees = 253
	world.combat.rewards.append(reward)
	world.combat.tick(world)
	check(world.state.rupees == 255, "Currency must clamp at the original 255-rupee limit")
	reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/rupee.tres")
	reward.position = Vector2i(180, 80)
	reward.age = 509
	world.combat.rewards.append(reward)
	world.combat.tick(world)
	check(world.combat.rewards.is_empty(), "An uncollected drop must expire at 510 ticks")
	reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/rupee.tres")
	reward.position = Vector2i(98, 80)
	reward.age = 32
	world.state.rupees = 0
	world.state.equipped_weapon = preload("res://content/items/wooden_sword.tres")
	world.player.facing = Vector2i.RIGHT
	world.combat.rewards.append(reward)
	world.simulate_tick(Vector2i.ZERO, true)
	for tick in range(4): world.simulate_tick(Vector2i.ZERO)
	check(world.state.rupees == 0, "Invisible sword startup must not collect a distant reward")
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.rupees == 1, "Extended sword must collect rewards outside Link's direct reach")
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var sword = preload("res://scripts/sword_action.gd").new()
		sword.start(world.state.equipped_weapon, direction)
		for tick in range(5): sword.tick()
		var vertical: bool = direction.x == 0
		var center: Vector2i = Vector2i(80, 77) + sword.offset() + (Vector2i(6, 8) if vertical else Vector2i(8, 6))
		var threshold := 12 if vertical else 16
		check(sword.hits(Vector2i(80, 77), center + Vector2i(threshold - 1, 0) - Vector2i(8, 8)), "Sword must reach the last pixel inside its original threshold")
		check(not sword.hits(Vector2i(80, 77), center + Vector2i(threshold, 0) - Vector2i(8, 8)), "Sword must reject the exact outside threshold")
	var table = preload("res://scripts/loot_table.gd").new()
	table.chance = 80
	table.entries.append(preload("res://content/items/heart.tres"))
	table.entries.append(null)
	check(table.select(0, 79) != null and table.select(0, 80) == null, "Drop probability must use the original strict roll threshold")
	check(table.select(1, 0) == null and table.select(2, 0) != null, "Drop rows must follow the cyclic kill index and preserve empty entries")
	var actor = preload("res://scripts/enemy_actor.gd").new()
	actor.setup(world.room.enemies[1])
	actor.definition = actor.definition.duplicate()
	actor.definition.turn_chance = 255
	actor.definition.shoot_cooldown = 0
	actor.spawn_remaining = 0
	actor.subposition = Vector2i(64, 45) * 256
	actor.facing = Vector2i.RIGHT
	for tick in range(64): actor.tick(Vector2i(200, 45), func(_at: Vector2i) -> bool: return true)
	check(actor.position() == Vector2i(112, 45), "Fractional-speed variant must retain its speed across grid boundaries")
	world.sword.phase = -1
	world.state.health = 1
	world.combat.player_invulnerability = 0
	world.combat.rocks.clear()
	var attacker = preload("res://scripts/enemy_actor.gd").new()
	attacker.setup(world.room.enemies[0])
	attacker.definition = attacker.definition.duplicate()
	attacker.definition.speed_subpixels = 0
	attacker.spawn_remaining = 0
	attacker.subposition = world.player.subposition
	world.combat.enemies.append(attacker)
	reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/heart.tres")
	reward.position = world.player.pixel_position() + Vector2i(0, 3)
	reward.age = 32
	world.combat.rewards.append(reward)
	world.combat.tick(world)
	check(world.state.health == 0 and not reward.collected, "A heart must not undo lethal contact damage in the same frame")
	world.free()
	reward_checks_completed = true

func check_first_encounter(world: Node) -> void:
	# Cave checks already obtained the sword. Walk through the actual east exit.
	world.enter_room(world.rooms[&"ow_77"], Vector2i(120, 77), Vector2i.RIGHT)
	for tick in range(80): world.simulate_tick(Vector2i.RIGHT)
	check(world.room.id == &"ow_78" and world.combat.enemies.size() == 4, "First east room must spawn its four original Octoroks")
	var actors: Array[RefCounted] = world.combat.enemies.duplicate()
	# Control encounter positions and rolls, keeping actual sword, death, drop,
	# collection, room-transition, and session-state code in the loop.
	var table = preload("res://scripts/loot_table.gd").new()
	table.chance = 256
	table.entries.append(preload("res://content/items/rupee.tres"))
	table.entries.append(preload("res://content/items/heart.tres"))
	world.loot_tables = world.loot_tables.duplicate()
	world.loot_tables[&"red_octorok"] = table
	world.state.kill_cycle = 0
	world.state.health = 4
	world.state.rupees = 0
	for actor in actors:
		actor.definition = actor.definition.duplicate()
		actor.definition.behavior = "native"
		actor.waiting_spawn = false
		actor.spawn_remaining = 10000
	for actor in actors:
		actor.definition = actor.definition.duplicate()
		actor.definition.speed_subpixels = 0
		actor.definition.shoot_cooldown = 0
		actor.spawn_remaining = 0
		actor.subposition = Vector2i(104, 93) * 256
		actor.facing = Vector2i.RIGHT
		world.player.place(Vector2i(80, 93))
		world.player.facing = Vector2i.RIGHT
		world.simulate_tick(Vector2i.ZERO, true)
		for tick in range(50): world.simulate_tick(Vector2i.ZERO)
		check(actor.health == 0 and actor.drop_resolved, "Real sword attack must defeat the enemy and resolve its drop after the death effect")
		check(world.combat.rewards.size() == 1, "Each defeated enemy must spawn at most one configured reward")
		for tick in range(16): world.simulate_tick(Vector2i.RIGHT)
		check(world.combat.rewards.is_empty(), "Walking over the drop must collect it")
	check(world.state.health == 6 and world.state.rupees == 2, "Four controlled kills must restore health and award currency")
	check(world.state.kill_cycle == 4, "Death completion must advance the global kill cycle once per enemy")
	for tick in range(16): world.simulate_tick(Vector2i.LEFT)
	for tick in range(11): world.simulate_tick(Vector2i.UP)
	for tick in range(80): world.simulate_tick(Vector2i.LEFT)
	check(world.room.id == &"ow_77" and world.state.rupees == 2 and world.state.equipped_weapon != null, "Returning west must retain rewards and sword ownership")
	world.enter_room(world.rooms[&"ow_78"], Vector2i(0, 77), Vector2i.RIGHT)
	check(world.combat.enemies.is_empty() and world.combat.rewards.is_empty(), "Revisiting must not duplicate defeated enemies or their rewards")
	encounter_checks_completed = true

func check_beams() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.combat.enemies.clear()
	world.state.equipped_weapon = preload("res://content/items/wooden_sword.tres")
	world.player.place(Vector2i(80, 77))
	world.player.facing = Vector2i.RIGHT
	world.simulate_tick(Vector2i.ZERO, true)
	for tick in range(12): world.simulate_tick(Vector2i.ZERO)
	check(world.combat.beam == null, "Beam must wait until the sword's third phase")
	world.simulate_tick(Vector2i.ZERO)
	check(world.combat.beam != null and world.combat.beam.position == Vector2i(96, 77), "Beam must begin 16 pixels ahead, without moving on its emission frame")
	var first = world.combat.beam
	world.simulate_tick(Vector2i.ZERO)
	check(first.position == Vector2i(99, 77), "Beam must fly three pixels per simulation tick")
	for tick in range(4): world.simulate_tick(Vector2i.ZERO)
	world.simulate_tick(Vector2i.ZERO, true)
	for tick in range(13): world.simulate_tick(Vector2i.ZERO)
	check(world.combat.beam == first, "A second swing must not replace an active beam")
	first.position = Vector2i(238, 77)
	world.combat.tick_beam(world)
	check(first.burst_remaining == 22 and first.position.x == 240, "Room boundary must start the 22-tick burst without crossing rooms")
	check(not world.combat.launch_beam(world), "Burst must retain the single projectile slot")
	for tick in range(22): world.combat.tick_beam(world)
	check(world.combat.beam == null, "Burst must release the projectile slot at completion")
	world.sword.phase = -1
	world.sword.start(world.state.equipped_weapon, Vector2i.RIGHT)
	world.state.health = 4
	check(not world.combat.launch_beam(world), "One missing heart must disable the beam")
	world.state.health = 5
	check(world.combat.launch_beam(world), "The original half-partial-heart threshold must allow half a heart missing")
	world.combat.beam = null
	world.sword.weapon = world.sword.weapon.duplicate()
	world.sword.weapon.fires_beam = false
	check(not world.combat.launch_beam(world), "Custom weapon definition must be able to disable beams")
	world.sword.weapon = world.state.equipped_weapon
	world.state.health = 6
	world.player.place(Vector2i(8, 77))
	world.sword.direction = Vector2i.LEFT
	check(not world.combat.launch_beam(world), "Horizontal edge restriction must reject an offscreen launch")
	world.player.place(Vector2i(80, 77))
	world.sword.direction = Vector2i.RIGHT
	check(world.combat.launch_beam(world), "Slot must permit another beam after recovery")
	world.room = world.room.duplicate()
	var lines: PackedStringArray = world.room.rows()
	lines[5] = "#......#.......#"
	world.room.tiles = "\n".join(lines)
	for tick in range(6): world.combat.tick_beam(world)
	check(world.combat.beam.flying() and world.combat.beam.position == Vector2i(114, 77), "Beam flight must follow room bounds rather than rock terrain collision")
	var actor = preload("res://scripts/enemy_actor.gd").new()
	actor.setup(world.room.enemies[0])
	actor.spawn_remaining = 0
	actor.subposition = Vector2i(144, 77) * 256
	world.combat.enemies.append(actor)
	for tick in range(12):
		world.combat.tick_beam(world)
		if actor.health == 0: break
	check(actor.health == 0 and world.combat.beam.burst_remaining == 22, "Beam hit must damage an enemy and immediately stop flight")
	check(world.state.defeated.has("combat_lab/red"), "Beam kills must use the same persistent defeated flag as melee")
	check(not world.combat.beam.hits(Vector2i(144, 77)), "Burst must be non-damaging")
	for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var beam = preload("res://scripts/sword_beam.gd").new()
		beam.position = Vector2i(80, 77)
		beam.direction = direction
		var center: Vector2i = beam.position + (Vector2i(6, 8) if direction.x == 0 else Vector2i(8, 6))
		check(beam.hits(center + Vector2i(11, 0) - Vector2i(8, 8)), "Beam must hit inside its strict distance threshold")
		check(not beam.hits(center + Vector2i(12, 0) - Vector2i(8, 8)), "Beam must reject targets at the outside threshold")
	world.enter_room(world.room, Vector2i(80, 77), Vector2i.RIGHT)
	check(world.combat.beam == null, "Room changes must clear the beam")
	world.free()
	beam_checks_completed = true

func check_health_display() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check([world.state.heart_frame(0), world.state.heart_frame(1), world.state.heart_frame(2)] == [0, 0, 0], "Full health must select three filled HUD hearts")
	world.combat.hurt_player(world, 1, Vector2i(120, 120))
	check([world.state.heart_frame(0), world.state.heart_frame(1), world.state.heart_frame(2)] == [0, 0, 1], "One contact hit must show a half-empty final heart")
	world.combat.player_invulnerability = 0
	world.combat.hurt_player(world, 1, Vector2i(120, 120))
	check([world.state.heart_frame(0), world.state.heart_frame(1), world.state.heart_frame(2)] == [0, 0, 2], "Two contact hits must show an empty final heart")
	var reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = preload("res://content/items/heart.tres")
	reward.age = 32
	reward.take(world.state)
	check(world.state.heart_frame(2) == 0, "A heart pickup must refill the displayed final heart")
	world.state.health = 0
	check([world.state.heart_frame(0), world.state.heart_frame(1), world.state.heart_frame(2)] == [2, 2, 2], "Zero health must show empty HUD hearts")
	world.free()

func check_scrolling() -> void:
	var world = Main.instantiate()
	world.use_imported_world = false
	root.add_child(world)
	world.set_physics_process(false)
	world.state.rupees = 13
	world.state.health = 5
	world.combat.player_invulnerability = 48
	var actor = preload("res://scripts/enemy_actor.gd").new()
	actor.setup(preload("res://content/rooms/combat_lab.tres").enemies[0])
	world.combat.enemies.append(actor)
	var rock = preload("res://scripts/rock_projectile.gd").new()
	world.combat.rocks.append(rock)
	world.combat.beam = preload("res://scripts/sword_beam.gd").new()
	world.player.place(Vector2i(240, 80))
	world.try_exit(Vector2i.RIGHT)
	check(world.transition != null and world.room.id == &"test_field", "Scroll must retain the source room until completion")
	check(world.combat.beam == null and world.combat.rocks.is_empty(), "Starting a scroll must clear transient projectiles")
	var reset := InputEventKey.new()
	reset.physical_keycode = KEY_R
	reset.pressed = true
	world._input(reset)
	check(world.player.pixel_position() == Vector2i(240, 80), "Reset input must not move Link during scrolling")
	for tick in range(63): world.simulate_tick(Vector2i.LEFT, true)
	check(world.transition != null and world.transition.distance == 252, "Horizontal scrolling must advance four pixels per tick for 64 ticks")
	check(actor.spawn_remaining == 32 and world.combat.player_invulnerability == 48, "Enemy and damage timers must remain frozen during scrolling")
	check(not world.sword.active() and world.state.health == 5, "Movement and attacks must not cause combat during scrolling")
	world.simulate_tick(Vector2i.ZERO)
	check(world.transition == null and world.room.id == &"expansion_field" and world.player.pixel_position() == Vector2i(0, 80), "Horizontal completion must enter the destination exactly once at its matching edge")
	check(world.state.rupees == 13 and world.state.health == 5, "Scrolling must preserve health and currency")
	world.try_exit(Vector2i.LEFT)
	for tick in range(64): world.simulate_tick(Vector2i.ZERO)
	check(world.room.id == &"test_field" and world.player.pixel_position() == Vector2i(240, 80), "Left scroll must return to the original room")
	world.simulate_tick(Vector2i.LEFT)
	check(world.transition == null and world.player.pixel_position().x < 240, "Movement must resume after the completion frame")
	var a = preload("res://scripts/room_definition.gd").new()
	var b = preload("res://scripts/room_definition.gd").new()
	a.id = &"scroll_a"
	b.id = &"scroll_b"
	var rows := PackedStringArray()
	for y in range(11): rows.append("................")
	a.tiles = "\n".join(rows)
	b.tiles = a.tiles
	a.exits["up"] = "scroll_b"
	a.exits["down"] = "scroll_b"
	a.exits["right"] = "scroll_b"
	world.rooms[a.id] = a
	world.rooms[b.id] = b
	for direction in [Vector2i.UP, Vector2i.DOWN]:
		var y := 0 if direction == Vector2i.UP else 160
		world.enter_room(a, Vector2i(120, y), direction)
		world.try_exit(direction)
		world.simulate_tick(Vector2i.ZERO)
		check(world.transition != null and world.transition.distance == 0, "Vertical scrolling must wait on its first tick")
		world.simulate_tick(Vector2i.ZERO)
		check(world.transition.distance == 8, "Vertical scrolling must move eight pixels every other tick")
		for tick in range(41): world.simulate_tick(Vector2i.ZERO)
		check(world.transition != null and world.transition.distance == 168, "Vertical scrolling must remain active through tick 43")
		world.simulate_tick(Vector2i.ZERO)
		check(world.transition == null and world.room.id == b.id and world.player.pixel_position() == Vector2i(120, 160 - y), "Vertical completion must preserve the horizontal coordinate and use the opposite edge")
	rows[5] = "################"
	b.tiles = "\n".join(rows)
	world.enter_room(a, Vector2i(240, 80), Vector2i.RIGHT)
	world.combat.beam = preload("res://scripts/sword_beam.gd").new()
	world.try_exit(Vector2i.RIGHT)
	check(world.transition == null and world.room.id == a.id and world.combat.beam != null, "Blocked destination must neither scroll nor clear ongoing combat")
	world.enter_room(a, Vector2i(120, 80), Vector2i.RIGHT)
	world.try_exit(Vector2i.RIGHT)
	check(world.transition == null, "An interior position must not start scrolling")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		var original = Main.instantiate()
		root.add_child(original)
		original.set_physics_process(false)
		original.enter_room(original.rooms[&"ow_77"], Vector2i(240, 77), Vector2i.RIGHT)
		original.try_exit(Vector2i.RIGHT)
		for tick in range(64): original.simulate_tick(Vector2i.ZERO)
		check(original.room.id == &"ow_78" and original.combat.enemies.size() == 4, "Original east encounter must initialize after the scroll")
		check(original.combat.enemies[0].waiting_spawn and original.combat.enemies[3].waiting_spawn, "Incoming edge enemies must wait until after scrolling")
		original.try_exit(Vector2i.LEFT)
		for tick in range(64): original.simulate_tick(Vector2i.ZERO)
		check(original.room.id == &"ow_77", "Original west exit must scroll back to the starting screen")
		original.player.place(Vector2i(120, -3))
		original.try_exit(Vector2i.UP)
		for tick in range(44): original.simulate_tick(Vector2i.ZERO)
		check(original.room.id == &"ow_67" and original.player.pixel_position() == Vector2i(120, 157), "Original north exit must preserve the five-pixel Y grid phase")
		original.try_exit(Vector2i.DOWN)
		for tick in range(44): original.simulate_tick(Vector2i.ZERO)
		check(original.room.id == &"ow_77" and original.player.pixel_position() == Vector2i(120, -3), "Original south return must retain the aligned upper edge")
		original.free()
	scroll_checks_completed = true
