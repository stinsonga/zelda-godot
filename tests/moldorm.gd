extends SceneTree
var failures:=0
func _initialize() -> void:
	create_timer(30).timeout.connect(func()->void:push_error("Moldorm suite timed out");quit(1))
	call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:
		failures+=1
		push_error(message)
func run()->void:
	var world=preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var room:Resource=world.room.duplicate()
	room.id=&"worm_fixture"
	room.enemy_persistence="overworld"
	var spawn=preload("res://scripts/enemy_spawn.gd").new()
	spawn.id=&"worms"
	spawn.enemy=preload("res://content/enemies/moldorm.tres")
	spawn.position=Vector2i(128,48)
	room.enemies.assign([spawn])
	world.rooms[room.id]=room
	var temporary:=OS.get_temp_dir().path_join("zelda-moldorm-check-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	world.save_store=preload("res://scripts/save_store.gd").new(temporary)
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	var owner=world.combat.enemies.back()
	var group=owner.family.moldorm
	check(world.combat.enemies.size()==11 and group.chains.size()==2 and world.combat.encounter_total==1,"Moldorm must create two five-segment chains and one persistent encounter")
	var head=group.chains[0].back().get_ref()
	var tail=group.chains[0][0].get_ref()
	check(not owner.targetable() and not owner.can_touch_player(),"The invisible encounter controller must not collide")
	check(head.targetable() and not tail.targetable() and not tail.body_visible(),"Only initialized moving segments may draw or collide")
	for tick in range(16):
		world.combat.player_invulnerability=10000
		world.simulate_tick(Vector2i.ZERO)
	check(head.position()!=Vector2i(128,48) and tail.facing==Vector2i.ZERO,"Head must move at once while the tail remains dormant")
	world.simulate_tick(Vector2i.ZERO)
	check(group.chains[0][3].get_ref().facing!=Vector2i.ZERO and group.chains[0][2].get_ref().facing==Vector2i.ZERO,"Each interval must propagate just one old direction down the chain")
	for tick in range(50):world.simulate_tick(Vector2i.ZERO)
	check(tail.targetable(),"Direction propagation must eventually activate the last tail")
	var heading:Vector2i=head.facing
	var before:Vector2i=head.position()
	world.player.place(head.position()+Vector2i(0,16))
	world.sword.start(preload("res://content/items/wooden_sword.tres"),Vector2i.UP)
	world.sword.phase=1
	world.combat.tick(world)
	world.sword.phase=-1
	world.player.place(Vector2i(32,125))
	before=head.position()
	check(head.health==1 and head.shove_remaining==0,"Real sword collision must preserve surviving segment HP without knockback")
	check(not head.receive_hit(1,Vector2i.RIGHT,"sword"),"Damage cooldown must reject a repeated hit")
	head.invulnerability=0
	check(head.receive_hit(1,Vector2i.RIGHT,"sword") and head.health==2 and tail.health==0 and head.invulnerability==0,"Lethal head damage must remove the tail and restore the fixed head slot")
	check(tail.position()==before and head.position()==before and head.facing==heading,"Tail death must appear at the struck segment while preserving head movement")
	check(group.chains[1].all(func(w:WeakRef)->bool:return w.get_ref().health>0),"Damage to one chain must not shorten the other")
	for tick in range(25):world.simulate_tick(Vector2i.ZERO)
	check(group.resolved_kills()==1 and world.combat.encounter_kills==0,"Segment death must not count as a whole defeated encounter")
	var next_tail=group.chains[0][1].get_ref()
	next_tail.invulnerability=0
	check(next_tail.receive_hit(10,Vector2i.UP,"bomb") and next_tail.health==0,"Directly hitting the current tail must remove that tail")
	for tick in range(25):world.simulate_tick(Vector2i.ZERO)
	room.persistence_enemy_count=8
	check(world.save_game() and world.load_game(),"A partial Moldorm fight must save and load safely")
	check(world.state.room_records[String(room.id)].kills==2,"Checkpoint loading must preserve the original partial kill count")
	var checkpoint_path:String=world.save_store.path_for(world.world_id)
	if FileAccess.file_exists(checkpoint_path):DirAccess.remove_absolute(checkpoint_path)
	DirAccess.remove_absolute(temporary)
	owner=world.combat.enemies.back()
	group=owner.family.moldorm
	check(group.chains[0].all(func(w:WeakRef)->bool:return w.get_ref().health==2),"A partial native encounter must rebuild on entry")
	# Original history stores eight kills even though ten segments are alive.
	room.persistence_enemy_count=8
	for chain in group.chains:
		var h=chain.back().get_ref()
		for hit in range(4):
			h.invulnerability=0
			check(h.receive_hit(100,Vector2i.UP,"sword"),"Fixture must shorten each chain")
	for tick in range(25):world.simulate_tick(Vector2i.ZERO)
	var record:Dictionary=world.combat.persisted_records(world.state)[String(room.id)]
	check(record.kills==8 and record.cleared and not world.room_clear(),"Original eight-kill history cap must be separate from ten-segment room clearance")
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.is_empty(),"An eight-kill source encounter must stay absent while retained in history")
	room.persistence_enemy_count=0
	world.state.room_records.clear()
	world.combat.encounter_room=null
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	owner=world.combat.enemies.back()
	group=owner.family.moldorm
	for chain in group.chains:
		var h=chain.back().get_ref()
		for hit in range(5):h.invulnerability=0;h.receive_hit(100,Vector2i.UP,"sword")
	for tick in range(25):world.simulate_tick(Vector2i.ZERO)
	check(owner.health==0 and world.room_clear() and world.combat.encounter_kills==1 and world.state.kill_cycle==2,"All ten segment deaths must finish the encounter and release room rewards once")
	var variant:Resource=spawn.enemy.duplicate()
	variant.moldorm_chain_count=1
	variant.moldorm_segments_per_chain=3
	variant.boss_turn_ticks=8
	variant.moldorm_segment=variant.moldorm_segment.duplicate()
	variant.moldorm_segment.speed_subpixels=192
	spawn.enemy=variant
	world.state.room_records.clear()
	world.combat.encounter_room=null
	world.enter_room(room,Vector2i(32,125),Vector2i.UP)
	check(world.combat.enemies.size()==4 and world.combat.enemies[0].definition.speed_subpixels==192,"Editable variants must change chain count, length, turn timing, and speed")
	world.free()
	if ResourceLoader.exists("res://imported/enemies/moldorm.tres"):
		world=preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		var found:=0
		for candidate in world.room_resources:
			if not candidate.enemies.any(func(s:Resource)->bool:return s.enemy.behavior=="moldorm"):continue
			world.enter_room(candidate,candidate.spawn,Vector2i.UP)
			check(world.combat.enemies.size()==11 and candidate.persistence_enemy_count==8,"Original room must create ten segments and preserve its history cap")
			owner=world.combat.enemies.back()
			check(owner.position()==Vector2i(128,48),"Original Moldorm must start at ($80,$70)")
			for tick in range(600):
				world.combat.player_invulnerability=10000
				world.simulate_tick(Vector2i.ZERO)
			check(world.combat.enemies.filter(func(a:RefCounted)->bool:return a.targetable()).size()==10,"Original chains must fully emerge and remain active")
			found+=1
		check(found>0,"Original dungeon Moldorm rooms must be imported")
		world.free()
	print("Moldorm checks: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
