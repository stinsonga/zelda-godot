extends SceneTree
const Reward = preload("res://scripts/dropped_reward.gd")
const Clock = preload("res://content/items/clock.tres")
const Fairy = preload("res://content/items/fairy.tres")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
const Item = preload("res://scripts/item_object.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("Clock and fairy suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	world = preload("res://scenes/reward_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.save_store = Store.new(OS.get_temp_dir().path_join("zelda-clock-fairy-%d" % OS.get_process_id()))
	check(world.room.validation_errors().is_empty() and world.combat.rewards.size() == 2, "ROM-free room spawns validated rewards")
	check(world.audio.history.has(&"item"), "Fairy appearance plays item cue")
	world.combat.enemies.clear()
	var clock: RefCounted = world.combat.rewards[0]
	world.player.place(Vector2i(80,122))
	for i in range(31): world.simulate_tick(Vector2i.ZERO)
	check(not world.state.clock_active and not clock.collected, "Clock cannot be picked up during its initial delay")
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.clock_active and clock.collected, "Clock pickup activates room effect")
	var hp: int = world.state.health
	check(not world.combat.hurt_player(world,4,world.player.pixel_position()) and world.state.health == hp, "Clock prevents damage")
	var at: Vector2i = world.player.pixel_position()
	world.simulate_tick(Vector2i.LEFT)
	check(world.player.pixel_position() != at, "Clock leaves Link free to move")
	for i in range(600): world.simulate_tick(Vector2i.ZERO)
	check(world.state.clock_active, "Clock lasts beyond reward expiry without a countdown")
	check(world.save_game() and world.load_game() and not world.state.clock_active, "Checkpoint retains no transient clock")
	world.state.clock_active = true
	world.enter_room(world.room,world.room.spawn,Vector2i.UP)
	check(not world.state.clock_active, "Room entry clears clock")
	check_clock_actors()
	check_fairy()
	check_weapons()
	world.free()
	print("Clock and fairy checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
func check_clock_actors() -> void:
	var spawn = Spawn.new()
	spawn.id = &"clock_test"
	spawn.enemy = preload("res://content/enemies/red_octorok.tres").duplicate()
	spawn.position = Vector2i(120,77)
	spawn.facing = Vector2i.RIGHT
	var actor = Actor.new()
	actor.setup(spawn)
	actor.spawn_remaining = 0
	var origin: Vector2i = actor.position()
	for i in range(240):
		check(not actor.tick(Vector2i(192,77),func(_at: Vector2i)->bool:return true,Callable(),true,{"clock":true}), "Frozen actor cannot shoot")
	check(actor.position() == origin, "Clock holds Octorok movement indefinitely")
	world.state.clock_active = true
	world.combat.enemies.assign([actor])
	for i in range(30): world.simulate_tick(Vector2i.ZERO)
	check(actor.position() == origin and world.combat.rocks.is_empty(), "World combat applies clock freeze before movement or shooting")
	var fireball = preload("res://scripts/rock_projectile.gd").new()
	fireball.kind = "fireball"
	fireball.subposition = world.player.subposition
	fireball.velocity = Vector2i(256,0)
	fireball.direction = Vector2i.RIGHT
	fireball.age = 16
	var projectile_start: Vector2i = fireball.position()
	world.combat.tick_fireball(world,fireball)
	check(fireball.alive and fireball.position() != projectile_start, "Existing fireball keeps moving and passes protected Link")
	actor.definition = actor.definition.duplicate()
	actor.definition.contact_effect = "curse_sword"
	world.state.sword_cursed = false
	world.combat.touch_player(world,actor)
	check(not world.state.sword_cursed and world.captor == null, "Clock rejects contact status effects")

	check(actor.receive_hit(1,Vector2i.RIGHT,"sword"), "Frozen monster still takes sword damage")
	actor.health = 0
	actor.death_remaining = 2
	actor.tick(Vector2i.ZERO,func(_at: Vector2i)->bool:return true,Callable(),true,{"clock":true})
	check(actor.death_remaining == 1, "Clock permits death animation")
	for behavior in ["walker","jumper","burrower","flyer","rope","blue_wizzrobe","red_wizzrobe","aquamentus","digdogger","moldorm","moldorm_segment"]:
		actor.definition = Enemy.new()
		actor.definition.behavior = behavior
		check(actor.affected_by_clock(), "Source clock freezes " + behavior)
	for behavior in ["trap","dodongo","gohma","manhandla","gleeok","patra","ganon"]:
		actor.definition = Enemy.new()
		actor.definition.behavior = behavior
		check(not actor.affected_by_clock(), "Source exception " + behavior)
	actor.definition.clock_response = "freeze"
	check(actor.affected_by_clock(), "Authored variant can freeze source exception")
	actor.definition.clock_response = "immune"
	check(not actor.affected_by_clock(), "Authored variant can ignore clock")
func check_fairy() -> void:
	var fairy = Reward.new()
	fairy.definition = Fairy
	fairy.position = Vector2i(120,77)
	var start: Vector2i = fairy.position
	for i in range(33): fairy.tick(Rect2i(17,14,207,127),255)
	check(fairy.position.y < start.y and fairy.speed == 160 and fairy.available(), "Fairy begins upward flight, accelerates to A0 and becomes collectible")
	var after: Vector2i = fairy.position
	world.state.clock_active = true
	world.combat.rewards.assign([fairy])
	world.combat.enemies.clear()
	world.player.place(Vector2i(32,141))
	world.simulate_tick(Vector2i.ZERO)
	check(fairy.position != after or fairy.fraction != 0, "Clock does not freeze fairy flight")
	world.state.max_health = 32
	world.state.health_units = 7 * 128 + 32
	fairy.take(world.state)
	check(world.state.health_units == 13 * 128 + 32, "Fairy heals three hearts while preserving fractional ring damage")
	fairy.collected = false
	world.state.health = 31
	fairy.take(world.state)
	check(world.state.health == 32, "Fairy healing respects heart capacity")
	var custom = Fairy.duplicate()
	custom.lifetime_ticks = 10
	custom.pickup_delay_ticks = 2
	fairy = Reward.new()
	fairy.definition = custom
	fairy.tick(Rect2i(17,14,207,127),0)
	check(not fairy.available(), "Custom pickup delay applies")
	fairy.tick(Rect2i(17,14,207,127),0)
	check(fairy.available(), "Custom reward becomes available")
	for i in range(8): fairy.tick(Rect2i(17,14,207,127),0)
	check(not fairy.available(), "Custom lifetime expires")
	fairy = Reward.new()
	fairy.definition = Fairy
	fairy.position = Vector2i(120,14)
	for i in range(3): fairy.tick(Rect2i(17,14,207,127),255)
	check(fairy.direction == 4, "Fairy reverses at the room boundary")
	var invalid = Fairy.duplicate()
	invalid.frame_ticks = 0
	check(not invalid.validation_errors().is_empty(), "Invalid reward settings are rejected")

	world.state.world_kill_count = 16
	var table = preload("res://scripts/loot_table.gd").new()
	table.chance = 0
	check(world.combat.original_drop(world,table,255) == Fairy, "Sixteenth kill guarantees fairy even when ordinary drop chance is zero")
func check_weapons() -> void:
	world.state.clock_active = false
	world.combat.rewards.clear()
	world.player.place(Vector2i(32,125))
	var reward = world.combat.spawn_reward(world,Clock,Vector2i(120,77))
	reward.age = 32
	world.tick_thrown(Item.arrow(reward.position,Vector2i.RIGHT,1))
	check(reward.collected and world.state.clock_active, "Arrow can collect clock")
	reward = world.combat.spawn_reward(world,Fairy,Vector2i(120,77))
	reward.age = 32
	world.state.health = 2
	world.tick_thrown(Item.boomerang(reward.position,Vector2i.RIGHT,49))
	check(reward.collected and world.state.health == 8, "Boomerang can collect flying fairy")
