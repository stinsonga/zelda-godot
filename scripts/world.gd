extends Node2D

const Room = preload("res://scripts/room_definition.gd")
const Player = preload("res://scripts/player.gd")
const Saves = preload("res://scripts/save_store.gd")
const HUD_HEIGHT := 64
const ROOM_SIZE := Vector2i(256, 176)
const ItemObject = preload("res://scripts/item_object.gd")
## Original submenu order; the potion and letter share one cell.
const B_ITEM_ORDER: Array[StringName] = [&"boomerang", &"bombs", &"arrows", &"candle", &"recorder", &"bait", &"potion", &"letter", &"rod"]
## Z_05 CheckPersonBlocking: in caves, Link cannot walk up above Y $8E.
const CAVE_PERSON_LINE := 0x8E - HUD_HEIGHT
## Item-use pose length is provisional; it matches the sword's 16-tick wield.
const ITEM_USE_TICKS := 16

@export var item_resources: Array[Resource] = [preload("res://content/items/wooden_sword.tres")]
@export var scroll_transitions: bool = true
@export var world_definition: Resource
@export var use_imported_world: bool = true
@export var room_resources: Array[Resource] = [
	preload("res://content/rooms/test_field.tres"),
	preload("res://content/rooms/expansion_field.tres")]
@export var visual_theme: Resource = preload("res://content/themes/default.tres")
var audio = preload("res://scripts/game_audio.gd").new()
var world_id := ""
var item_catalog: Dictionary[StringName, Resource] = {}
var save_store = Saves.new()
var status_message := ""
var status_ticks := 0
var transition: RefCounted
var loot_tables: Dictionary[StringName, Resource] = {}
var rooms: Dictionary = {}
var state = preload("res://scripts/game_state.gd").new()
var combat = preload("res://scripts/combat_simulation.gd").new()
var sword = preload("res://scripts/sword_action.gd").new()
var attack_requested := false
var item_requested := false
var cave_session: RefCounted
var secrets = preload("res://scripts/secret_runtime.gd").new()
var item_objects: Array[RefCounted] = []
var candle_used := false
var item_use_remaining := 0
var portal_armed := true
var rise_remaining := 0
var rise_square := Rect2i()
var legacy_ids: Dictionary[String, String] = {}
var overrides: Dictionary = {}
var level_exit_remaining := 0
## A Like Like or Wallmaster holding Link.
var captor: RefCounted
const DIRECTION_NAMES := {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}
var simulation_tick := 0
var entry_walk_remaining := 0
var entry_walk_subpixels := 0
var entry_direction := Vector2i.UP
var dialogue_elapsed := 0
var lift_remaining := 0
var lifted_item: Resource
var pickup_ticks: Dictionary[String, int] = {}
var walk_ticks := 0
var walk_pose := 0
var room: Resource
var player = Player.new()
var held: Array[Vector2i] = []
@onready var font := ThemeDB.fallback_font

func _ready() -> void:
	add_child(audio)
	var start_id: StringName = &""
	var selected_world: Resource = world_definition
	if selected_world == null and use_imported_world and ResourceLoader.exists("res://imported/world.tres"):
		selected_world = load("res://imported/world.tres")
	if selected_world != null:
		room_resources = selected_world.rooms
		visual_theme = selected_world.visual_theme
		start_id = selected_world.start_room
		loot_tables = selected_world.loot_tables
		combat.spawn_lists = selected_world.spawn_lists
		combat.projectile_limit = selected_world.projectile_limit
		legacy_ids = selected_world.legacy_ids
		world_id = String(selected_world.id)
		item_resources = item_resources + selected_world.items
	audio.configure(selected_world.audio_bank if selected_world != null else null, selected_world != null and String(selected_world.id) == "original_quest_1")
	assert(not room_resources.is_empty(), "World must contain rooms")
	for definition in room_resources:
		var errors: PackedStringArray = definition.validation_errors()
		assert(errors.is_empty(), str(errors))
		assert(not rooms.has(definition.id), "Duplicate room ID")
		rooms[definition.id] = definition
	for definition in room_resources:
		for target in definition.exits.values():
			assert(rooms.has(StringName(target)), "Missing exit destination: " + target)
		for portal in definition.portals:
			assert(rooms.has(portal.target_room), "Missing portal destination")
	assert(start_id.is_empty() or rooms.has(start_id), "Starting room is missing")
	var first_room: Resource = rooms[start_id] if not start_id.is_empty() else room_resources[0]
	if world_id.is_empty(): world_id = "native/" + String(first_room.id)
	for item in item_resources: register_item(item)
	for definition in room_resources:
		for pickup in definition.pickups: register_item(pickup.item)
		if definition.cave != null:
			for ware in definition.cave.wares:
				if ware != null and ware.item != null and "slot" in ware.item: register_item(ware.item)
	enter_room(first_room, first_room.spawn, Vector2i.UP)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:
		return
	var direction := Vector2i.ZERO
	match event.physical_keycode:
		KEY_UP, KEY_W: direction = Vector2i.UP
		KEY_DOWN, KEY_S: direction = Vector2i.DOWN
		KEY_LEFT, KEY_A: direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
		KEY_M:
			if event.pressed:
				audio.muted = not audio.muted
				audio.apply_pause()
		KEY_F5:
			if event.pressed: save_game()
		KEY_F9:
			if event.pressed: load_game()
		KEY_ENTER:
			if event.pressed and state.health == 0:
				state.health = state.max_health
				combat.player_invulnerability = 48
				enter_room(room, room.spawn, Vector2i.UP)
		KEY_Z, KEY_SPACE:
			if event.pressed:
				attack_requested = true
		KEY_X, KEY_SHIFT:
			if event.pressed:
				item_requested = true
		KEY_C, KEY_TAB:
			# Provisional selection until the original submenu exists.
			if event.pressed:
				cycle_item()
		KEY_R:
			if event.pressed and transition == null:
				player.place(room.spawn)
	if direction != Vector2i.ZERO:
		held.erase(direction)
		if event.pressed:
			held.append(direction)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		audio.suspended = false
		audio.apply_pause()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		audio.suspended = true
		audio.apply_pause()
		held.clear()
		attack_requested = false
		item_requested = false

func _physics_process(_delta: float) -> void:
	status_ticks = maxi(0, status_ticks - 1)
	var direction: Vector2i = Vector2i.ZERO if held.is_empty() else held.back()
	simulate_tick(direction, attack_requested, item_requested)
	attack_requested = false
	item_requested = false
	queue_redraw()

func enter_room(target: Resource, at: Vector2i, facing: Vector2i, entry_walk: int = 0, restoring: bool = false, rise: int = 0) -> void:
	if not restoring: combat.commit_room(state)
	transition = null
	room = target
	player.grid_origin = room.grid_origin
	player.place(at + Vector2i(0, rise))
	player.facing = facing
	entry_walk_remaining = entry_walk
	entry_walk_subpixels = entry_walk * 256
	entry_direction = facing
	dialogue_elapsed = 0
	walk_ticks = 0
	walk_pose = 0
	sword.phase = -1
	item_objects.clear()
	captor = null
	candle_used = false
	item_use_remaining = 0
	rise_remaining = rise * 4
	rise_square = Rect2i(at.x, at.y + 3, 16, 16)
	portal_armed = true
	state.current_level = room.dungeon_level
	secrets.enter(room, state)
	overrides = compute_overrides(room)
	cave_session = null
	if room.cave != null:
		cave_session = preload("res://scripts/cave_session.gd").new()
		cave_session.start(room.cave, room.id, state, combat.source_random)
	combat.enter_room(room, state, restoring, at, facing)
	state.visit_room(room)
	audio.set_music(room.music)

func dialogue_visible() -> bool:
	if cave_session != null:
		return cave_session.visible_text() != "" or cave_session.phase in ["prices", "text"]
	return not room.dialogue.is_empty() and (room.dialogue_until_pickup.is_empty() or not state.has_collected(room.id, room.dialogue_until_pickup))

func simulate_tick(direction: Vector2i, attack_pressed: bool = false, item_pressed: bool = false) -> void:
	simulation_tick += 1
	combat.advance_frame()
	if state.tick_rupees(simulation_tick):
		audio.play(&"heart")
	state.sword_block_ticks = maxi(0, state.sword_block_ticks - 1)
	if state.health <= 0:
		return
	if transition != null:
		if transition.tick():
			enter_room(transition.target, transition.destination, transition.direction)
		return
	if level_exit_remaining > 0:
		level_exit_remaining -= 1
		if level_exit_remaining == 0: leave_level()
		return
	tick_item_objects()
	tick_captor()
	overrides = compute_overrides(room)
	# Link updates before objects: a lift started by the resident counts from
	# the next tick, and the resident keeps updating during a lift.
	var lifting := lift_remaining > 0
	var cave_halts := false
	if cave_session != null and entry_walk_remaining == 0:
		cave_session.tick(self)
		cave_halts = cave_session.blocks_player()
	if lift_remaining > 0:
		if lifting: lift_remaining -= 1
		return
	if rise_remaining > 0:
		# Z_07 StepOutside: up one pixel every four ticks, then free to move.
		rise_remaining -= 1
		if rise_remaining % 4 == 0: player.subposition.y -= 256
		portal_armed = false
		return
	var before: Vector2i = player.pixel_position()
	if entry_walk_remaining > 0:
		# Mode 4 walks stop exactly on the target, unlike carried free movement.
		var budget := mini(Player.SPEED_SUBPIXELS, entry_walk_subpixels)
		player.step(entry_direction, can_occupy, can_enter_segment, budget)
		entry_walk_subpixels -= budget
		entry_walk_remaining = ceili(entry_walk_subpixels / 256.0)
		assert(player.pixel_position() != before, "Portal entry walk is blocked")
	elif cave_halts:
		return
	elif cave_session == null and dialogue_visible() and dialogue_elapsed < room.dialogue.length() * room.dialogue_character_ticks:
		dialogue_elapsed += 1
		return
	elif combat.shove_remaining > 0:
		combat.move_shoved_player(self)
		combat.tick(self)
		return
	elif sword.active():
		sword.tick()
		combat.tick(self)
		return
	elif item_use_remaining > 0:
		item_use_remaining -= 1
		combat.tick(self)
		return
	elif attack_pressed and state.sword_block_ticks == 0 and not state.sword_cursed and sword.start(state.equipped_weapon, player.facing):
		audio.play(&"attack")
		combat.tick(self)
		return
	elif item_pressed and use_item():
		combat.tick(self)
		return
	else:
		if captor == null and not secrets.blocks_player(player.pixel_position()):
			player.step(direction, can_occupy, can_enter_segment)
		if secrets.try_push(self, direction):
			overrides = compute_overrides(room)
		try_doors(direction)
	if player.pixel_position() != before:
		walk_ticks += 1
		if walk_ticks >= 6:
			walk_ticks = 0
			walk_pose = 1 - walk_pose
	if entry_walk_remaining > 0:
		return
	if not portal_armed and player.pixel_position() != before:
		portal_armed = true
	if try_portal(direction, before):
		return
	try_exit(direction)
	if transition != null:
		return
	try_pickups()
	if lift_remaining == 0:
		combat.tick(self)

func try_portal(direction: Vector2i, from: Vector2i = Vector2i(-1000, -1000)) -> bool:
	if not portal_armed:
		return false
	for portal in room.portals:
		if not portal.area.has_point(player.pixel_position()) and not passed_through(portal.area, from, player.pixel_position()):
			continue
		if portal.requires_secret and not secrets.revealed:
			continue
		if portal.required_direction != Vector2i.ZERO and portal.required_direction != direction:
			continue
		var target: Resource = rooms[portal.target_room]
		if occupiable_in(target, portal.target_position):
			enter_room(target, portal.target_position, portal.target_facing, portal.entry_walk_pixels, false, portal.exit_rise_pixels)
			# Z_05 CheckWarps waits until Link leaves an arrival square.
			portal_armed = not target_has_portal_at(target, player.pixel_position())
			return true
	return false

## Movement carries across grid points, but CheckWarps runs at each one, so
## an entrance crossed during this tick's straight step still counts.
func passed_through(area: Rect2i, from: Vector2i, to: Vector2i) -> bool:
	if from == to or (from.x != to.x and from.y != to.y): return false
	# The starting point does not count: stepping off an arrival square never warps.
	var step := (to - from).sign()
	var first := from + step
	var low := Vector2i(mini(first.x, to.x), mini(first.y, to.y))
	var high := Vector2i(maxi(first.x, to.x), maxi(first.y, to.y))
	return area.intersects(Rect2i(low, high - low + Vector2i.ONE))

## Occupancy in another room, with that room's remembered secrets applied.
func occupiable_in(target: Resource, at: Vector2i) -> bool:
	var previous: Resource = room
	var previous_overrides := overrides
	room = target
	overrides = compute_overrides(target)
	var valid := can_occupy(at)
	room = previous
	overrides = previous_overrides
	return valid

func target_has_portal_at(target: Resource, at: Vector2i) -> bool:
	for portal in target.portals:
		if portal.area.has_point(at): return true
	return false

func try_pickups() -> void:
	for pickup in room.pickups:
		if pickup.requires_clear and not room_clear():
			continue
		var distance: Vector2i = (player.pixel_position() - pickup.position).abs()
		if distance.x > pickup.tolerance.x or distance.y > pickup.tolerance.y:
			continue
		if state.collect(room.id, pickup):
			audio.play(&"item_fanfare" if pickup.lift_ticks > 0 else &"item")
			lifted_item = pickup.item
			lift_remaining = pickup.lift_ticks
			pickup_ticks[state.pickup_key(room.id, pickup.id)] = simulation_tick
			if "slot" in pickup.item and pickup.item.slot == &"triforce":
				# Z_05 mode $12: the fanfare plays, hearts refill, then Link leaves the level.
				state.health = state.max_health
				audio.play(&"item_fanfare")
				level_exit_remaining = 192
			return

## Doors and secrets replace 16-pixel squares and their collision.
func compute_overrides(definition: Resource) -> Dictionary:
	var result: Dictionary = secrets.overrides(definition, state)
	for door in definition.doors:
		if not door_passable(definition, door): continue
		for i in range(door.cells.size()):
			var cell := Vector2i(door.cells[i] % 16, door.cells[i] / 16)
			if result.has(cell): continue
			var bits: int = door.open_collision[i]
			result[cell] = [door.open_tiles[i], PackedByteArray([bits & 1, bits >> 1 & 1, bits >> 2 & 1, bits >> 3 & 1]), "door"]
	return result

func door_key(definition: Resource, direction: Vector2i) -> String:
	return "door/" + String(definition.id) + "/" + DIRECTION_NAMES[direction]

## Z_05 TouchDoor: false walls let Link through, key and bombable doors stay
## open once opened, and shutters open while the room is clear.
func door_passable(definition: Resource, door: Resource) -> bool:
	match door.kind:
		"open", "false": return true
		"key", "bombable": return state.flags.get(door_key(definition, door.direction), false)
		"shutter": return definition != room or room_clear()
	return false

## Z_05 CheckHasLivingMonsters: Bubbles and traps do not count.
func monsters_gone() -> bool:
	for actor in combat.enemies:
		if actor.health > 0 and actor.definition.counts_for_clear: return false
	return true

## Z_05 CheckSecretTrigger: no living monsters, and a pushed block where required.
func room_clear() -> bool:
	return monsters_gone() and (room.shutter_trigger != 4 or secrets.revealed)

## Opening a door also opens the facing door in the next room.
func open_door(door: Resource) -> void:
	state.flags[door_key(room, door.direction)] = true
	var name: String = DIRECTION_NAMES[door.direction]
	if room.exits.has(name) and rooms.has(StringName(room.exits[name])):
		state.flags[door_key(rooms[StringName(room.exits[name])], -door.direction)] = true
	audio.play(&"door")
	overrides = compute_overrides(room)

## Z_05 TouchDoorKey: pressing into a locked doorway spends a key; the magical key is never spent.
func try_doors(direction: Vector2i) -> void:
	var at: Vector2i = player.pixel_position()
	for door in room.doors:
		if door.kind != "key" or direction != door.direction or door_passable(room, door) or not door.in_doorway(at): continue
		if state.item_value(&"magic_key") == 0:
			if state.item_value(&"keys") == 0: continue
			state.slots[&"keys"] -= 1
		open_door(door)

## Z_04 UpdateLikeLike and UpdateWallmaster: a Like Like holds Link where he
## stands; a Wallmaster carries him, and finishing its path restarts the level.
func tick_captor() -> void:
	if captor == null: return
	if captor.health <= 0 or captor not in combat.enemies:
		captor = null
		return
	if captor.definition.behavior == "wallmaster":
		player.place(captor.position())
		if captor.family.carried_out:
			captor = null
			restart_level()
		return
	captor.subposition = player.subposition
	captor.capture_ticks += 1
	if captor.capture_ticks == 0x60:
		state.slots.erase(&"magic_shield")

## Z_07 mode 3: back to the level's first room, walking in from its entrance.
func restart_level() -> void:
	for definition in rooms.values():
		if definition.dungeon_level != room.dungeon_level: continue
		for portal in definition.portals:
			if rooms.has(portal.target_room) and rooms[portal.target_room].dungeon_level == 0:
				enter_room(definition, Vector2i(120, 157), Vector2i.UP, 16)
				return

## After a triforce, return to the level's overworld entrance.
func leave_level() -> void:
	for definition in rooms.values():
		if definition.dungeon_level != room.dungeon_level: continue
		for portal in definition.portals:
			if rooms.has(portal.target_room) and rooms[portal.target_room].dungeon_level == 0:
				enter_room(rooms[portal.target_room], portal.target_position, portal.target_facing, 0, false, portal.exit_rise_pixels)
				return

func take_cave_item(item: Resource) -> void:
	# Z_01 TakeItem: caves always lift the item for 128 frames with the fanfare.
	state.take_item(item)
	audio.play(&"item_fanfare")
	lifted_item = item
	lift_remaining = 128

func tick_item_objects() -> void:
	for object in item_objects:
		var cue: StringName = object.tick()
		if not cue.is_empty(): audio.play(cue)
		if not object.active: continue
		for actor in combat.enemies:
			if actor.targetable() and object.hits(actor.hit_position()):
				if actor.receive_hit(object.damage(), object.direction, object.kind):
					audio.play(&"enemy_hit")
					if actor.health == 0:
						audio.play(&"enemy_die")
						combat.record_permanent_kill(self, actor)
		# Z_07 UpdateFire: Link's own fire harms him, centers closer than $0E.
		if object.kind == "fire":
			var delta: Vector2i = (object.position - player.pixel_position()).abs()
			if delta.x < 0x0E and delta.y < 0x0E:
				combat.hurt_player(self, 1, object.position)
	for object in item_objects:
		if not object.detonating(): continue
		for door in room.doors:
			if door.kind != "bombable" or door_passable(room, door): continue
			var delta: Vector2i = (door.bomb_hotspot() - object.position).abs()
			if delta.x < 0x18 and delta.y < 0x18: open_door(door)
	item_objects = item_objects.filter(func(object: RefCounted) -> bool: return object.active)
	secrets.update(self)

func use_item() -> bool:
	var slot: StringName = state.selected_item
	if slot.is_empty() or state.item_value(slot) == 0:
		return false
	var ahead: Vector2i = player.pixel_position() + player.facing * 16
	match slot:
		&"bombs":
			# Z_01 WieldBomb: a bomb may replace a fire, but waits for another
			# bomb to detonate before a second one is set.
			var bombs: Array = item_objects.filter(func(object: RefCounted) -> bool: return object.kind == "bomb")
			if bombs.size() >= 2 or bombs.any(func(object: RefCounted) -> bool: return object.stage < 3):
				return false
			if item_objects.size() >= 2:
				item_objects.erase(item_objects.filter(func(object: RefCounted) -> bool: return object.kind == "fire")[0])
			state.slots[&"bombs"] -= 1
			item_objects.append(ItemObject.bomb(ahead, player.facing))
			audio.play(&"bomb_drop")
			ensure_selected_item()
		&"candle":
			# Z_01 WieldCandle: two slots; the blue candle burns once per room.
			if item_objects.size() >= 2 or (state.item_value(&"candle") == 1 and candle_used):
				return false
			candle_used = true
			item_objects.append(ItemObject.fire(ahead, player.facing))
			audio.play(&"flame")
		&"potion":
			# Provisional: the original refills gradually while Link waits.
			state.health = state.max_health
			state.slots[&"potion"] -= 1
			audio.play(&"heart")
			ensure_selected_item()
			return true
		&"letter":
			return cave_session != null and cave_session.show_letter(self)
		_:
			return false
	item_use_remaining = ITEM_USE_TICKS
	return true

func available_items() -> Array[StringName]:
	var result: Array[StringName] = []
	for slot in B_ITEM_ORDER:
		if slot == &"letter" and state.item_value(&"potion") > 0: continue
		if state.item_value(slot) > 0 and item_for_slot(slot) != null: result.append(slot)
	return result

## Z_07 EnsureSelectedItem: move off an item that has run out.
func ensure_selected_item() -> void:
	if state.item_value(state.selected_item) == 0: cycle_item()

func cycle_item() -> void:
	var options := available_items()
	if options.is_empty():
		state.selected_item = &""
		return
	state.selected_item = options[(options.find(state.selected_item) + 1) % options.size()]

## The catalog item drawn for a slot's current value.
func item_for_slot(slot: StringName) -> Resource:
	var value := state.item_value(slot)
	var fallback: Resource = null
	for item in item_catalog.values():
		if not "slot" in item or item.slot != slot: continue
		if item.value == value: return item
		if item.effect == "count": fallback = item
	return fallback

func decoration_visible(decoration: Resource) -> bool:
	if decoration.hide_after_pickup.is_empty() or not state.has_collected(room.id, decoration.hide_after_pickup):
		return true
	var key: String = state.pickup_key(room.id, decoration.hide_after_pickup)
	return pickup_ticks.has(key) and simulation_tick - pickup_ticks[key] < 64

func is_blocked(pixel: Vector2i) -> bool:
	if not overrides.is_empty() and Rect2i(Vector2i.ZERO, ROOM_SIZE).has_point(pixel):
		var override: Variant = overrides.get(pixel / 16)
		if override != null:
			return override[1][(pixel.x % 16) / 8 * 2 + (pixel.y % 16) / 8] != 0
	if room.is_pixel_solid(pixel):
		return true
	for decoration in room.decorations:
		if decoration_visible(decoration) and decoration.blocking_area.has_point(pixel):
			return true
	return false

func can_occupy(at: Vector2i) -> bool:
	# Z_07 GetCollidableTileStill: y + $0B, two eight-pixel columns.
	if not room.movement_bounds.has_point(at):
		return false
	return not is_blocked(at + Vector2i(0, 11)) and not is_blocked(at + Vector2i(8, 11))

func can_enter_segment(at: Vector2i, direction: Vector2i) -> bool:
	if not room.movement_bounds.has_point(at + direction * 8):
		return false
	if room.cave != null and direction == Vector2i.UP and at.y < CAVE_PERSON_LINE:
		return false
	# Z_07 GetCollidingTileMoving / GetCollidableTile. At grid points,
	# horizontal movement checks one leading column at the foot hotspot;
	# vertical movement checks both columns, eight pixels ahead of it.
	var probe := at + Vector2i(0, 11)
	if direction.x != 0:
		probe.x += 16 if direction.x > 0 else -8
		return not is_blocked(probe)
	probe.y += 8 if direction.y > 0 else -8
	return not is_blocked(probe) and not is_blocked(probe + Vector2i(8, 0))

func try_exit(direction: Vector2i) -> void:
	var at: Vector2i = player.pixel_position()
	var edge := ""
	var bounds: Rect2i = room.movement_bounds
	if at.x == bounds.position.x and direction == Vector2i.LEFT: edge = "left"
	elif at.x == bounds.end.x - 1 and direction == Vector2i.RIGHT: edge = "right"
	elif at.y == bounds.position.y and direction == Vector2i.UP: edge = "up"
	elif at.y == bounds.end.y - 1 and direction == Vector2i.DOWN: edge = "down"
	if not room.exits.has(edge):
		return
	var target: Resource = rooms[StringName(room.exits[edge])]
	var destination := at
	match edge:
		"left": destination.x = target.movement_bounds.end.x - 1
		"right": destination.x = target.movement_bounds.position.x
		"up": destination.y = target.movement_bounds.end.y - 1
		"down": destination.y = target.movement_bounds.position.y
	if not occupiable_in(target, destination): return
	if not scroll_transitions:
		enter_room(target, destination, direction)
		return
	transition = preload("res://scripts/room_transition.gd").new()
	transition.source = room
	transition.target = target
	transition.source_position = at
	transition.destination = destination
	transition.direction = direction
	player.facing = direction
	# Transient projectiles and loose drops cannot leak into the next room.
	combat.beam = null
	combat.rocks.clear()
	combat.rewards.clear()
	sword.phase = -1

func _draw() -> void:
	if room == null:
		return
	draw_rect(Rect2(0, 0, 256, 240), Color("171c20"))
	if visual_theme.hud_tiles:
		draw_original_hud()
	else:
		draw_string(font, Vector2(12, 18), "REPRODUCTION LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, visual_theme.accent_color)
		draw_string(font, Vector2(170, 18), "%s/3  $%d" % [state.health / 2.0, state.rupees], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ed7770"))
		draw_string(font, Vector2(12, 34), room.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(font, Vector2(12, 50), "ARROWS / WASD    Z: SWORD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("a6b4bb"))
	if status_ticks > 0:
		draw_rect(Rect2(0, 53, 256, 11), Color.BLACK)
		draw_string(font, Vector2(8, 62), status_message, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color.WHITE)
	if transition != null:
		draw_scrolling_rooms()
		return
	draw_terrain(room, Vector2.ZERO)
	draw_pushed_object()
	draw_room_objects()
	draw_item_objects()
	draw_combat()
	if rise_remaining > 0:
		draw_rising_player()
	elif combat.player_invulnerability == 0 or simulation_tick % 4 < 2:
		var at: Vector2 = Vector2(player.pixel_position()) + Vector2(0, HUD_HEIGHT)
		if lift_remaining > 0 and visual_theme.sprites.has(&"lift"):
			draw_named_sprite(&"lift", Vector2(player.pixel_position()))
			draw_named_sprite(item_sprite(lifted_item), Vector2(player.pixel_position()) - Vector2(4, 16))
		elif (sword.active() or item_use_remaining > 0) and visual_theme.sprites.has(StringName("attack_" + direction_name(player.facing))):
			var facing: Vector2i = sword.direction if sword.active() else player.facing
			draw_named_sprite(StringName("attack_" + direction_name(facing)), Vector2(player.pixel_position()) + Vector2(0, 2))
		elif visual_theme.player_sheet:
			var direction := 0
			if player.facing == Vector2i.LEFT: direction = 1
			elif player.facing == Vector2i.DOWN: direction = 2
			elif player.facing == Vector2i.UP: direction = 3
			var frame := direction * 2 + walk_pose
			# Z_07 applies a two-pixel overworld drawing offset, independent of collision.
			draw_texture_rect_region(visual_theme.player_sheet, Rect2(at + Vector2(0, 2), Vector2(16, 16)), Rect2(frame * visual_theme.player_sheet.get_width() / 8.0, 0, visual_theme.player_sheet.get_width() / 8.0, visual_theme.player_sheet.get_height()))
		elif visual_theme.player_texture:
			draw_texture_rect(visual_theme.player_texture, Rect2(at, Vector2(16, 16)), false)
		else:
			draw_rect(Rect2(at + Vector2(3, 2), Vector2(10, 13)), visual_theme.player_color)
			draw_rect(Rect2(at + Vector2(4, 5), Vector2(8, 5)), visual_theme.accent_color)
			draw_line(at + Vector2(8, 8), at + Vector2(8, 8) + Vector2(player.facing) * 7, Color("263b32"), 2)

		if sword.visible():
			draw_named_sprite(sword_sprite(sword.weapon, sword.direction), Vector2(player.pixel_position() + sword.offset()))

	if state.health == 0:
		draw_rect(Rect2(0, 64, 256, 176), Color(0, 0, 0, 0.75))
		if visual_theme.hud_tiles:
			draw_hud_text("GAME OVER", Vector2(88, 112))
			draw_hud_text("ENTER TO RETRY", Vector2(72, 136))
		else:
			draw_string(font, Vector2(60, 120), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			draw_string(font, Vector2(50, 144), "ENTER TO RETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func sword_sprite(weapon: Resource, direction: Vector2i) -> StringName:
	var prefix: String = String(weapon.sprite_prefix) if "sprite_prefix" in weapon and not weapon.sprite_prefix.is_empty() else "sword"
	return StringName(prefix + "_" + direction_name(direction))

func item_sprite(item: Resource) -> StringName:
	return item.sprite_name() if item.has_method("sprite_name") else item.id

## Z_07 StepOutside draws Link behind the background; only the doorway shows him.
func draw_rising_player() -> void:
	if not visual_theme.player_sheet: return
	var width: float = visual_theme.player_sheet.get_width() / 8.0
	var frame := 4 + (simulation_tick / 6) % 2
	var at := Vector2(player.pixel_position()) + Vector2(0, HUD_HEIGHT + 2)
	var destination := Rect2(at, Vector2(16, 16))
	var visible := destination.intersection(Rect2(Vector2(rise_square.position) + Vector2(0, HUD_HEIGHT), Vector2(rise_square.size)))
	if not visible.has_area(): return
	var source := Rect2(frame * width + (visible.position.x - at.x) * width / 16.0, visible.position.y - at.y, visible.size.x * width / 16.0, visible.size.y)
	draw_texture_rect_region(visual_theme.player_sheet, visible, source)

func direction_name(direction: Vector2i) -> String:
	if direction == Vector2i.RIGHT: return "right"
	if direction == Vector2i.LEFT: return "left"
	if direction == Vector2i.DOWN: return "down"
	return "up"

func draw_named_sprite(name: StringName, position_in_room: Vector2, tint: Color = Color.WHITE, size: Vector2 = Vector2(16, 16)) -> void:
	if visual_theme.sprites.has(name):
		var texture: Texture2D = visual_theme.sprites[name]
		draw_clipped_texture(texture,Rect2(position_in_room + Vector2(0,HUD_HEIGHT),size),Rect2(Vector2.ZERO,texture.get_size()),tint)

func draw_room_objects() -> void:
	for decoration in room.decorations:
		if not decoration_visible(decoration):
			continue
		if not decoration.hide_after_pickup.is_empty() and state.has_collected(room.id, decoration.hide_after_pickup) and simulation_tick % 2 != 0:
			continue
		var sprite_name: StringName = decoration.sprite
		if decoration.frames > 1:
			var pose := floori(float(simulation_tick) / maxi(1, int(decoration.frame_ticks))) % int(decoration.frames)
			sprite_name = StringName(String(sprite_name) + "_" + str(pose))
		draw_named_sprite(sprite_name, Vector2(decoration.position))
	for pickup in room.pickups:
		if not state.has_collected(room.id, pickup.id) and (not pickup.requires_clear or room_clear()):
			var sprite := item_sprite(pickup.item)
			if not visual_theme.sprites.has(sprite): sprite = StringName(String(sprite) + "_" + str((simulation_tick / 8) % 2))
			draw_named_sprite(sprite, Vector2(pickup.position) + Vector2(0, 3) if room.dungeon_level > 0 else Vector2(pickup.position))
	if cave_session != null:
		draw_cave()
	elif dialogue_visible() and entry_walk_remaining == 0:
		var shown: String = room.dialogue.substr(0, dialogue_elapsed / room.dialogue_character_ticks)
		var lines: PackedStringArray = shown.split("\n")
		for i in range(lines.size()):
			draw_hud_text(lines[i], Vector2(32, 104 + i * 8))

## Dungeon HUD: the map shows rooms once held; the compass flashes the triforce room.
func draw_level_map() -> void:
	var level: int = room.dungeon_level
	draw_hud_text("LEVEL-%d" % level, Vector2(16, 8))
	var cells: Array[int] = []
	var left := 15
	var triforce_room := -1
	for definition in rooms.values():
		if definition.dungeon_level != level or definition.map_room_id < 0: continue
		cells.append(definition.map_room_id)
		left = mini(left, definition.map_room_id % 16)
		for pickup in definition.pickups:
			if "slot" in pickup.item and pickup.item.slot == &"triforce": triforce_room = definition.map_room_id
	var origin := Vector2(16, 16)
	if state.has_level_item(&"map", level):
		for id in cells:
			draw_rect(Rect2(origin + Vector2((id % 16 - left) * 8, (id / 16) * 4), Vector2(7, 3)), Color("2038ec"))
	if triforce_room >= 0 and state.has_level_item(&"compass", level) and not state.has_level_item(&"triforce", level) and simulation_tick % 32 < 16:
		draw_rect(Rect2(origin + Vector2((triforce_room % 16 - left) * 8 + 2, (triforce_room / 16) * 4), Vector2(3, 3)), Color("d82800"))
	var here: int = room.map_room_id
	if here < 0 and rooms.has(room.history_id): here = rooms[room.history_id].map_room_id
	if here >= 0:
		draw_rect(Rect2(origin + Vector2((here % 16 - left) * 8 + 2, (here / 16) * 4), Vector2(3, 3)), Color("80d010"))

func draw_cave() -> void:
	var session: RefCounted = cave_session
	if session.flicker_hidden(simulation_tick): return
	if session.person_visible():
		if visual_theme.sprites.has(session.cave.person_sprite):
			draw_named_sprite(session.cave.person_sprite, Vector2(120, 64))
		else:
			draw_rect(Rect2(122, 64 + HUD_HEIGHT, 12, 16), Color("e0a060"))
	if not session.person_visible(): return
	for i in range(3):
		if not session.ware_visible(i): continue
		var item: Resource = session.cave.wares[i].item
		var at := Vector2(session.WARE_X[i], session.WARE_Y)
		var sprite := item_sprite(item)
		if not visual_theme.sprites.has(sprite): sprite = StringName(String(sprite) + "_" + str((simulation_tick / 8) % 2))
		if visual_theme.sprites.has(sprite): draw_named_sprite(sprite, at)
		else: draw_rect(Rect2(at + Vector2(4, HUD_HEIGHT + 2), Vector2(8, 12)), item.fallback_color if "fallback_color" in item else Color("f0d070"))
	if session.show_prices:
		if session.price_mark != "":
			draw_named_sprite(&"rupee_0", Vector2(48, 107))
		draw_hud_text(session.price_mark, Vector2(64, 176))
		for i in range(3):
			var price: String = session.price_text(i)
			draw_hud_text(price, Vector2(72 + i * 32 + (4 - price.length()) * 8, 176))
	if entry_walk_remaining == 0:
		var lines: PackedStringArray = session.visible_text().split("\n")
		for i in range(lines.size()):
			draw_hud_text(lines[i], Vector2(32, 104 + i * 8))

func draw_item_objects() -> void:
	for object in item_objects:
		if object.kind == "fire":
			var sprite := StringName("fire_" + str((simulation_tick / 4) % 2))
			if visual_theme.sprites.has(sprite): draw_named_sprite(sprite, Vector2(object.position))
			else: draw_circle(Vector2(object.center()) + Vector2(0, HUD_HEIGHT), 6, Color("f07020"))
		elif object.showing_bomb():
			if visual_theme.sprites.has(&"bombs"): draw_named_sprite(&"bombs", Vector2(object.position))
			else: draw_circle(Vector2(object.center()) + Vector2(0, HUD_HEIGHT), 5, Color("3050c0"))
		else:
			# Z_07 DrawOtherBombClouds alternates between two offset sets.
			var offsets := [Vector2i(-7, -13), Vector2i(14, 0), Vector2i(7, 14)] if simulation_tick % 2 == 0 else [Vector2i(7, -13), Vector2i(-13, 0), Vector2i(-7, 14)]
			var sprite := StringName("bomb_cloud_" + str(object.stage - 2))
			for offset in [Vector2i.ZERO] + offsets:
				if visual_theme.sprites.has(sprite): draw_named_sprite(sprite, Vector2(object.position + offset))
				else: draw_circle(Vector2(object.center() + offset) + Vector2(0, HUD_HEIGHT), 6, Color("e8e8e8"))

func draw_hud_text(text: String, at: Vector2, color: Color = Color.WHITE) -> void:
	for i in range(text.length()):
		var code := text.unicode_at(i)
		var tile := -1
		if code >= 48 and code <= 57: tile = code - 48
		elif code >= 65 and code <= 90: tile = code - 65 + 10
		elif code == 45: tile = 0x62
		elif code == 39: tile = 0x2A
		elif code == 46: tile = 0x29
		elif code == 33: tile = 0x2C
		elif code == 63: tile = 0x2E
		elif code == 43: tile = 0x64
		elif code == 44: tile = 0x28
		if tile >= 0:
			draw_texture_rect_region(visual_theme.hud_tiles, Rect2(at + Vector2(i * 8, 0), Vector2(8, 8)), Rect2((tile % 16) * 8, (tile / 16) * 8, 8, 8), color)

func draw_original_hud() -> void:
	# Sword ownership, health, and currency are live; the map is a scaffold.
	draw_rect(Rect2(0, 0, 256, 64), Color.BLACK)
	if room.dungeon_level > 0:
		draw_level_map()
	else:
		draw_rect(Rect2(16, 16, 64, 32), Color("666666"))
		var room_number: int = room.map_room_id if room.map_room_id >= 0 else 0
		draw_rect(Rect2(16 + room_number % 16 * 4, 16 + (room_number / 16) * 4, 4, 4), Color("80d010"))
	draw_hud_text("X%d" % state.rupees, Vector2(96, 16))
	draw_hud_text("X%d" % state.item_value(&"keys"), Vector2(96, 32))
	draw_hud_text("X%d" % state.item_value(&"bombs"), Vector2(96, 40))
	draw_rect(Rect2(124, 24, 20, 24), Color("4070c0"), false, 2)
	draw_rect(Rect2(148, 24, 20, 24), Color("4070c0"), false, 2)
	draw_hud_text("B", Vector2(128, 16))
	draw_hud_text("A", Vector2(152, 16))
	draw_hud_text("-LIFE-", Vector2(176, 16), Color("e85050"))
	for i in range(state.max_health / 2):
		var frame: int = state.heart_frame(i)
		var at := Vector2(176 + (i % 8) * 8, 32 + (i / 8) * 8)
		if visual_theme.hud_hearts:
			var texture: Texture2D = visual_theme.hud_hearts
			var width := texture.get_width() / 3.0
			draw_texture_rect_region(texture, Rect2(at, Vector2(8, 8)), Rect2(frame * width, 0, width, texture.get_height()))
		else:
			# A custom theme can omit the ROM-derived heart sheet.
			var mask := ["01101100", "11111110", "11111110", "11111110", "11111110", "01111100", "00111000", "00010000"]
			for y in range(8):
				for x in range(8):
					if mask[y][x] == "1":
						var filled := frame == 0 or (frame == 1 and x < 4)
						draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), Color("e85050") if filled else Color("d0c8bd"))

	if state.equipped_weapon != null and visual_theme.sprites.has(state.equipped_weapon.id):
		draw_texture_rect(visual_theme.sprites[state.equipped_weapon.id], Rect2(150, 28, 16, 16), false)
	var selected: Resource = item_for_slot(state.selected_item) if not state.selected_item.is_empty() and state.item_value(state.selected_item) > 0 else null
	if selected != null and visual_theme.sprites.has(item_sprite(selected)):
		draw_texture_rect(visual_theme.sprites[item_sprite(selected)], Rect2(126, 28, 16, 16), false)

func draw_combat() -> void:
	for actor in combat.enemies:
		var at: Vector2 = Vector2(actor.position()) + Vector2(0, HUD_HEIGHT)
		if actor.waiting_spawn: continue
		if actor.spawn_remaining > 0:
			var phase: int = 0 if actor.spawn_remaining > 12 else 1 if actor.spawn_remaining > 6 else 2
			var sprite := StringName("spawn_cloud_" + str(phase))
			if actor.definition.behavior != "native" and visual_theme.sprites.has(sprite):
				draw_named_sprite(sprite, Vector2(actor.position()))
			else:
				draw_circle(at + Vector2(8, 8), 3 + actor.spawn_remaining % 4, Color("f0e6c8"))
		elif actor.health <= 0:
			if actor.death_remaining > 0:
				var phase: int = 1 if actor.death_remaining > 12 or actor.death_remaining <= 6 else 0
				var sprite := StringName("death_spark_" + str(phase))
				if actor.definition.behavior != "native" and visual_theme.sprites.has(sprite):
					if actor.death_remaining < 19: draw_named_sprite(sprite, Vector2(actor.position()))
				else:
					draw_circle(at + Vector2(8, 8), actor.death_remaining / 2.0, Color("fff4c8"))
		elif actor.body_visible() and (actor.invulnerability == 0 or simulation_tick % 4 < 2):
			var sprite: StringName = actor.sprite_name()
			# Dungeon monsters use their level's pattern blocks and palettes.
			var leveled := StringName("l%d_%s" % [room.dungeon_level, sprite])
			if room.dungeon_level > 0 and visual_theme.sprites.has(leveled): sprite = leveled
			if visual_theme.sprites.has(sprite):
				draw_named_sprite(sprite, Vector2(actor.position()), actor.definition.tint, Vector2(actor.definition.size))
			else:
				draw_rect(Rect2(at + Vector2(1, 2), Vector2(14, 12)), actor.definition.fallback_color)
				draw_line(at + Vector2(8, 8), at + Vector2(8, 8) + Vector2(actor.facing) * 8, Color.BLACK, 2)
	for rock in combat.rocks:
		if rock.kind == "boomerang":
			# Spinning: the image flips every few frames.
			var spin := (simulation_tick / 3) % 4
			var at: Vector2 = Vector2(rock.position()) + Vector2(0, HUD_HEIGHT)
			if visual_theme.sprites.has(&"boomerang"):
				var texture: Texture2D = visual_theme.sprites[&"boomerang"]
				var size := Vector2(-16 if spin & 1 else 16, -16 if spin & 2 else 16)
				draw_texture_rect(texture, Rect2(at + Vector2(16 if spin & 1 else 0, 16 if spin & 2 else 0), size), false)
			else:
				draw_circle(at + Vector2(8, 8), 4, Color("c87830"))
			continue
		var sprite: StringName = &"rock"
		if rock.kind == "arrow": sprite = StringName("monster_arrow_" + direction_name(rock.direction))
		elif rock.kind in ["sword", "magic"]: sprite = StringName("beam_" + direction_name(rock.direction) + "_" + str(simulation_tick % 4))
		elif rock.kind == "fireball": sprite = StringName("fireball_" + str(simulation_tick % 2))
		if visual_theme.sprites.has(sprite):
			draw_named_sprite(sprite, Vector2(rock.position()) + (Vector2(0,3) if rock.kind in ["sword", "magic"] and rock.direction.x != 0 else Vector2.ZERO))
		elif rock.kind == "rock":
			draw_circle(Vector2(rock.position()) + Vector2(8, HUD_HEIGHT + 8), 3, Color("ba9670"))
		else:
			var center: Vector2 = Vector2(rock.position()) + Vector2(8,HUD_HEIGHT+8)
			draw_line(center-Vector2(rock.direction)*6,center+Vector2(rock.direction)*6,Color("eeeecc"),3)

	for reward in combat.rewards:
		if reward.age < 32 and (reward.age / 2) % 2 != 0:
			continue
		var pose := (simulation_tick / 8) % 2
		var sprite := StringName(String(reward.definition.sprite) + "_" + str(pose))
		if visual_theme.sprites.has(sprite):
			draw_named_sprite(sprite, Vector2(reward.position))
		else:
			draw_circle(Vector2(reward.position) + Vector2(8, HUD_HEIGHT + 8), 4, reward.definition.fallback_color)

	if combat.beam != null:
		var beam = combat.beam
		var palette := simulation_tick % 4
		if beam.flying():
			var name := StringName("beam_" + direction_name(beam.direction) + "_" + str(palette))
			var at: Vector2 = Vector2(beam.position) + (Vector2(0, 3) if beam.direction.x != 0 else Vector2.ZERO)
			if visual_theme.sprites.has(name):
				draw_named_sprite(name, at)
			else:
				draw_line(at + Vector2(8, HUD_HEIGHT + 8), at + Vector2(8, HUD_HEIGHT + 8) + Vector2(beam.direction) * 10, Color("b5eaff"), 3)
		else:
			var distance: int = 2 + 22 - beam.burst_remaining
			var offsets := [Vector2i(-distance, -distance), Vector2i(-distance, distance), Vector2i(distance, distance), Vector2i(distance, -distance)]
			for corner in range(4):
				var name := StringName("beam_burst_" + str(corner) + "_" + str(palette))
				var at: Vector2 = Vector2(beam.position + offsets[corner])
				if visual_theme.sprites.has(name):
					draw_named_sprite(name, at)
				else:
					draw_circle(at + Vector2(8, HUD_HEIGHT + 8), 2, Color("b5eaff"))

func draw_terrain(definition: Resource, offset: Vector2) -> void:
	for y in range(11):
		for x in range(16):
			var wall: bool = definition.is_solid(Vector2i(x, y))
			var rect := Rect2(Vector2(x * 16, HUD_HEIGHT + y * 16) + offset, Vector2(16, 16))
			if not rect.intersects(Rect2(0, 64, 256, 176)): continue
			if definition.tile_atlas and not definition.tile_indices.is_empty():
				var index: int = definition.tile_indices[y * 16 + x]
				var cell_size: Vector2i = definition.atlas_cell_size
				var columns: int = definition.tile_atlas.get_width() / cell_size.x
				var source := Rect2(Vector2((index % columns) * cell_size.x, (index / columns) * cell_size.y), Vector2(cell_size))
				draw_clipped_texture(definition.tile_atlas, rect, source)
				continue
			var texture: Texture2D = visual_theme.wall_texture if wall else visual_theme.floor_texture
			if texture:
				draw_clipped_texture(texture, rect, Rect2(Vector2.ZERO, texture.get_size()))
			else:
				draw_rect(rect.intersection(Rect2(0, 64, 256, 176)), visual_theme.wall_color if wall else visual_theme.floor_color)
				if wall:
					draw_rect(rect.grow(-3).intersection(Rect2(0, 64, 256, 176)), Color("394f36"), false, 1)
	var replaced: Dictionary = overrides if definition == room else compute_overrides(definition)
	for cell in replaced:
		draw_square(definition, replaced[cell][0], Vector2(cell * 16) + offset, replaced[cell][2])

## A replacement square: atlas index, or a placeholder color for unthemed rooms.
func draw_square(definition: Resource, index: int, at: Vector2, kind: String) -> void:
	var rect := Rect2(at + Vector2(0, HUD_HEIGHT), Vector2(16, 16))
	if definition.tile_atlas and index >= 0:
		var cell_size: Vector2i = definition.atlas_cell_size
		var columns: int = definition.tile_atlas.get_width() / cell_size.x
		draw_clipped_texture(definition.tile_atlas, rect, Rect2(Vector2((index % columns) * cell_size.x, (index / columns) * cell_size.y), Vector2(cell_size)))
	else:
		var colors := {"floor": visual_theme.floor_color, "object": visual_theme.wall_color, "entrance": Color.BLACK, "door": visual_theme.floor_color}
		draw_rect(rect.intersection(Rect2(0, 64, 256, 176)), colors[kind])

func draw_pushed_object() -> void:
	if room.secret == null or not secrets.moving(): return
	# Z_04 UpdateRockOrGravestone draws the moving object one pixel high.
	draw_square(room, room.secret.object_tile, Vector2(secrets.object_position()) - Vector2(0, 1), "object")

func draw_clipped_texture(texture: Texture2D, destination: Rect2, source: Rect2, tint: Color = Color.WHITE) -> void:
	var visible := destination.intersection(Rect2(0, 64, 256, 176))
	if not visible.has_area(): return
	var ratio := source.size / destination.size
	var cropped := Rect2(source.position + (visible.position - destination.position) * ratio, visible.size * ratio)
	draw_texture_rect_region(texture, visible, cropped, tint)

func draw_scrolling_rooms() -> void:
	var offset := Vector2(transition.direction * transition.distance)
	var incoming := Vector2(transition.direction * (transition.length() - transition.distance))
	draw_terrain(transition.source, -offset)
	draw_terrain(transition.target, incoming)
	var at: Vector2 = Vector2(transition.player_position()) + Vector2(0, HUD_HEIGHT + 2)
	if visual_theme.player_sheet:
		var direction := 0
		if transition.direction == Vector2i.LEFT: direction = 1
		elif transition.direction == Vector2i.DOWN: direction = 2
		elif transition.direction == Vector2i.UP: direction = 3
		var frame: int = direction * 2 + (transition.ticks / 6) % 2
		var width: float = visual_theme.player_sheet.get_width() / 8.0
		draw_clipped_texture(visual_theme.player_sheet, Rect2(at, Vector2(16, 16)), Rect2(frame * width, 0, width, visual_theme.player_sheet.get_height()))
	elif visual_theme.player_texture:
		draw_clipped_texture(visual_theme.player_texture, Rect2(at, Vector2(16, 16)), Rect2(Vector2.ZERO, visual_theme.player_texture.get_size()))
	else:
		draw_rect(Rect2(at + Vector2(3, 2), Vector2(10, 13)).intersection(Rect2(0, 64, 256, 176)), visual_theme.player_color)

func register_item(item: Resource) -> void:
	assert(item != null and not item.id.is_empty(), "Items need stable IDs")
	assert(not item_catalog.has(item.id) or item_catalog[item.id] == item, "Duplicate item ID")
	item_catalog[item.id] = item

func show_status(message: String) -> void:
	status_message = message
	status_ticks = 180
	queue_redraw()

func snapshot() -> Dictionary:
	var inventory: Array = state.inventory.keys().map(func(id: StringName) -> String: return String(id))
	inventory.sort()
	return {"version": Saves.VERSION, "world_id": world_id, "room_id": String(room.id),
		"position": [player.subposition.x, player.subposition.y],
		"facing": [player.facing.x, player.facing.y], "max_health": state.max_health,
		"health": state.health, "rupees": state.rupees, "kill_cycle": state.kill_cycle, "spawn_cycle": state.spawn_cycle,
		"inventory": inventory, "equipped": String(state.equipped_weapon.id) if state.equipped_weapon != null else "",
		"collected": enabled_keys(state.collected), "defeated": enabled_keys(state.defeated), "flags": enabled_keys(state.flags),
		"room_history": state.room_history.duplicate(), "history_cursor": state.history_cursor,
		"room_records": combat.persisted_records(state), "slots": saved_slots(),
		"max_bombs": state.max_bombs, "selected_item": String(state.selected_item) if state.item_value(state.selected_item) > 0 else ""}

func saved_slots() -> Dictionary:
	var result := {}
	for slot in state.slots:
		if state.slots[slot] > 0: result[String(slot)] = state.slots[slot]
	return result

func enabled_keys(values: Dictionary) -> Array:
	var keys: Array = []
	for key in values:
		if values[key]: keys.append(String(key))
	keys.sort()
	return keys

func save_game() -> bool:
	if transition != null or entry_walk_remaining > 0 or lift_remaining > 0 or rise_remaining > 0 or state.health <= 0 or not state.rupees_settled():
		show_status("WAIT UNTIL LINK IS READY TO SAVE")
		return false
	var result: Dictionary = save_store.write_snapshot(snapshot(), world_id)
	show_status("GAME SAVED" if result.ok else "SAVE FAILED: " + result.error)
	return result.ok

func saved_position_walkable(definition: Resource, at: Vector2i, saved_state: RefCounted) -> bool:
	if not definition.movement_bounds.has_point(at): return false
	for pixel in [at + Vector2i(0, 11), at + Vector2i(8, 11)]:
		if definition.is_pixel_solid(pixel): return false
		for decoration in definition.decorations:
			if not decoration.hide_after_pickup.is_empty() and saved_state.has_collected(definition.id, decoration.hide_after_pickup): continue
			if decoration.blocking_area.has_point(pixel): return false
	return true

func load_game() -> bool:
	var result: Dictionary = save_store.read_snapshot(world_id)
	if not result.ok:
		show_status("LOAD FAILED: " + result.error)
		return false
	var data: Dictionary = result.data
	var id := StringName(legacy_ids.get(data.room_id, data.room_id))
	if not rooms.has(id):
		show_status("LOAD FAILED: ROOM IS UNAVAILABLE")
		return false
	var restored = preload("res://scripts/game_state.gd").new()
	for item_id in data.inventory:
		var item := StringName(item_id)
		if not item_catalog.has(item):
			show_status("LOAD FAILED: ITEM IS UNAVAILABLE")
			return false
		restored.inventory[item] = item_catalog[item]
	if not data.equipped.is_empty(): restored.equipped_weapon = item_catalog[StringName(data.equipped)]
	restored.max_health = int(data.max_health)
	restored.health = int(data.health)
	restored.rupees = int(data.rupees)
	restored.kill_cycle = int(data.kill_cycle)
	restored.spawn_cycle = int(data.spawn_cycle)
	for key in data.collected: restored.collected[legacy_ids.get(key, key)] = true
	if data.has("slots"):
		for slot in data.slots: restored.slots[StringName(slot)] = int(data.slots[slot])
		restored.max_bombs = int(data.max_bombs)
		restored.selected_item = StringName(data.selected_item)
	else:
		# Version 2 saves only held unique items such as swords.
		for item in restored.inventory.values():
			if "slot" in item and item.effect in ["unique", "grade"]: restored.slots[item.slot] = maxi(restored.item_value(item.slot), item.value)
	for key in data.defeated: restored.defeated[key] = true
	for key in data.flags: restored.flags[key] = true
	restored.room_history.assign(data.room_history)
	restored.history_cursor = int(data.history_cursor)
	for key in data.room_records:
		restored.room_records[key] = {"kills": int(data.room_records[key].kills), "cleared": data.room_records[key].cleared}
	var target: Resource = rooms[id]
	var position := Vector2i(int(data.position[0]), int(data.position[1]))
	var at := Vector2i(floori(position.x / 256.0), floori(position.y / 256.0))
	var relocated := false
	if not saved_position_walkable(target, at, restored):
		at = target.spawn
		position = at * 256
		relocated = true
		if not saved_position_walkable(target, at, restored):
			show_status("LOAD FAILED: ROOM HAS NO SAFE SPAWN")
			return false
	# Commit only after complete schema, content, and position validation.
	state = restored
	lift_remaining = 0
	lifted_item = null
	pickup_ticks.clear()
	held.clear()
	attack_requested = false
	enter_room(target, at, Vector2i(int(data.facing[0]), int(data.facing[1])), 0, true)
	player.subposition = position
	combat.player_invulnerability = 48
	show_status("BACKUP SAVE LOADED" if result.backup else "LOADED AT ROOM ENTRANCE" if relocated else "GAME LOADED")
	return true

## Secret systems call this only after their world change has succeeded.
func reveal_secret(flag: String) -> bool:
	if flag.is_empty() or state.flags.get(flag, false): return false
	state.flags[flag] = true
	audio.play(&"secret")
	return true
