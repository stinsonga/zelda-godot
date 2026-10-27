extends SceneTree
const Rod = preload("res://content/items/magic_rod.tres")
const Book = preload("res://content/items/book.tres")
const Beam = preload("res://scripts/sword_beam.gd")
const Item = preload("res://scripts/item_object.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(40).timeout.connect(func() -> void: push_error("Rod suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func ticks(count: int) -> void:
	for i in range(count): world.simulate_tick(Vector2i.ZERO)
func place_magic(at: Vector2i = Vector2i(223,77)) -> void:
	world.combat.beam = Beam.new()
	world.combat.beam.kind = "magic"
	world.combat.beam.position = at
	world.combat.beam.direction = Vector2i.RIGHT
	world.combat.beam.damage = 2
	world.combat.beam.speed_subpixels = 640
func run() -> void:
	world = preload("res://scenes/rod_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.save_store = Store.new(OS.get_temp_dir().path_join("zelda-rod-%d" % OS.get_process_id()))
	check(world.room.validation_errors().is_empty() and Rod.validation_errors().is_empty(), "Editable rod lab and weapon validate")
	ticks(1)
	check(world.state.item_value(&"rod") == 1 and world.state.selected_item == &"rod", "Rod pickup enables B selection")
	world.player.place(Vector2i(80,77))
	world.player.facing = Vector2i.RIGHT
	world.state.health = 1
	world.simulate_tick(Vector2i.ZERO,false,true)
	check(world.rod.phase == 0 and world.combat.beam == null, "Rod begins its five-frame preparation without a wave")
	var player_at: Vector2i = world.player.pixel_position()
	for i in range(11): world.simulate_tick(Vector2i.RIGHT)
	check(world.player.pixel_position() == player_at and world.combat.beam == null, "Rod pose holds Link and wave waits through extension")
	ticks(1)
	var wave: RefCounted = world.combat.beam
	check(wave != null and wave.kind == "magic" and wave.position == Vector2i(96,77), "Wave appears sixteen pixels ahead at phase three, even at low health")
	check(world.audio.history.has(&"magic"), "Wave launch emits magic sound")
	if wave == null: world.free(); quit(1); return
	ticks(2)
	check(wave.position == Vector2i(101,77), "Magic moves five pixels every two ticks")
	ticks(3)
	world.state.selected_item = &"rod"
	check(world.use_item(), "Rod can swing while a magic wave is already flying")
	ticks(13)
	check(world.combat.beam == wave, "Further swings cannot replace an active magic wave")
	world.rod.phase = -1
	world.item_objects.append(Item.arrow(Vector2i(120,77),Vector2i.RIGHT,2))
	check(not world.use_item(), "Active arrow occupies rod slot")
	world.item_objects.clear()
	check(world.use_item(), "Rod starts once arrow slot is free")
	world.state.slots[&"arrows"] = 1
	world.state.slots[&"bow"] = 1
	world.state.rupees = 1
	world.state.selected_item = &"arrows"
	check(not world.use_item(), "Rod swing occupies arrow slot")
	world.state.slots.erase(&"arrows")
	world.state.slots.erase(&"bow")
	world.state.selected_item = &"rod"
	world.combat.beam = Beam.new()
	check(world.combat.launch_magic(world) and world.combat.beam.kind == "magic", "Rod wave replaces an existing sword beam")
	world.sword.weapon = preload("res://content/items/wooden_sword.tres")
	check(not world.combat.launch_beam(world), "Magic wave blocks sword-beam slot")
	check_damage()
	check_book()
	world.rod.phase = -1
	world.sword.phase = -1
	world.item_objects.clear()
	world.state.health = world.state.max_health
	world.player.place(world.room.spawn)
	check(world.save_game() and world.load_game() and world.state.item_value(&"rod") == 1 and world.state.item_value(&"book") == 1 and not world.rod.active() and world.combat.beam == null, "Save/load retains rod and book, clearing transient attack")
	world.free()
	print("Rod and book checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
func check_damage() -> void:
	world.combat.beam = null
	world.rod.phase = -1
	world.state.health = world.state.max_health
	world.state.selected_item = &"rod"
	var spawn = Spawn.new()
	spawn.id = &"target"
	spawn.enemy = Enemy.new()
	spawn.enemy.health = 8
	spawn.enemy.speed_subpixels = 0
	spawn.enemy.shoot_cooldown = 0
	spawn.enemy.invincible_to = PackedStringArray(["magic"])
	spawn.position = Vector2i(80,69)
	var actor = Actor.new()
	actor.setup(spawn)
	actor.spawn_remaining = 0
	world.combat.enemies.assign([actor])
	world.combat.player_invulnerability = 10000
	world.use_item()
	world.combat.tick(world)
	check(actor.health == 6, "Rod preparation can deal white-sword melee damage to a magic-immune target")
	world.rod.phase = -1
	actor.invulnerability = 0
	place_magic(Vector2i(84,77))
	world.combat.weapon_hits(world, actor)
	check(actor.health == 6 and world.combat.beam == null, "Magic immunity parries the wave independently of melee")
	world.combat.enemies.clear()
	var terrain = world.room.duplicate(true)
	terrain.tiles = terrain.tiles.replace("#..............#","#......#.......#")
	world.room = terrain
	place_magic(Vector2i(108,77))
	for i in range(5): world.combat.tick_beam(world)
	check(world.combat.beam != null and world.combat.beam.position.x > 112, "Magic ignores interior terrain")
	world.combat.beam = null
	actor.definition = preload("res://content/enemies/ganon.tres")
	actor.health = 15
	check(not actor.receive_hit(2,Vector2i.RIGHT,"rod") and actor.health == 15, "Rod cannot use Ganon's sword-only collision path")
func check_book() -> void:
	world.state.take_item(Book)
	world.room = world.room_resources[0]
	world.player.place(Vector2i(80,125))
	world.rod.phase = -1
	world.candle_used = true
	place_magic()
	world.combat.impact_beam(world)
	check(world.combat.beam == null and world.item_objects.size() == 1, "Book replaces wave impact with fire, without owning a candle")
	var fire: RefCounted = world.item_objects[0]
	check(fire.kind == "fire" and fire.stage == 2 and fire.timer == 79 and world.candle_used, "Book fire starts standing for 79 ticks and preserves candle-use flag")
	ticks(77)
	check(not world.secrets.revealed, "Book fire waits until burning out to reveal a tree secret")
	ticks(1)
	check(world.secrets.revealed, "Book fire burns the authored secret")
	ticks(1)
	check(world.item_objects.is_empty(), "Book fire expires at 79 ticks")
	world.item_objects.assign([Item.bomb(Vector2i(64,64),Vector2i.UP),Item.bomb(Vector2i(96,64),Vector2i.UP)])
	place_magic()
	world.combat.impact_beam(world)
	check(world.item_objects.size() == 2 and world.item_objects.all(func(o:RefCounted)->bool:return o.kind == "bomb"), "Book cannot replace occupied bomb slots")
	world.item_objects.clear()
	var custom_book = Book.duplicate()
	custom_book.use_duration_ticks = 12
	world.item_catalog[&"book"] = custom_book
	world.state.inventory[&"book"] = custom_book
	place_magic()
	world.combat.impact_beam(world)
	check(world.item_objects[0].timer == 12, "Authored book changes fire lifetime")
	world.item_objects.clear()
	world.item_catalog[&"book"] = Book
	world.state.inventory[&"book"] = Book
	var dark = world.room.duplicate(true)
	dark.dark_room = true
	world.enter_room(dark,Vector2i(80,125),Vector2i.UP,0,true)
	place_magic()
	world.combat.impact_beam(world)
	ticks(1)
	check(world.lighting.fading(), "Standing book fire lights a dark room")
	world.lighting.stage = 0
	world.lighting.steps.clear()
	world.item_objects.clear()
