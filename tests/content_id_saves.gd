extends "res://tests/room_rename_saves.gd"
## Placement and pack renames: old checkpoints keep their progress.
const Ids = preload("res://editor/shared/content_ids.gd")
func run() -> void:
	var source: Dictionary = Pack.read("res://content/packs/ember_relay.json").pack
	var old := make_world(source)
	old.state.collected["room_2/item_1"] = true;old.state.collected["room_3/item_1"] = true
	old.state.defeated["room_1/enemy_1"] = true
	check(old.save_game(),"Checkpoint writes before renames")
	var old_world: String = old.world_id
	dispose(old)
	var pack: Dictionary = source.duplicate(true)
	for step in [["room_2","pickups","item_1","relay_prize"],["room_2","pickups","relay_prize","ember"],["room_1","enemies","enemy_1","sentry"]]:
		var result := Ids.rename_placement(pack,step[0],step[1],step[2],step[3])
		check(result.errors.is_empty(),"Placement rename succeeds: "+str(result.errors));pack = result.pack
	var moved := Pack.rename_room(pack,"room_2","relay");check(moved.errors.is_empty(),"Room rename keeps placement history valid: "+str(moved.errors));pack = moved.pack
	check(pack.placement_aliases.pickups == {"relay/item_1":"relay/ember","relay/relay_prize":"relay/ember"},"Placement history follows the room rename")
	pack.id = "ember_relay_deluxe";Ids.record_identity(pack,"ember_relay")
	check(Pack.validate(pack).is_empty(),"Renamed pack validates: "+str(Pack.validate(pack)))
	var current := make_world(pack)
	check(current.world_id != old_world and current.previous_world_ids == PackedStringArray([old_world]),"A renamed pack remembers its old world ID")
	check(current.load_game(),"The old pack ID's checkpoint loads")
	check(current.state.has_collected(&"relay",&"ember") and current.state.has_collected(&"room_3",&"item_1"),"Renamed pickups keep their collection")
	check(current.state.defeated.has("room_1/sentry") and not current.state.defeated.has("room_1/enemy_1"),"Renamed enemies stay defeated")
	check(current.save_game() and FileAccess.file_exists(current.save_store.path_for(current.world_id)),"The next save writes under the new pack ID")
	dispose(current)
	DirAccess.remove_absolute(temporary)
	print("Content ID save checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
