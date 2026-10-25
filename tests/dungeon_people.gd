extends SceneTree
## Dungeon residents, shutter triggers, statues, and rupee stashes (Z_01
## InitUnderworldPerson and UpdateRupeeStash_Full, Z_04 UpdateStatues, Z_05
## CheckSecretTrigger). The fixtures are built here and need no ROM; the
## imported checks run with a local import.
const Cave = preload("res://scripts/cave_definition.gd")
const Ware = preload("res://scripts/cave_ware.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
var failures := 0
var world: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Dungeon people suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func tick(count := 1, direction := Vector2i.ZERO) -> void:
	for i in range(count):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(direction)

## A copy of the lab hall with its own ID, optional shutter trigger, and monsters.
func fixture(id: StringName, trigger: int, enemies: Array = []) -> Resource:
	var room: Resource = world.rooms[&"lab_dungeon_hall"].duplicate()
	room.id = id
	room.shutter_trigger = trigger
	room.pickups = Array([], TYPE_OBJECT, "Resource", null)
	room.enemies.assign(enemies)
	world.rooms[id] = room
	return room

func run() -> void:
	world = preload("res://scenes/dungeon_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_shutters()
	check_gate()
	check_bomb_offer()
	check_statues()
	check_rupee_stash()
	world.free()
	check_imported()
	print("Dungeon people checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_shutters() -> void:
	var never: Resource = fixture(&"trigger_0", 0)
	world.enter_room(never, Vector2i(120, 77), Vector2i.UP)
	check(world.monsters_gone() and not world.door_passable(never, never.doors[0]), "Trigger 0 shutters stay shut even with no monsters")
	world.state.flags["shutters/trigger_0"] = true
	check(world.door_passable(never, never.doors[0]), "The gate flag opens trigger 0 shutters")
	var cleared: Resource = fixture(&"trigger_1", 1)
	world.enter_room(cleared, Vector2i(120, 77), Vector2i.UP)
	check(world.door_passable(cleared, cleared.doors[0]), "Trigger 1 shutters open with every monster gone")
	var stairs: Resource = fixture(&"trigger_5", 5)
	world.enter_room(stairs, Vector2i(120, 77), Vector2i.UP)
	check(not world.door_passable(stairs, stairs.doors[0]), "Trigger 5 reveals stairs and opens no shutters")
	check(world.door_passable(world.rooms[&"lab_dungeon_entry"], stairs.doors[0]), "Shutters stay passable from the neighbouring room")

func person(text: String) -> Resource:
	var cave: Resource = Cave.new()
	cave.id = StringName("lab_person_%d" % text.length())
	cave.text = text
	cave.lifts_wares = false
	return cave

func check_gate() -> void:
	var room: Resource = fixture(&"gate_room", 0)
	room.cave = person("ONLY WITH EVERY PIECE.")
	room.cave.triforce_gate = true
	world.state.flags.erase("shutters/gate_room")
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(world.cave_session.person_visible() and world.combat.holds_player() == false, "The gate man waits in his room")
	tick(200)
	check(not world.cave_session.blocks_player() and world.cave_session.visible_text().begins_with("ONLY"), "He types his line, then lets Link move")
	world.player.place(Vector2i(120, 0x8E - 64))
	tick(30, Vector2i.UP)
	# CheckPersonBlocking stops upward moves once Link is above Y $8E.
	check(world.player.pixel_position().y >= 0x8E - 64 - 8, "He blocks the way north while present (%d)" % world.player.pixel_position().y)
	check(not world.door_passable(room, room.doors[0]), "Without the whole triforce his shutters stay shut")
	for level in range(1, 9): world.state.flags["triforce/%d" % level] = true
	check(range(1, 9).all(func(l: int) -> bool: return world.state.has_level_item(&"triforce", l)), "Fixture holds the triforce of levels 1-8")
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(not world.cave_session.person_visible() and world.door_passable(room, room.doors[0]), "With all eight pieces he is gone and the shutters open")
	world.player.place(Vector2i(120, 0x8E - 64))
	tick(30, Vector2i.UP)
	check(world.player.pixel_position().y < 0x8E - 64 - 8, "Nothing blocks Link once he has gone")

func check_bomb_offer() -> void:
	var room: Resource = fixture(&"bomb_room", 0)
	var cave: Resource = person("MORE BOMBS?")
	var ware: Resource = Ware.new()
	ware.item = load("res://content/items/bomb_upgrade.tres")
	ware.price = 100
	cave.wares.assign([null, ware, null])
	for flag in ["choose", "pay", "show_items", "show_prices", "negative_prices", "remember"]: cave.set(flag, true)
	room.cave = cave
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	world.state.rupees = 99
	world.state.max_bombs = 8
	world.state.slots[&"bombs"] = 2
	tick(120)
	world.player.place(Vector2i(0x78, 0x98 - 64))
	tick(5)
	check(world.state.max_bombs == 8, "Fewer than 100 rupees buys nothing")
	world.state.rupees = 100
	tick(3)
	check(world.state.max_bombs == 12 and world.state.item_value(&"bombs") == 12, "100 rupees raise the bomb limit by four and fill it")
	check(world.lift_remaining == 0, "Dungeon offers are handed over without lifting")
	tick(80)
	check(not world.cave_session.person_visible(), "The man leaves after the sale")
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(not world.cave_session.person_visible(), "And stays gone")

func check_statues() -> void:
	var room: Resource = fixture(&"statue_room", 1)
	room.statues = PackedVector2Array([Vector2(0x24 + 4, 0xC0 - 64), Vector2(0xC8 + 4, 0x5C - 64)])
	world.enter_room(room, Vector2i(120, 77), Vector2i.UP)
	var shots := 0
	for i in range(400):
		var before: int = world.combat.rocks.size()
		tick()
		shots += maxi(0, world.combat.rocks.size() - before)
	check(shots >= 2, "Statues shoot fireballs at Link (%d)" % shots)
	check(world.combat.rocks.all(func(r: RefCounted) -> bool: return r.kind == "fireball"), "Statue shots are fireballs")
	# A statue never fires while Link stands within $18 of it.
	world.combat.rocks.clear()
	world.combat.statue_timers = PackedInt32Array([0, 0, 0, 0])
	room.statues = PackedVector2Array([Vector2(124, 77)])
	var fired := false
	for i in range(300):
		world.player.place(Vector2i(120, 77))
		tick()
		if not world.combat.rocks.is_empty(): fired = true
	check(not fired, "No fireball leaves a statue within $18 of Link")
	# Striking a resident turns his fires into shooters.
	var calm: Resource = fixture(&"calm_room", 1)
	calm.cave = person("HELLO")
	calm.provoked_statues = PackedVector2Array([Vector2(76, 66), Vector2(172, 70)])
	world.enter_room(calm, Vector2i(120, 125), Vector2i.UP)
	tick(200)
	check(world.combat.rocks.is_empty() and not world.combat.person_provoked, "A calm resident's fires stay quiet")
	world.state.equipped_weapon = load("res://content/items/wooden_sword.tres")
	world.player.place(Vector2i(120, 0x8E - 64))
	world.player.facing = Vector2i.UP
	world.simulate_tick(Vector2i.ZERO, true)
	tick(12)
	check(world.combat.person_provoked, "The sword provokes the resident")
	world.player.place(Vector2i(120, 125))
	tick(300)
	check(not world.combat.rocks.is_empty() or world.state.health < world.state.max_health, "Then the fires shoot")

func check_rupee_stash() -> void:
	var rupee: Resource = Enemy.new()
	rupee.id = &"lab_stash"
	rupee.behavior = "rupee_stash"
	rupee.spawn_cloud = false
	rupee.contact_damage = 0
	rupee.counts_for_clear = false
	rupee.drops_rewards = false
	rupee.sprite = &"rupee_0"
	var spawns: Array = []
	for i in range(10):
		var spawn: Resource = Spawn.new()
		spawn.id = StringName("rupee_%d" % i)
		spawn.enemy = rupee
		spawn.position = Vector2i(48 + i * 16, 61)
		spawns.append(spawn)
	var room: Resource = fixture(&"stash_room", 1, spawns)
	room.enemy_persistence = "overworld"
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(world.combat.enemies.size() == 10 and world.combat.enemies.all(func(a: RefCounted) -> bool: return not a.targetable() and not a.can_touch_player()), "Ten rupees, untouchable by weapons")
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(world.combat.enemies.size() == 10, "Leaving without taking one keeps them all")
	var before: int = world.state.rupees + world.state.rupees_to_add
	world.player.place(Vector2i(48 + 16 * 3 + 4, 61 + 4))
	tick()
	check(world.state.rupees + world.state.rupees_to_add == before + 1 and world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.health > 0).size() == 9, "Touching one takes one rupee")
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	check(world.combat.enemies.is_empty(), "Taking one counts as taking them all")

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/caves/uw_l9_66.tres"): return
	world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.enter_room(world.rooms[&"l9_66"], Vector2i(120, 125), Vector2i.UP)
	check(world.cave_session != null and world.cave_session.cave.triforce_gate, "The level 9 entrance man guards the gate")
	check(not world.shutters_open(), "His shutters stay shut without the triforce")
	world.enter_room(world.rooms[&"l5_17"], Vector2i(120, 125), Vector2i.UP)
	check(world.room.cave.wares[1].item.id == &"bomb_upgrade" and world.room.cave.wares[1].price == 100, "The level 5 man sells bomb capacity for 100")
	check(world.room.provoked_statues.size() == 2, "His fires can be provoked")
	world.enter_room(world.rooms[&"l4_11"], Vector2i(120, 125), Vector2i.UP)
	check(world.combat.enemies.size() == 10 and world.combat.enemies[0].position() == Vector2i(0x78, 0x70 - 64), "The level 4 stash holds ten rupees")
	var statue_rooms: Array = world.room_resources.filter(func(r: Resource) -> bool: return not r.statues.is_empty())
	check(statue_rooms.size() > 0 and statue_rooms.all(func(r: Resource) -> bool: return r.statues.size() in [2, 4]), "Statue rooms shoot from two or four statues")
	world.free()
