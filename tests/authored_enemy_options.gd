extends SceneTree
## Pack enemy options reach the game's enemy definitions.
const Pack = preload("res://editor/shared/room_pack.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void:
	var pack: Dictionary = Pack.sample();Pack.upgrade(pack)
	pack.enemy_types["guard"] = {"title":"Guard","behavior":"walker","health":4,"speed_subpixels":128,"contact_damage":2,"shooting_enabled":true,"drops":"generous","front_shield":true,"immune_to":["arrow","magic"],"projectile":"boomerang","projectile_damage":2}
	pack.enemy_types["husk"] = {"title":"Husk","behavior":"gel","health":1,"speed_subpixels":64,"contact_damage":1,"drops":"none"}
	var hall: Dictionary = pack.rooms.filter(func(r): return r.id == "hall")[0]
	hall.enemies[0].type = "guard";hall.enemies[1].type = "husk"
	var compiled := Adapter.compile(pack)
	check(compiled.errors.is_empty(),"Pack with enemy options compiles: "+str(compiled.errors))
	if not compiled.errors.is_empty(): quit(1);return
	var definitions: Dictionary = {}
	for room in compiled.world.rooms:
		for spawn in room.enemies: definitions[spawn.enemy.title] = spawn.enemy
	var guard: Resource = definitions.Guard;var husk: Resource = definitions.Husk
	check(guard.drops_rewards and guard.loot_table.chance == 256 and guard.front_shield and Array(guard.invincible_to) == ["arrow","magic"],"Drops, shield and immunities reach the definition")
	check(guard.projectile_kind == "boomerang" and guard.projectile_damage == 2 and guard.validation_errors().is_empty(),"Projectile settings reach the definition")
	check(not husk.drops_rewards and not husk.front_shield and husk.projectile_kind == "rock","Defaults stay as before, and drops can be turned off")
	print("Authored enemy option checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
