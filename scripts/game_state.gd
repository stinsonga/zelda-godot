class_name GameState
extends RefCounted
## Runtime state is separate from content resources and serializes by stable ID.
const HEALTH_UNITS := 128
var spawn_cycle := 0
var room_history: Array[String] = []
var history_cursor := 0
var room_records: Dictionary[String, Dictionary] = {}
var flags: Dictionary[String, bool] = {}
var rupees := 0
## Z_01 World_ChangeRupees applies these one rupee every other frame.
var rupees_to_add := 0
var rupees_to_subtract := 0
var kill_cycle := 0
var max_health := 6
## Half hearts are split into 128 units so rings can reduce damage.
var health_units := 6 * HEALTH_UNITS
var health: int:
	get: return ceili(health_units / float(HEALTH_UNITS))
	set(value): health_units = value * HEALTH_UNITS
var defeated: Dictionary[String, bool] = {}
var equipped_weapon: Resource
var inventory: Dictionary[StringName, Resource] = {}
## Original item slots: grades, counts, or 1 for unique items.
var slots: Dictionary[StringName, int] = {}
var max_bombs := 8
var selected_item: StringName
## Bubbles: a flashing one blocks the sword for $A0 ticks; red curses it until a blue one.
var sword_block_ticks := 0
var sword_cursed := false
## Dungeon level of the current room; 0 outdoors.
var current_level := 0
var collected: Dictionary[String, bool] = {}

func pickup_key(room_id: StringName, pickup_id: StringName) -> String:
	return String(room_id) + "/" + String(pickup_id)

func has_collected(room_id: StringName, pickup_id: StringName) -> bool:
	return collected.has(pickup_key(room_id, pickup_id))

func collect(room_id: StringName, pickup: Resource) -> bool:
	if has_collected(room_id, pickup.id):
		return false
	collected[pickup_key(room_id, pickup.id)] = true
	take_item(pickup.item)
	return true

func item_value(slot: StringName) -> int:
	return slots.get(slot, 0)

## Z_01 TakeItem. Returns false when the item changed nothing.
func take_item(item: Resource) -> bool:
	if not "effect" in item:
		return false
	var before := item_value(item.slot) if "slot" in item and not item.slot.is_empty() else 0
	match item.effect:
		"unique": slots[item.slot] = item.value
		"grade":
			if item.value <= before: return false
			slots[item.slot] = item.value
		"count":
			var cap: int = max_bombs if item.slot == &"bombs" else item.limit
			slots[item.slot] = mini(cap, before + item.value)
		"heart_container":
			if max_health >= 32: return false
			max_health += 2
			health += 2
			return true
		"rupees":
			rupees_to_add += item.amount if "amount" in item else item.value
			return true
		"health":
			health = mini(max_health, health + (item.amount if "amount" in item else item.value))
			return true
		"level":
			var key := level_key(item.slot, current_level)
			if flags.get(key, false): return false
			flags[key] = true
			return true
	inventory[item.id] = item
	if item.slot == &"sword" and (equipped_weapon == null or item.value >= equipped_weapon.value):
		equipped_weapon = item
	if selected_item.is_empty() and item.usable:
		selected_item = item.slot
	return true

func level_key(slot: StringName, level: int) -> String:
	return String(slot) + "/" + str(level)

func has_level_item(slot: StringName, level: int) -> bool:
	return flags.get(level_key(slot, level), false)

## Damage in half hearts. Rings halve or quarter it (Z_07 Link_BeHarmed).
func take_damage(half_hearts: int) -> void:
	var shift := item_value(&"ring")
	health_units = maxi(0, health_units - ((half_hearts * HEALTH_UNITS) >> shift))

func tick_rupees(frame: int) -> bool:
	if rupees == 0: rupees_to_subtract = 0
	if rupees == 255: rupees_to_add = 0
	if frame % 2 != 0 or (rupees_to_add == 0 and rupees_to_subtract == 0): return false
	if rupees_to_add > 0:
		rupees_to_add -= 1
		rupees += 1
	if rupees_to_subtract > 0:
		rupees_to_subtract -= 1
		rupees = maxi(0, rupees - 1)
	return true

func rupees_settled() -> bool:
	return rupees_to_add == 0 and rupees_to_subtract == 0

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
	if room.persistence_enemy_count > 0: return room.enemies.size()
	return maxi(0, room.enemies.size() - int(record.kills))
