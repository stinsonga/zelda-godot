extends SceneTree
var failures := 0
const Main = preload("res://scenes/main.tscn")
func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: push_error("Manhandla checks timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room: Resource = world.room.duplicate()
	room.id = &"multipart_fixture"
	room.enemy_persistence = "overworld"
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"boss"
	spawn.enemy = preload("res://content/enemies/manhandla.tres")
	spawn.position = Vector2i(120,77)
	room.enemies.assign([spawn])
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.size() == 5 and world.combat.encounter_total == 1,"Multipart boss must create four hands but count as one persistent encounter")
	var body = world.combat.enemies.back()
	var group = body.family.manhandla
	check(not body.receive_hit(100,Vector2i.UP,"bomb") and body.health == 2,"Body must survive direct damage")
	var hand = world.combat.enemies[0]
	check(not hand.receive_hit(1,Vector2i.UP,"fire") and not hand.receive_hit(1,Vector2i.UP,"boomerang"),"Hands must reject fire and boomerangs")
	check(hand.receive_hit(1,Vector2i.UP,"sword") and hand.health == 1,"Hands must accept sword damage independently")
	check(world.combat.enemies[1].health == 2,"One hand's damage must not affect another")
	check(not hand.receive_hit(1,Vector2i.UP,"sword"),"A hand's damage timer must reject repeated hits")
	hand.invulnerability = 0
	hand.receive_hit(1,Vector2i.UP,"bomb")
	world.combat.player_invulnerability = 10000
	for tick in range(25): world.simulate_tick(Vector2i.ZERO)
	check(group.speed == 256 and body.health > 0,"Destroying one hand must accelerate the boss without killing its body")
	check(world.combat.encounter_kills == 0 and int(world.combat.persisted_records(world.state)[String(room.id)].kills) == 0,"Hand deaths must not persist as a cleared boss")
	for part in world.combat.enemies:
		if part.health > 0: check(part.shove_remaining == 0,"Boss movement must ignore weapon knockback")
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.size() == 5 and world.combat.enemies.slice(0,4).all(func(a: RefCounted) -> bool: return a.health == 2),"Leaving a partially defeated boss must rebuild all hands")
	body = world.combat.enemies.back()
	group = body.family.manhandla
	# Original bomb shape can damage several hands during one detonation.
	var bomb = preload("res://scripts/item_object.gd").bomb(body.position(),Vector2i.UP)
	bomb.stage = 3
	bomb.timer = 8
	world.item_objects.append(bomb)
	world.tick_item_objects()
	check(world.combat.enemies.slice(0,4).all(func(a: RefCounted) -> bool: return a.health == 0),"A centered bomb must damage all four hands")
	for tick in range(25): world.simulate_tick(Vector2i.ZERO)
	check(body.health == 0 and world.combat.encounter_kills == 1 and world.room_clear(),"Last hand must kill the body and clear exactly one persistent encounter")
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.is_empty(),"A cleared boss must stay defeated while retained in room history")
	group = null
	body = null
	hand = null
	world.free()
	if ResourceLoader.exists("res://imported/enemies/manhandla.tres"):
		world = Main.instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		var boss_room: Resource
		for candidate in world.room_resources:
			if candidate.dungeon_level != 3: continue
			if candidate.enemies.any(func(s: Resource) -> bool: return s.enemy.behavior == "manhandla"): boss_room = candidate; break
		check(boss_room != null,"Level 3 must import its Manhandla encounter")
		if boss_room != null:
			world.enter_room(boss_room,boss_room.spawn,Vector2i.UP)
			check(world.combat.enemies.size() == 5,"Original encounter must create all five parts")
			for tick in range(1200):
				world.combat.player_invulnerability = 10000
				world.simulate_tick(Vector2i.ZERO)
			check(world.combat.rocks.size() <= world.combat.projectile_limit,"Manhandla shots must respect the common projectile cap")
			for a in world.combat.enemies:
				if a.definition.boss_hand == null: a.health = 0; a.death_remaining = 0
			for tick in range(25): world.simulate_tick(Vector2i.ZERO)
			check(world.room_clear(),"Defeating imported hands must release the boss room")
		world.free()
	print("Manhandla checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
