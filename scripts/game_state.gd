class_name GameState
extends RefCounted
## Session state is separate from content resources. Saving is a later milestone.
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
