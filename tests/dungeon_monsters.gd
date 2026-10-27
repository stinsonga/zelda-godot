extends SceneTree
## Dungeon monsters: Stalfos, Gels, Zols, Keese, Goriyas, and Ropes, plus kill
## triggers. Needs a local ROM import; reports a skip without one.
var failures := 0
var completed := false
const Main = preload("res://scenes/main.tscn")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Dungeon monster suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func definition(name: String) -> Resource:
	return load("res://imported/enemies/" + name + ".tres")

func actor(name: String, at: Vector2i, facing: Vector2i = Vector2i.RIGHT) -> RefCounted:
	var spawn = Spawn.new()
	spawn.id = StringName(name)
	spawn.enemy = definition(name)
	spawn.position = at
	spawn.facing = facing
	spawn.spawn_ticks = 0
	var result = Actor.new()
	result.setup(spawn)
	result.spawn_remaining = 0
	return result

func open(_at: Vector2i, _direction: Vector2i) -> bool: return true

func kill_all(world: Node) -> void:
	for monster in world.combat.enemies:
		monster.spawn_remaining = 0
		monster.waiting_spawn = false
		monster.health = 0
		monster.death_remaining = 0

func run() -> void:
	if not ResourceLoader.exists("res://imported/enemies/stalfos.tres"):
		print("Dungeon monster checks: SKIPPED (no local ROM import)")
		quit(0)
		return
	check_definitions()
	check_behaviors()
	var world = Main.instantiate()
	world.scroll_transitions = false
	root.add_child(world)
	world.set_physics_process(false)
	check_rooms(world)
	check_regulars(world)
	check(completed, "Regular monster checks must run to completion")
	world.free()
	print("Dungeon monster checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_definitions() -> void:
	for name in ["stalfos", "blue_goriya", "red_goriya", "zol", "gel", "child_gel", "blue_keese", "red_keese", "black_keese", "rope"]:
		check(definition(name).validation_errors().is_empty(), "Imported " + name + " must validate")
	check(definition("stalfos").health == 2 and not definition("stalfos").shooting_enabled, "First-quest Stalfos take two hits and never shoot")
	check(definition("blue_goriya").health == 5 and definition("red_goriya").health == 3, "Goriya health must come from the ROM")
	check(definition("red_goriya").shoot_random_values == PackedInt32Array([35, 119]), "Red Goriyas throw only on random $23 or $77")
	check(definition("zol").splits_into == definition("child_gel") and definition("gel").health == 1, "Zols split into one-hit Gels")
	check(definition("blue_keese").flight_initial_speed == 0x1F and definition("red_keese").flight_initial_speed == 0x7F, "Keese start speeds follow InitBlueKeese")

func check_behaviors() -> void:
	var stalfos = actor("stalfos", Vector2i(64, 61))
	var path := 0
	for i in range(32):
		var before: Vector2i = stalfos.subposition
		stalfos.tick(Vector2i(200, 141), Callable(), open, true, {})
		path += absi(stalfos.subposition.x - before.x) + absi(stalfos.subposition.y - before.y)
	check(path == 32 * 128, "Stalfos walk half a pixel a frame")
	var gel = actor("gel", Vector2i(64, 61))
	gel.family.initialized = true
	var context := {"bounds": Rect2i(33, 30, 175, 95)}
	var waited := false
	for i in range(120):
		gel.tick(Vector2i(200, 141), Callable(), open, true, context)
		if gel.family.timer >= 5:
			var before: Vector2i = gel.position()
			gel.tick(Vector2i(200, 141), Callable(), open, true, context)
			waited = gel.position() == before
			break
	check(waited and gel.family.timer in [7, 23, 39, 55], "Gels wait at squares for one of their delays")
	var keese = actor("blue_keese", Vector2i(120, 77), Vector2i.ZERO)
	keese.source_random = 5
	keese.tick(Vector2i(0, 0), Callable(), open, true, context)
	check(keese.targetable() and keese.family.flight_speed >= 0x1F, "Keese can be hit while flying and start at their initial speed")
	for i in range(600):
		keese.source_random = (i * 37) & 255
		keese.source_next_random = (i * 91) & 255
		keese.tick(Vector2i(0, 0), Callable(), open, true, context)
		check(Rect2i(32, 29, 178, 98).has_point(keese.position()), "Keese stay inside dungeon object bounds")
		if failures > 0: break
	var rope = actor("rope", Vector2i(64, 93), Vector2i.UP)
	rope.family.initialized = true
	rope.family.timer = 60
	for i in range(40):
		rope.tick(Vector2i(144, 77), Callable(), open, true, context)
		if rope.family.rope_speed == 384: break
	check(rope.family.rope_speed == 384 and rope.facing == Vector2i.RIGHT, "Ropes rush when lined up with Link at a square")

func check_rooms(world: Node) -> void:
	# Goriya boomerang: thrown, the thrower waits, then it comes back.
	world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 141), Vector2i.UP)
	world.combat.enemies.clear()
	var goriya = actor("blue_goriya", Vector2i(64, 77))
	goriya.slot = 1
	world.combat.enemies.append(goriya)
	world.player.place(Vector2i(144, 77))
	world.combat.player_invulnerability = 100000
	var thrown := false
	for i in range(200):
		world.combat.tick(world)
		if goriya.shot_out:
			thrown = true
			break
	check(thrown and world.combat.rocks.size() == 1 and world.combat.rocks[0].kind == "boomerang", "Blue Goriyas throw boomerangs at Link")
	var held: Vector2i = goriya.position()
	var returned := false
	for i in range(200):
		world.combat.tick(world)
		check(goriya.position() == held or not goriya.shot_out, "A Goriya waits while its boomerang is out")
		if not goriya.shot_out:
			returned = true
			break
	check(returned and world.combat.rocks.is_empty(), "Boomerangs return to their thrower")
	# Zol: a surviving hit splits it in two; the room needs one more kill.
	world.combat.enemies.clear()
	world.combat.rocks.clear()
	var zol = actor("zol", Vector2i(64, 77), Vector2i.RIGHT)
	world.combat.enemies.append(zol)
	world.combat.encounter_total = 1
	check(zol.receive_hit(1, Vector2i.RIGHT) and zol.health == 1, "A Zol survives one wooden-sword hit")
	world.combat.tick(world)
	var gels: Array = world.combat.enemies.filter(func(monster: RefCounted) -> bool: return monster.definition.id == &"child_gel")
	check(gels.size() == 2 and zol.health == 0 and zol.drop_resolved and world.combat.encounter_total == 2, "A hit Zol becomes two Gels without a drop")
	check(gels[0].facing == -gels[1].facing and gels[0].facing.x == 0, "Split Gels dart apart perpendicular to the Zol")
	# Spawning, shutters, and items that wait for a clear room.
	world.enter_room(world.rooms[&"l1_52"], Vector2i(120, 77), Vector2i.UP)
	check(world.combat.enemies.size() > 0, "Keese rooms must spawn their monsters")
	for i in range(80): world.combat.tick(world)
	for monster in world.combat.enemies:
		check(world.combat.bounds.grow(1).has_point(monster.position()) or monster.waiting_spawn, "Dungeon monsters spawn inside the walls")
	var shutter: Resource = null
	for door in world.room.doors:
		if door.kind == "shutter": shutter = door
	check(shutter != null and not world.door_passable(world.room, shutter), "Shutters stay closed while monsters live")
	kill_all(world)
	check(world.door_passable(world.room, shutter), "Killing every monster opens the shutters")
	world.enter_room(world.rooms[&"l1_23"], Vector2i(120, 141), Vector2i.UP)
	var key: Resource = world.room.pickups[0]
	world.player.place(key.position)
	world.try_pickups()
	check(world.state.item_value(&"keys") == 0, "A room's reward waits until its monsters are gone")
	kill_all(world)
	world.try_pickups()
	check(world.state.item_value(&"keys") == 1, "Clearing the room releases its key")
	world.enter_room(world.rooms[&"l1_c7f"], Vector2i(48, 29), Vector2i.UP)
	check(world.combat.enemies.size() == 4 and world.combat.enemies.all(func(monster: RefCounted) -> bool: return monster.definition.id == &"blue_keese"), "Cellars hold four blue Keese")

func fresh_room(world: Node, monsters: Array) -> void:
	world.enter_room(world.rooms[&"l1_73"], Vector2i(120, 141), Vector2i.UP)
	world.combat.enemies.clear()
	world.combat.rocks.clear()
	for monster in monsters: world.combat.enemies.append(monster)
	world.state.sword_cursed = false
	world.state.sword_block_ticks = 0
	world.state.max_health = 32
	world.state.health = 32

func check_regulars(world: Node) -> void:
	var darknut = actor("red_darknut", Vector2i(64, 77), Vector2i.LEFT)
	check(not darknut.receive_hit(1, Vector2i.RIGHT, "sword") and darknut.parried_hit, "Darknuts parry swords from the front")
	check(darknut.receive_hit(1, Vector2i.LEFT, "sword"), "Darknuts are hurt from behind")
	darknut.invulnerability = 0
	check(not darknut.receive_hit(1, Vector2i.UP, "fire") and darknut.receive_hit(4, Vector2i.UP, "bomb"), "Darknuts ignore fire but not bombs")
	for name in ["red_darknut", "blue_darknut", "gibdo", "like_like", "vire", "pols_voice", "wallmaster", "bubble", "blue_bubble", "red_bubble", "trap"]:
		check(definition(name).validation_errors().is_empty(), "Imported " + name + " must validate")
	check(definition("blue_darknut").speed_subpixels == 160, "Blue Darknuts walk at q-speed $28")
	# Bubbles: harmless, unkillable, and not needed to clear a room.
	var bubble = actor("bubble", Vector2i(120, 125))
	fresh_room(world, [bubble])
	check(world.monsters_gone(), "Bubbles do not keep a room uncleared")
	world.player.place(Vector2i(120, 125))
	var health: int = world.state.health
	world.combat.tick(world)
	check(world.state.sword_block_ticks == 0xA0 and world.state.health == health, "A flashing Bubble blocks the sword without hurting")
	world.simulate_tick(Vector2i.ZERO, true)
	check(not world.sword.active(), "A blocked sword cannot swing")
	var red = actor("red_bubble", Vector2i(120, 125))
	var blue = actor("blue_bubble", Vector2i(120, 125))
	fresh_room(world, [red])
	world.player.place(Vector2i(120, 125))
	world.combat.tick(world)
	check(world.state.sword_cursed, "Red Bubbles curse the sword")
	world.combat.enemies.clear()
	world.combat.enemies.append(blue)
	world.state.sword_block_ticks = 0
	world.combat.tick(world)
	check(not world.state.sword_cursed, "Blue Bubbles lift the curse")
	# Like Like: holds Link, then eats the magical shield.
	world.state.slots[&"magic_shield"] = 1
	var like_like = actor("like_like", Vector2i(120, 125))
	fresh_room(world, [like_like])
	world.player.place(Vector2i(120, 125))
	world.combat.player_invulnerability = 0
	world.simulate_tick(Vector2i.ZERO)
	check(world.captor == like_like, "Like Likes capture Link on contact")
	var held: Vector2i = world.player.pixel_position()
	for i in range(0x60): world.simulate_tick(Vector2i.LEFT)
	check(world.player.pixel_position() == held and world.state.item_value(&"magic_shield") == 0, "A captured Link cannot walk and loses the magical shield")
	like_like.health = 0
	world.simulate_tick(Vector2i.LEFT)
	check(world.captor == null, "Killing the Like Like frees Link")
	# Vire: wounded, it becomes two red Keese.
	var vire = actor("vire", Vector2i(64, 77))
	fresh_room(world, [vire])
	world.combat.encounter_total = 1
	vire.receive_hit(1, Vector2i.RIGHT)
	world.combat.tick(world)
	var keese: Array = world.combat.enemies.filter(func(monster: RefCounted) -> bool: return monster.definition.id == &"red_keese")
	check(keese.size() == 2 and world.combat.encounter_total == 2, "A wounded Vire splits into two red Keese")
	# Traps slide toward the middle when Link lines up, then return.
	var trap = actor("trap", Vector2i(32, 29))
	fresh_room(world, [trap])
	world.player.place(Vector2i(120, 29))
	world.combat.player_invulnerability = 100000
	var reached := false
	for i in range(120):
		world.combat.tick(world)
		if trap.position().x > 100: reached = true
	check(reached and trap.family.phase == 2, "Traps slide fast toward the room's middle, then return")
	world.player.place(Vector2i(120, 141))
	for i in range(400): world.combat.tick(world)
	check(trap.position() == Vector2i(32, 29) and trap.family.phase == 0, "Traps creep home and wait again")
	check(not trap.receive_hit(4, Vector2i.RIGHT, "bomb") and world.monsters_gone(), "Traps are invulnerable and do not keep a room uncleared")
	# Wallmaster: emerges when Link stands at a wall, carries him back to the start.
	var wallmaster = actor("wallmaster", Vector2i(0, 0))
	fresh_room(world, [wallmaster])
	world.enter_room(world.rooms[&"l1_74"], Vector2i(32, 77), Vector2i.LEFT)
	world.combat.enemies.clear()
	world.combat.enemies.append(wallmaster)
	world.combat.player_invulnerability = 0
	world.player.facing = Vector2i.LEFT
	var emerged := false
	for i in range(400):
		world.simulate_tick(Vector2i.ZERO)
		if wallmaster.family.phase == 1: emerged = true
		if world.room.id == &"l1_73": break
	check(emerged, "Wallmasters emerge from the wall beside Link")
	check(world.room.id == &"l1_73", "A Wallmaster carries Link back to the level's first room")
	# Pols Voice hops but stays inside the room.
	var pols = actor("pols_voice", Vector2i(120, 77), Vector2i.RIGHT)
	var context := {"bounds": Rect2i(33, 30, 175, 95)}
	for i in range(600):
		pols.source_random = (i * 53) & 255
		pols.tick(Vector2i(0, 0), Callable(), open, true, context)
	check(Rect2i(16, 0, 224, 160).has_point(pols.position()), "Pols Voice stays inside the room")
	check(not pols.receive_hit(4, Vector2i.UP, "bomb") and pols.receive_hit(1, Vector2i.UP, "sword"), "Only the sword hurts Pols Voice")
	# Red Wizzrobe: appears on a square beside Link, shoots once per cycle, vanishes.
	var red_wizzrobe = actor("red_wizzrobe", Vector2i(0, 0))
	fresh_room(world, [red_wizzrobe])
	world.player.place(Vector2i(120, 77))
	world.combat.player_invulnerability = 100000
	var shots := 0
	var seen_hidden := false
	for i in range(256):
		world.combat.advance_frame()
		world.combat.tick(world)
		shots += world.combat.rocks.filter(func(r: RefCounted) -> bool: return r.kind == "magic" and r.age <= 1).size()
		if not red_wizzrobe.targetable(): seen_hidden = true
	var at: Vector2i = red_wizzrobe.position()
	check(shots == 1 and seen_hidden, "Red Wizzrobes shoot once per 256-frame cycle and spend part of it hidden")
	# Offsets reach $50, then the spot is rounded down to its square (AND $F0).
	check(at.x % 16 == 0 and (at.y + 3) % 16 == 0 and (at - Vector2i(120, 77)).abs().x < 0x50 + 16 and (at - Vector2i(120, 77)).abs().y < 0x50 + 16, "Red Wizzrobes appear on a square near Link")
	check(not world.combat.shield_blocks(world, world.combat.rocks[0]) if not world.combat.rocks.is_empty() else true, "Only the magical shield stops Wizzrobe magic")
	# Blue Wizzrobe: walks, teleports, and fires along Link's row.
	var blue_wizzrobe = actor("blue_wizzrobe", Vector2i(112, 77), Vector2i.RIGHT)
	fresh_room(world, [blue_wizzrobe])
	world.player.place(Vector2i(176, 77))
	var teleported := false
	var fired := false
	for i in range(2400):
		world.combat.advance_frame()
		world.combat.tick(world)
		if blue_wizzrobe.family.teleport_left > 0: teleported = true
		if not world.combat.rocks.is_empty(): fired = true
	check(teleported and fired, "Blue Wizzrobes teleport and shoot magic")
	# Aquamentus: paces its patch, breathes three fireballs, and guards the heart container.
	world.enter_room(world.rooms[&"l1_35"], Vector2i(32, 77), Vector2i.RIGHT)
	var boss: RefCounted = world.combat.enemies[0]
	check(boss.definition.id == &"aquamentus" and boss.position() == Vector2i(0xB0, 0x80 - 64) and boss.definition.size == Vector2i(24, 32), "Aquamentus starts at ($B0, $80)")
	world.state.max_health = 32
	world.state.health = 32
	var volley := 0
	var left := 255
	var right := 0
	for i in range(400):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)
		volley = maxi(volley, world.combat.rocks.filter(func(r: RefCounted) -> bool: return r.kind == "fireball").size())
		left = mini(left, boss.position().x)
		right = maxi(right, boss.position().x)
	check(volley == 3, "Aquamentus breathes three fireballs at once")
	check(left >= 0x88 and right <= 0xC8 and right > left, "Aquamentus paces between X $88 and $C7")
	world.combat.rocks.clear()
	world.combat.player_invulnerability = 0
	var fireball: RefCounted = world.combat.make_fireball(world, world.player.pixel_position() + Vector2i(40, 0), 0)
	fireball.damage = boss.definition.projectile_damage
	world.combat.rocks.append(fireball)
	var before: int = world.state.health
	for i in range(40): world.combat.tick(world)
	check(world.state.health < before, "Fireballs fly at Link and hurt him")
	check(not boss.receive_hit(1, Vector2i.RIGHT, "fire") and not boss.receive_hit(1, Vector2i.RIGHT, "boomerang"), "Aquamentus ignores fire and the boomerang")
	var reward: Resource = world.room.pickups[0]
	world.player.place(reward.position)
	world.try_pickups()
	check(not world.state.has_collected(&"l1_35", &"item"), "The heart container waits for Aquamentus to fall")
	boss.health = 0
	world.try_pickups()
	check(world.state.has_collected(&"l1_35", &"item"), "Defeating Aquamentus releases the heart container")
	# Dodongo: swords bounce off; two eaten bombs, or a blast and a sword, defeat it.
	var ItemObject = preload("res://scripts/item_object.gd")
	var dodongo = actor("dodongo", Vector2i(80, 77), Vector2i.RIGHT)
	fresh_room(world, [dodongo])
	check(dodongo.size() == Vector2i(32, 16) and not dodongo.targetable(), "Dodongo is 32 wide sideways and shrugs off weapons")
	var mouth: Vector2i = dodongo.position() + Vector2i(16, 0) + Vector2i(8, 0)
	world.item_objects.append(ItemObject.bomb(mouth, Vector2i.LEFT))
	for i in range(3): world.simulate_tick(Vector2i.ZERO)
	check(dodongo.family.phase == 1 and dodongo.family.bombs_eaten == 1 and world.item_objects.is_empty(), "Dodongo eats a ticking bomb at its mouth")
	for i in range(0x20 + 0x40 + 4): world.simulate_tick(Vector2i.ZERO)
	check(dodongo.family.phase == 0 and dodongo.health > 0, "One bomb only bloats Dodongo")
	mouth = dodongo.position() + Vector2i(16 if dodongo.facing.x != 0 else 8, 8) + dodongo.facing * 8 - Vector2i(8, 8)
	world.item_objects.append(ItemObject.bomb(mouth, Vector2i.LEFT))
	for i in range(0x20 + 0x40 + 0x40 + 8): world.simulate_tick(Vector2i.ZERO)
	check(dodongo.health == 0, "A second eaten bomb defeats Dodongo")
	var stunned_dodongo = actor("dodongo", Vector2i(80, 77), Vector2i.RIGHT)
	fresh_room(world, [stunned_dodongo])
	var blast = ItemObject.bomb(stunned_dodongo.position() + Vector2i(24, 0), Vector2i.LEFT)
	blast.stage = 3
	blast.timer = 20
	world.item_objects.append(blast)
	world.simulate_tick(Vector2i.ZERO)
	check(stunned_dodongo.family.phase == 2 and stunned_dodongo.targetable(), "A bomb blast beside Dodongo stuns it")
	check(stunned_dodongo.receive_hit(1, Vector2i.LEFT, "sword") and stunned_dodongo.health == 0, "A stunned Dodongo falls to the sword")
	# Gohma: arrows only, flying up into the fully open eye.
	world.enter_room(world.rooms[&"l6_1c"], Vector2i(128, 125), Vector2i.UP)
	var gohma: RefCounted = world.combat.enemies[0]
	check(gohma.definition.behavior == "gohma" and gohma.position() == Vector2i(0x70, 0x70 - 64) and gohma.size() == Vector2i(48, 16), "Gohma starts with its middle at ($80, $70)")
	check(not gohma.receive_hit(1, Vector2i.UP, "sword"), "Swords bounce off Gohma")
	var ItemObjects = preload("res://scripts/item_object.gd")
	world.state.take_item(load("res://content/items/bow.tres"))
	world.state.take_item(load("res://content/items/arrows.tres"))
	world.state.rupees = 20
	world.state.selected_item = &"arrows"
	gohma.family.eye_state = 0
	gohma.family.eye_timer = 0
	gohma.family.eye_wait = 200
	var closed = ItemObjects.arrow(gohma.position() + Vector2i(24, 20), Vector2i.UP, 2)
	world.item_objects.append(closed)
	var gohma_health: int = gohma.health
	for i in range(4): world.simulate_tick(Vector2i.ZERO)
	check(gohma.health == gohma_health, "Arrows bounce off Gohma's closed eye")
	gohma.family.eye_timer = 0x40
	gohma.family.eye_state = 3
	gohma.subposition = Vector2i(0x70, 0x70 - 64) * 256
	gohma.family.going_straight = false
	gohma.invulnerability = 0
	world.item_objects.clear()
	world.item_objects.append(ItemObjects.arrow(gohma.position() + Vector2i(13, 12), Vector2i.UP, 2))
	world.simulate_tick(Vector2i.ZERO)
	check(gohma.health < gohma_health, "An arrow flying up into the open eye hurts Gohma")
	# Digdogger: untouchable until the recorder splits it.
	world.enter_room(world.rooms[&"l5_24"], Vector2i(32, 77), Vector2i.RIGHT)
	var digdogger: RefCounted = world.combat.enemies[0]
	for i in range(30): world.simulate_tick(Vector2i.ZERO)
	check(digdogger.definition.size == Vector2i(32, 32) and not digdogger.targetable(), "The big Digdogger cannot be hurt")
	world.state.take_item(load("res://content/items/recorder.tres"))
	world.state.selected_item = &"recorder"
	world.combat.player_invulnerability = 100000
	world.use_item()
	for i in range(0x98 + 0x40 + 4): world.simulate_tick(Vector2i.ZERO)
	var children: Array = world.combat.enemies.filter(func(m: RefCounted) -> bool: return m.definition.id == &"little_digdogger" and m.health > 0)
	check(digdogger.health == 0 and children.size() == digdogger.definition.split_count, "The recorder splits Digdogger into its children")
	check(children.size() > 0 and children[0].targetable(), "Little Digdoggers can be hurt")
	completed = true
