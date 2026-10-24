extends SceneTree

const Player = preload("res://scripts/player.gd")
const Main = preload("res://scenes/main.tscn")
var failures := 0
var combat_checks_completed := false
var cave_checks_completed := false

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
	check_combat()
	check(combat_checks_completed, "Combat suite must run to completion")
	if ResourceLoader.exists("res://imported/world.tres"):
		var imported = Main.instantiate()
		root.add_child(imported)
		imported.set_physics_process(false)
		check(imported.rooms.size() == 129, "Imported world must contain 128 overworld rooms and the sword cave")
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
		if world.room.id == &"sword_cave": break
	check(world.room.id == &"sword_cave", "Walking into the visible opening must enter the sword cave")
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
	check(not world.state.collect(world.room.id, world.room.pickups[0]), "The same gift cannot be collected twice")
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
	check(world.room.id == &"ow_77", "Walking out must return from cave to its source room")
	check(world.state.equipped_weapon != null, "Sword ownership must survive room changes")
	world.enter_room(world.rooms[&"ow_77"], Vector2i(64, 13), Vector2i.UP)
	check(world.try_portal(Vector2i.UP), "Cave must support revisiting")
	for tick in range(32):
		world.simulate_tick(Vector2i.ZERO)
	check(not world.dialogue_visible(), "A collected cave gift must not restart its dialogue")
	check(not world.decoration_visible(world.room.decorations[0]), "The old man must be gone on revisit after the gift")

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
