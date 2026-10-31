extends SceneTree
const Fixture = preload("appearance_fixture.gd")
const Pack = preload("../shared/room_pack.gd")
const Ids = preload("../shared/content_ids.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Content ID test timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var source := Pack.sample();Pack.upgrade(source)
	var room: Dictionary = source.rooms.filter(func(r): return not r.pickups.is_empty())[0]
	var pickup: String = room.pickups[0].id
	source.goals = [{"room":room.id,"pickup":pickup}]
	var renamed := Ids.rename_placement(source,room.id,"pickups",pickup,"prize")
	check(renamed.errors.is_empty() and renamed.pack.goals[0].pickup == "prize" and renamed.pack.placement_aliases.pickups[room.id+"/"+pickup] == room.id+"/prize","Pickup rename updates objectives and history")
	check(Pack.validate(renamed.pack).is_empty(),"Placement history validates")
	check(not Ids.rename_placement(renamed.pack,room.id,"pickups","prize",pickup).errors.is_empty(),"Historical placement IDs stay reserved")
	var again: Dictionary = Ids.rename_placement(renamed.pack,room.id,"pickups","prize","reward").pack
	check(again.placement_aliases.pickups == {room.id+"/"+pickup:room.id+"/reward",room.id+"/prize":room.id+"/reward"},"Histories stay flat across repeated renames")
	var broken: Dictionary = again.duplicate(true);broken.placement_aliases.pickups[room.id+"/"+pickup] = "elsewhere/reward"
	check(not Pack.validate(broken).is_empty(),"Aliases must point into the same room")
	var dropped: Dictionary = again.duplicate(true);Pack.RoomIds.retire(dropped,room.id);Ids.rekey_room(dropped,room.id,"");dropped.rooms = dropped.rooms.filter(func(r): return r.id != room.id);dropped.goals = []
	check(dropped.placement_aliases.pickups.is_empty(),"Deleting a room drops its placement history")
	var enemy_type: String = source.enemy_types.keys()[0]
	var variant := Ids.rename_variant(source,enemy_type,"brute",{"enemy_sprites":{enemy_type:"art/lib/beast"}})
	check(variant.errors.is_empty() and variant.pack.enemy_types.has("brute") and not variant.pack.enemy_types.has(enemy_type) and variant.appearance.enemy_sprites.has("brute"),"Variant rename moves definitions and art")
	check(variant.pack.rooms.all(func(r): return r.enemies.all(func(e): return e.type != enemy_type)) and Pack.validate(variant.pack).is_empty(),"Variant rename updates placements")
	check(not Ids.rename_variant(source,enemy_type,enemy_type+"x").errors.is_empty() or source.enemy_types.size() == 1,"Variant collisions are refused")
	var identity: Dictionary = source.duplicate(true);identity.id = "second";Ids.record_identity(identity,"first");Ids.record_identity(identity,"first")
	check(identity.previous_ids == ["first"] and Pack.validate(identity).is_empty(),"Saving under a new pack ID remembers the old one once")
	# GUI: rename, delete reserves, allocation skips reserved, save records identity.
	var folder := Fixture.create()
	var filename := folder.path_join("pack.json")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui);ui.game_root = folder;ui.replace_pack(source,filename,false)
	ui.current_id = room.id;ui.select_placement("pickups",pickup)
	var before: Dictionary = ui.pack.duplicate(true)
	ui.rename_placement("prize")
	check(ui.placement_key.id == "prize" and ui.pack.goals[0].pickup == "prize","GUI renames the selected placement")
	ui.undo();check(ui.pack == before and ui.placement_key.id == pickup,"Undo restores the placement ID")
	ui.redo();ui.delete_placement()
	check(ui.pack.placement_aliases.pickups[room.id+"/prize"] == "" and ui.pack.placement_aliases.pickups[room.id+"/"+pickup] == "","Deleting a placement reserves its history")
	check(ui.unique_placement_id(ui.current().pickups,"item") not in ["prize",pickup],"New placements skip reserved IDs")
	ui.pack.id = "renamed_pack"
	check(ui.save_to(filename) and Pack.read(filename).pack.previous_ids == [source.id],"Saving under a new ID records the published one")
	ui.free();Fixture.remove(folder)
	print("Content ID checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
