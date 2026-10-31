extends SceneTree
const Pack = preload("../shared/room_pack.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Enemy option test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var pack: Dictionary = JSON.parse_string(JSON.stringify(Pack.sample()));Pack.upgrade(pack)
	var crawler: Dictionary = pack.enemy_types.crawler
	crawler.shooting_enabled = true
	check(Pack.set_enemy_options(crawler,{"drops":"generous","front_shield":true,"immune_to":["arrow","bomb"],"projectile":"boomerang","projectile_damage":2}),"Options need schema 2")
	check(Pack.validate(pack).is_empty(),"Enemy options validate: "+str(Pack.validate(pack)))
	check(Pack.enemy_options(crawler) == {"drops":"generous","front_shield":true,"immune_to":["arrow","bomb"],"projectile":"boomerang","projectile_damage":2},"Options read back")
	for bad in [{"drops":"lots"},{"front_shield":1},{"immune_to":["sword"]},{"immune_to":["arrow","arrow"]},{"projectile":"fireball"},{"projectile_damage":0}]:
		var broken := pack.duplicate(true);broken.enemy_types.crawler.merge(bad,true)
		check(not Pack.validate(broken).is_empty(),"Invalid option rejected: "+str(bad))
	var grounded := pack.duplicate(true);grounded.enemy_types.crawler.erase("shooting_enabled")
	check(not Pack.validate(grounded).is_empty(),"Projectile settings need a shooting walker")
	Pack.set_enemy_options(grounded.enemy_types.crawler,Pack.enemy_options(grounded.enemy_types.crawler))
	check(not grounded.enemy_types.crawler.has("projectile") and Pack.validate(grounded).is_empty(),"Rewriting options drops projectile settings from non-shooters")
	# The variant panel writes options; placement stat edits keep them.
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.replace_pack(JSON.parse_string(JSON.stringify(Pack.sample())),"",false)
	ui.select_room("hall")
	ui.pick(ui.enemy_drops,"none");ui.front_shield.button_pressed = true
	ui.immunity_checks[1].button_pressed = true
	ui.shooting.button_pressed = true;ui.pick(ui.projectile,"arrow");ui.projectile_damage.value = 3
	ui.apply_enemy()
	var edited: Dictionary = ui.pack.enemy_types.crawler
	check(ui.pack.schema == 2 and edited.get("drops") == "none" and edited.get("front_shield") == true and edited.get("immune_to") == ["boomerang"] and edited.get("projectile") == "arrow" and edited.get("projectile_damage") == 3,"The variant panel writes enemy options: "+str(edited))
	check(Pack.validate(ui.pack).is_empty(),"The edited pack validates")
	ui.select_placement("enemies","guard_a")
	ui.placement_inspector.health.value = 9;ui.placement_inspector.apply()
	var copy: Dictionary = ui.pack.enemy_types[ui.selected_placement().type]
	check(copy.health == 9 and copy.get("front_shield") == true and copy.get("immune_to") == ["boomerang"] and copy.get("projectile") == "arrow","A placement's own variant keeps the options: "+str(copy))
	ui.undo();ui.undo()
	check(not ui.pack.enemy_types.crawler.has("front_shield"),"Undo removes the options")
	ui.free()
	print("Enemy option checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
