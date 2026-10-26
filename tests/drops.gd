extends SceneTree
## Monster drops (Z_04 SetUpDroppedItem, Z_01 HandleMonsterDied) and room items
## carried by monsters (Z_07 MoveAndDrawRoomItem). The fixtures need no ROM; the
## imported checks run with a local import.
const Loot = preload("res://scripts/loot_table.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Pickup = preload("res://scripts/pickup_definition.gd")
const Combat = preload("res://scripts/combat_simulation.gd")
var failures := 0
var world: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func() -> void: push_error("Drops suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func tick(count := 1) -> void:
	for i in range(count):
		world.combat.player_invulnerability = 100000
		world.simulate_tick(Vector2i.ZERO)

func run() -> void:
	world = preload("res://scenes/dungeon_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	check_counters()
	check_drop_order()
	check_carried_item()
	world.free()
	check_imported()
	print("Drops checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_counters() -> void:
	var state: RefCounted = world.state
	state.reset_help_drops()
	for i in range(9): state.note_kill(false)
	state.note_kill(true)
	check(state.help_drop_count == 10 and state.help_drop_bomb and state.world_kill_count == 10, "The tenth kill by bomb sets up a bomb drop")
	state.note_kill(false)
	check(state.help_drop_count == 10 and state.world_kill_count == 11, "The help counter stops at ten; the kill count goes on")
	state.health = state.max_health
	state.take_damage(1)
	check(state.help_drop_count == 0 and not state.help_drop_bomb and state.world_kill_count == 0, "Any hurt resets both counters")

func check_drop_order() -> void:
	var state: RefCounted = world.state
	var heart: Resource = load("res://content/items/heart.tres")
	var never: Resource = Loot.new()
	never.chance = 0
	never.entries.assign([heart])
	var always: Resource = Loot.new()
	always.chance = 256
	always.entries.assign([heart])
	state.reset_help_drops()
	check(world.combat.original_drop(world, never, 0) == null, "The row's rate can cancel a drop")
	check(world.combat.original_drop(world, always, 0) == heart, "Otherwise the kill-cycle entry drops")
	state.help_drop_count = 10
	check(world.combat.original_drop(world, never, 255) == Combat.FIVE_RUPEE_DROP and state.help_drop_count == 0, "A full help counter guarantees five rupees")
	state.help_drop_count = 10
	state.help_drop_bomb = true
	check(world.combat.original_drop(world, never, 255) == Combat.BOMB_DROP and not state.help_drop_bomb, "After a bomb kill it guarantees a bomb")
	state.world_kill_count = 0x10
	state.help_drop_count = 4
	check(world.combat.original_drop(world, always, 0) == Combat.FAIRY_DROP and state.help_drop_count == 0 and state.world_kill_count == 0x10, "The sixteenth kill brings the fairy and keeps counting")
	state.world_kill_count = 0
	# Taking a dropped bomb gives the bombs item.
	state.max_bombs = 8
	state.slots[&"bombs"] = 0
	var reward = preload("res://scripts/dropped_reward.gd").new()
	reward.definition = Combat.BOMB_DROP
	reward.age = 40
	reward.take(state)
	check(state.item_value(&"bombs") == 4, "A dropped bomb adds four bombs")

func check_carried_item() -> void:
	var room: Resource = world.rooms[&"lab_dungeon_hall"].duplicate()
	room.id = &"carrier_room"
	room.enemy_persistence = "reset"
	var spawn: Resource = Spawn.new()
	spawn.id = &"carrier"
	spawn.enemy = load("res://content/enemies/lab_skeleton.tres")
	spawn.position = Vector2i(64, 77)
	room.enemies.assign([spawn])
	var key: Resource = Pickup.new()
	key.id = &"item"
	key.item = load("res://content/items/key.tres")
	key.position = Vector2i(176, 106)
	key.tolerance = Vector2i(8, 8)
	key.lift_ticks = 0
	key.carrier_slot = 1
	room.pickups.assign([key])
	world.rooms[room.id] = room
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	tick(60)
	var carrier: RefCounted = world.combat.enemies[0]
	check(world.pickup_position(key) == carrier.position() - Vector2i(0, 3), "The room item rides on the slot-1 monster")
	var keys: int = world.state.item_value(&"keys")
	world.player.place(carrier.position())
	tick()
	check(world.state.item_value(&"keys") == keys + 1, "Touching the carrier takes the item")
	world.enter_room(world.rooms[&"lab_dungeon_entry"], Vector2i(120, 77), Vector2i.UP)
	world.state.collected.erase(world.state.pickup_key(room.id, key.id))
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	tick(60)
	carrier = world.combat.enemies[0]
	carrier.receive_hit(carrier.health, Vector2i.UP, "sword")
	var fallen: Vector2i = carrier.position()
	tick(40)
	check(world.pickup_position(key) == fallen - Vector2i(0, 3), "The item stays where its carrier fell")

func check_imported() -> void:
	if not ResourceLoader.exists("res://imported/rooms/l1_33.tres"): return
	world = preload("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room: Resource = world.rooms[&"l1_33"]
	var item: Resource = room.pickups[0]
	check(item.carrier_slot == 1 and room.enemies[0].enemy.nes_type == 0x2A, "Level 1's key Stalfos carries the room item")
	world.enter_room(room, Vector2i(120, 125), Vector2i.UP)
	tick(80)
	var carrier: RefCounted = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.slot == 1)[0]
	check(world.pickup_position(item) == carrier.position() - Vector2i(0, 3), "The key moves with the Stalfos")
	check(load("res://imported/enemies/gel.tres").drops_rewards == false and load("res://imported/enemies/blue_keese.tres").drops_rewards == false and load("res://imported/enemies/like_like.tres").drops_rewards == false, "Gels, Keese, and Like Likes drop nothing")
	check(world.loot_tables.values().any(func(t: Resource) -> bool: return t.entries.has(Combat.BOMB_DROP)), "Drop rows include bombs")
	# A Dodongo's death guarantees a bomb.
	var dodongo_room: Resource = world.room_resources.filter(func(r: Resource) -> bool: return r.enemies.any(func(s: Resource) -> bool: return s.enemy.behavior == "dodongo"))[0]
	world.enter_room(dodongo_room, dodongo_room.spawn, Vector2i.UP)
	tick(40)
	var dodongo: RefCounted = world.combat.enemies.filter(func(a: RefCounted) -> bool: return a.definition.behavior == "dodongo")[0]
	dodongo.health = 0
	dodongo.death_remaining = 1
	tick(3)
	check(world.combat.rewards.any(func(r: RefCounted) -> bool: return r.definition == Combat.BOMB_DROP), "Dodongo leaves a bomb")
	# Triforce pieces sit 8 pixels left of their item position.
	var triforce_room: Resource = world.room_resources.filter(func(r: Resource) -> bool: return r.dungeon_level == 1 and r.pickups.any(func(p: Resource) -> bool: return p.item.id == &"triforce"))[0]
	check(triforce_room.pickups.filter(func(p: Resource) -> bool: return p.item.id == &"triforce")[0].position.x % 16 == 8, "The triforce piece is shifted left 8 pixels")
	world.free()
