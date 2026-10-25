class_name GameState
extends RefCounted
## Runtime state is separate from content resources and serializes by stable ID.
var spawn_cycle := 0
var room_history: Array[String] = []
var history_cursor := 0
var room_records: Dictionary[String, Dictionary] = {}
var flags: Dictionary[String, bool] = {}
var rupees := 0
var kill_cycle := 0
var max_health := 6
var health := 6
var defeated: Dictionary[String, bool] = {}
var equipped_weapon: Resource
var inventory: Dictionary[StringName, Resource] = {}
var collected: Dictionary[String, bool] = {}

func pickup_key(room_id: StringName, pickup_id: StringName) -> String:
	return String(room_id) + "/" + String(pickup_id)

func has_collected(room_id: StringName, pickup_id: StringName) -> bool:
	return collected.has(pickup_key(room_id, pickup_id))

func collect(room_id: StringName, pickup: Resource) -> bool:
	if has_collected(room_id, pickup.id):
		return false
	collected[pickup_key(room_id, pickup.id)] = true
	inventory[pickup.item.id] = pickup.item
	equipped_weapon = pickup.item
	return true

func heart_frame(index: int) -> int:
	var remaining := health - index * 2
	if remaining >= 2: return 0
	if remaining == 1: return 1
	return 2

func history_key(room: Resource) -> String:
	return String(room.history_id) if not room.history_id.is_empty() else String(room.id)

func visit_room(room: Resource) -> void:
	if not room.tracks_history: return
	var key := history_key(room)
	if key in room_history: return
	if room_history.size() < 6:
		room_history.append(key)
		history_cursor = room_history.size() % 6
	else:
		room_history[history_cursor] = key
		history_cursor = (history_cursor + 1) % 6

func prepare_overworld_room(room: Resource, restoring: bool = false) -> int:
	var key := String(room.id)
	# Version 1 snapshots recorded individual enemy IDs. Translate known IDs
	# once into the original count model; no array addresses enter the save.
	var legacy_count := 0
	for spawn in room.enemies:
		var legacy_key := key + "/" + String(spawn.id)
		if defeated.has(legacy_key):
			legacy_count += 1
			defeated.erase(legacy_key)
	if not room_records.has(key):
		room_records[key] = {"kills": legacy_count, "cleared": legacy_count > 0 and legacy_count >= room.enemies.size()}
	var record: Dictionary = room_records[key]
	if record.cleared and not restoring and history_key(room) not in room_history:
		record = {"kills": 0, "cleared": false}
		room_records[key] = record
	if record.cleared: return 0
	return maxi(0, room.enemies.size() - int(record.kills))
