extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(30).timeout.connect(func() -> void: push_error("Gleeok suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room: Resource = world.room.duplicate()
	room.id = &"neck_fixture"
	room.enemy_persistence = "overworld"
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"boss"
	spawn.enemy = preload("res://content/enemies/gleeok.tres")
	spawn.position = Vector2i(116,23)
	room.enemies.assign([spawn])
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	var body = world.combat.enemies.back()
	var group = body.family.gleeok
	var first = group.heads[0].get_ref()
	var second = group.heads[1].get_ref()
	check(world.combat.enemies.size()==3 and world.combat.encounter_total==1,"A two-neck boss must count as one encounter")
	check(first.position()==Vector2i(124,67) and second.family.gleeok_delay==12,"Necks must begin at the source base and stagger their head delays")
	var before: Vector2i = first.position()
	for tick in range(4):
		world.combat.player_invulnerability=10000
		world.simulate_tick(Vector2i.ZERO)
	check(first.position()!=before and second.position()==before,"Only the selected neck moves; delayed heads must wait")
	check(not body.receive_hit(100,Vector2i.UP,"sword") and body.health==1 and group.writhing>0,"Base hits must cause writhing without killing the body")
	for kind in ["arrow","bomb","fire","magic","boomerang"]:
		check(not first.receive_hit(1,Vector2i.UP,kind),"Attached heads must reject "+kind)
	world.player.place(first.position()+Vector2i(0,16))
	world.sword.start(preload("res://content/items/wooden_sword.tres"),Vector2i.UP)
	world.sword.phase=1
	world.combat.tick(world)
	world.sword.phase=-1
	world.player.place(Vector2i(32,125))
	check(group.head_health==2 and second.health==2,"Real sword collision must damage the shared attached-head HP pool")
	check(not second.receive_hit(1,Vector2i.UP,"sword"),"Shared head damage cooldown must prevent double damage across necks")
	for tick in range(33): world.simulate_tick(Vector2i.ZERO)
	check(first.receive_hit(2,Vector2i.UP,"beam") and first.family.gleeok_detached,"Lethal sword/beam damage must detach the struck head")
	check(not first.targetable() and first.can_touch_player() and body.health>0,"Detached heads must remain dangerous and invulnerable")
	check(group.head_health==2 and second.health==2,"After a detachment the remaining head pool must use its editable reset value")
	before=first.position()
	for tick in range(80): world.simulate_tick(Vector2i.ZERO)
	check(first.position()!=before and first.family.flight_speed>=191,"Detached head must fly without resting")
	check(world.combat.encounter_kills==0 and not world.room_clear(),"A flying head must not persist as a defeated boss")
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	body=world.combat.enemies.back()
	group=body.family.gleeok
	check(group.heads.size()==2 and group.head_health==3 and group.heads.all(func(w: WeakRef)->bool:return not w.get_ref().family.gleeok_detached),"Reentry must rebuild a partial fight")
	for weak_head in group.heads:
		var head=weak_head.get_ref()
		group.hit_timer=0
		check(head.receive_hit(100,Vector2i.UP,"sword"),"Fixture must detach each neck")
	for tick in range(25): world.simulate_tick(Vector2i.ZERO)
	check(body.health==0 and world.combat.enemies.all(func(a: RefCounted)->bool:return a.health==0),"Last neck must kill the body and remove flying heads")
	check(world.combat.encounter_kills==1 and world.room_clear(),"Whole boss must clear once and release room rewards")
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.is_empty(),"Completed boss must remain defeated in room history")
	var variant: Resource=spawn.enemy.duplicate()
	variant.gleeok_neck_count=4
	variant.gleeok_head_delay=3
	spawn.enemy=variant
	world.state.room_records.clear()
	world.combat.encounter_room=null
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.size()==5 and world.combat.enemies[3].family.gleeok_delay==9,"Editable four-neck variant must change count and delay without code changes")
	var shot=preload("res://scripts/rock_projectile.gd").new()
	shot.kind="fireball"
	shot.blockable=false
	shot.magic_blockable=false
	world.state.take_item(preload("res://content/items/magic_shield.tres"))
	check(not world.combat.shield_blocks(world,shot),"Fireball2 must penetrate even the magical shield")
	world.free()
	if ResourceLoader.exists("res://imported/enemies/gleeok_2.tres"):
		world=preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		var found:=0
		for candidate in world.room_resources:
			if not candidate.enemies.any(func(s:Resource)->bool:return s.enemy.behavior=="gleeok"):continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			body=world.combat.enemies.back()
			check(body.position()==Vector2i(116,23),"Imported Gleeok body must use its original fixed position")
			check(world.combat.enemies.size()==body.definition.gleeok_neck_count+1 and body.family.gleeok.head_health==10,"Original boss must import its neck count and initial 10-HP pool")
			for tick in range(300):
				world.combat.player_invulnerability=10000
				world.simulate_tick(Vector2i.ZERO)
			found+=1
		check(found>=2,"Import must populate Gleeok rooms in levels 4 and 8")
		world.free()
	print("Gleeok checks: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
