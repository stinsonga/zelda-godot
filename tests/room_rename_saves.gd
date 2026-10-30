extends SceneTree
const Pack = preload("res://editor/shared/room_pack.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
const Store = preload("res://scripts/save_store.gd")
const Migration = preload("res://scripts/room_save_migration.gd")
var failures := 0
var temporary: String
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	temporary = OS.get_temp_dir().path_join("zelda-room-migration-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	create_timer(30).timeout.connect(func(): push_error("Room migration checks timed out");quit(1))
	call_deferred("run")
func make_world(pack: Dictionary) -> Node:
	var compiled := Adapter.compile(pack);check(compiled.errors.is_empty(),"Pack with aliases compiles")
	for room in compiled.world.rooms:
		if not room.enemies.is_empty(): room.enemy_persistence = "permanent"
	var game = preload("res://scenes/main.tscn").instantiate();game.use_imported_world = false;game.world_definition = compiled.world
	root.add_child(game);game.set_physics_process(false);game.save_store = Store.new(temporary)
	return game
func dispose(game: Node) -> void:
	for actor in game.combat.enemies: actor.source.tile_probe = Callable()
	game.combat.enemies.clear();game.combat.encounter_room = null;game.free()
func write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func run() -> void:
	var loaded := Pack.read("res://content/packs/ember_relay.json");var source: Dictionary = loaded.pack
	source.rooms[2].secret.trigger = "bomb"
	var old := make_world(source)
	old.enter_room(old.rooms[&"room_2"],Vector2i(120,125),Vector2i.UP)
	old.player.subposition.x+=128;old.player.facing = Vector2i.LEFT
	old.state.rupees = 23;old.state.health = 5
	old.state.collected["entry/item_1"] = true;old.state.collected["room_3/item_1"] = true;old.state.collected["room_2/item_1"] = true;old.state.collected["room_2/taken"] = true
	old.state.collected["room_20/item_1"] = true
	old.state.defeated["room_1/enemy_1"] = true
	for flag in ["door/entry/up","door/room_1/down","secret/room_2","shutters/room_2","visited/room_2","quest/room_2","secretive/room_2","authored/complete"]: old.state.flags[flag] = true
	old.state.room_history.assign(["entry","room_1","room_2","room_3"]);old.state.history_cursor = 4
	old.state.room_records["room_1"] = {"kills":1,"cleared":false};old.state.room_records["room_2"] = {"kills":0,"cleared":true}
	var original: Dictionary = old.snapshot();check(old.save_game(),"Pre-rename checkpoint writes")
	var path: String = old.save_store.path_for(old.world_id);var bytes := FileAccess.get_file_as_bytes(path);var world_id: String = old.world_id;var position: Vector2i = old.player.subposition
	dispose(old)
	var pack: Dictionary = source.duplicate(true)
	for pair in [["entry","landing"],["room_1","watch"],["room_2","relay"],["room_3","store"],["relay","sanctum"]]:
		var result := Pack.rename_room(pack,pair[0],pair[1]);check(result.errors.is_empty(),"Reference-aware rename succeeds");pack = result.pack
	var current := make_world(pack)
	check(current.world_id==world_id and current.save_store.path_for(current.world_id)==path,"Room renames keep checkpoint world identity and filename")
	check(current.load_game(),"Old checkpoint loads after repeated room renames")
	check(current.room.id==&"sanctum" and current.player.subposition==position and current.player.facing==Vector2i.LEFT,"Current room, fractional position and facing migrate")
	check(current.state.rupees==23 and current.state.health==5,"Inventory counters and health survive")
	check(current.state.has_collected(&"landing",&"item_1") and current.state.has_collected(&"store",&"item_1") and current.state.has_collected(&"sanctum",&"taken"),"Pickup and resident transaction keys migrate")
	check(current.state.collected.has("room_20/item_1") and not current.state.collected.has("entry/item_1"),"Only exact room prefixes change")
	check(current.state.flags.has("door/landing/up") and current.state.flags.has("door/watch/down") and current.state.flags.has("shutters/sanctum") and current.state.flags.has("visited/sanctum"),"Door, shutter and visited flags migrate")
	check(current.secrets.revealed and current.state.flags.has("secret/sanctum"),"Persistent secret remains revealed natively")
	check(current.state.flags.has("quest/room_2") and current.state.flags.has("secretive/room_2") and current.state.flags.has("authored/complete"),"Global and unknown flag namespaces are opaque")
	check(current.state.room_history==["landing","watch","sanctum","store"] and current.state.history_cursor==4,"History order and cursor survive normal migration")
	check(current.state.room_records.watch.kills==1 and current.state.room_records.sanctum.cleared,"Kill records migrate")
	check(current.state.defeated.has("watch/enemy_1"),"Permanent enemy defeat key migrates")
	var rupees: int = current.state.rupees;current.player.place(Vector2i(96,77))
	for i in range(5): current.simulate_tick(Vector2i.ZERO)
	check(current.state.rupees==rupees and current.state.has_collected(&"sanctum",&"item_1"),"Renamed reward cannot be collected again")
	check(FileAccess.get_file_as_bytes(path)==bytes,"Loading never rewrites player's checkpoint")
	current.enter_room(current.rooms[&"watch"],Vector2i(120,125),Vector2i.UP)
	check(current.combat.enemies.size()==1,"Defeated permanent monster stays absent in renamed room")
	current.enter_room(current.rooms[&"sanctum"],Vector2i(120,125),Vector2i.UP)
	check(current.save_game(),"Next explicit save writes current room IDs")
	var saved: Dictionary = current.save_store.read_snapshot(world_id)
	check(saved.data.room_id=="sanctum" and "landing/item_1" in saved.data.collected and "door/landing/up" in saved.data.flags,"Resaved checkpoint uses current IDs")
	dispose(current)
	pack = Pack.rename_room(pack,"sanctum","relic_hall").pack
	current = make_world(pack);check(current.load_game() and current.room.id==&"relic_hall","A newer checkpoint survives another rename")
	var broken := FileAccess.open(path,FileAccess.WRITE);broken.store_string("{broken");broken.close()
	check(current.load_game() and current.room.id==&"relic_hall" and current.status_message=="BACKUP SAVE LOADED","Old-ID backup recovers into latest room identity")
	for version in [1,2]:
		var historical: Dictionary = original.duplicate(true);historical.version = version
		for key in ["slots","max_bombs","selected_item"]: historical.erase(key)
		write(path,historical)
		check(current.load_game() and current.room.id==&"relic_hall" and current.state.has_collected(&"landing",&"item_1"),"Version %d checkpoint migrates room IDs" % version)
	var too_long: Dictionary = original.duplicate(true)
	too_long.collected.append("entry/"+"x".repeat(250))
	check(current.save_store.validate(too_long,world_id).ok,"Boundary-length old save is structurally valid")
	write(path,too_long)
	var untouched: RefCounted = current.state
	check(not current.load_game() and current.state==untouched and current.status_message.contains("MIGRATED SAVE"),"Invalid migrated field cannot partially replace the live session")
	var large: Dictionary = original.duplicate(true);large.collected = []
	for i in 10000: large.collected.append("room_2/"+str(i)+"x".repeat(85))
	check(current.save_store.write_snapshot(large,world_id).ok,"Near-limit checkpoint is valid before room-prefix expansion")
	check(not current.load_game() and current.state==untouched and current.status_message.contains("TOO LARGE"),"Oversized migrated snapshot fails before replacing the session")
	var ring: Dictionary = original.duplicate(true)
	ring.room_history = ["entry","room_1","room_2","room_3","room_20","unused"];ring.history_cursor = 3
	var full_ring := Migration.remap(ring,pack.room_aliases)
	check(full_ring.history_cursor==3 and full_ring.room_history==["landing","watch","relic_hall","store","room_20","unused"],"Full history ring retains its physical order and cursor without collisions")
	var mixed: Dictionary = original.duplicate(true)
	mixed.collected.append("sanctum/item_1");mixed.defeated.append("watch/enemy_1")
	mixed.room_history = ["entry","landing","room_1","room_2","sanctum","room_3"];mixed.history_cursor = 2
	mixed.room_records.watch = {"kills":2,"cleared":true}
	var migrated := Migration.remap(mixed,pack.room_aliases)
	check(migrated.collected.count("relic_hall/item_1")==1 and migrated.defeated.count("watch/enemy_1")==1,"Mixed old/current progress is deduplicated")
	check(migrated.room_records.watch.kills==2 and migrated.room_records.watch.cleared,"Colliding records preserve maximum progress")
	check(migrated.room_history==["watch","relic_hall","store","landing"] and migrated.history_cursor==4,"Alias collisions retain recent history and valid ring cursor")
	check(current.save_store.validate(migrated,world_id).ok and Migration.remap(migrated,pack.room_aliases)==migrated,"Migration yields valid, idempotent snapshots")
	check(mixed.room_history[0]=="entry","Migration does not modify source snapshot")
	write(path,original)
	var retired: Dictionary = pack.duplicate(true);Pack.RoomIds.retire(retired,"relic_hall")
	retired.rooms = retired.rooms.filter(func(room): return room.id!="relic_hall");retired.goals = []
	for room in retired.rooms:
		for edge in room.connections.keys():
			if room.connections[edge].target=="relic_hall": room.connections.erase(edge)
	dispose(current);current = make_world(retired)
	var before: RefCounted = current.state
	check(not current.load_game() and current.state==before and current.status_message.contains("ROOM IS UNAVAILABLE"),"Deleted renamed room fails safely without redirecting checkpoint")
	dispose(current)
	for filename in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary.path_join(filename))
	DirAccess.remove_absolute(temporary)
	print("Room rename checkpoint checks: ","PASS" if failures==0 else "FAIL");call_deferred("finish")
func finish() -> void: quit(0 if failures==0 else 1)
