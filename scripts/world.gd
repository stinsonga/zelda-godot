extends Node2D

const Room = preload("res://scripts/room_definition.gd")
const Player = preload("res://scripts/player.gd")
const Saves = preload("res://scripts/save_store.gd")
const Submenu = preload("res://scripts/submenu.gd")
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
var start_requested := false
var submenu = preload("res://scripts/submenu.gd").new()
## Original submenu layout from the world; null draws placeholders.
var submenu_layout: Resource
var cave_session: RefCounted
var secrets = preload("res://scripts/secret_runtime.gd").new()
var item_objects: Array[RefCounted] = []
var candle_used := false
var item_use_remaining := 0
var portal_armed := true
var rise_remaining := 0
var rise_square := Rect2i()
var legacy_ids: Dictionary[String, String] = {}
var world_definition_whirlwinds: Array = []
var overrides: Dictionary = {}
var level_exit_remaining := 0
var filling_hearts := false
var recorder_ticks := 0
var recorder_used_here := false
var whirlwind_pending := false
var teleport_index := 0
var held_direction := Vector2i.ZERO
## A Like Like or Wallmaster holding Link.
var captor: RefCounted
const DIRECTION_NAMES := {Vector2i.UP: "up", Vector2i.DOWN: "down", Vector2i.LEFT: "left", Vector2i.RIGHT: "right"}
var raft = preload("res://scripts/raft.gd").new()
var rod = preload("res://scripts/rod_action.gd").new()
var ladder = preload("res://scripts/ladder.gd").new()
var lighting = preload("res://scripts/room_lighting.gd").new()
var simulation_tick := 0
var entry_walk_remaining := 0
var entry_walk_subpixels := 0
var entry_direction := Vector2i.UP
var dialogue_elapsed := 0
var lift_remaining := 0
const TRIFORCE = preload("res://content/items/triforce.tres")
var lifted_item: Resource
var pickup_ticks: Dictionary[String, int] = {}
## Last positions of carried room items, by pickup ID, for the current room.
var carried_positions: Dictionary = {}
## Key doors still opening in this room, by direction: frames left.
var door_openings: Dictionary = {}
## Statue squares already woken this visit, by cell: they show floor.
var woken_statues: Dictionary = {}
## Z_01 MazeStep: progress through the current maze room's sequence.
var maze_step := 0
const DOOR_OPEN_TICKS := 9
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
		world_definition_whirlwinds = selected_world.whirlwinds
		world_id = String(selected_world.id)
		submenu_layout = selected_world.submenu
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
	# The submenu shows any owned item, wherever it came from; fill the catalog
	# from the native item definitions without overriding the world's own.
	for file in ResourceLoader.list_directory("res://content/items/"):
		var path := "res://content/items/" + file.trim_suffix(".remap")
		if not path.ends_with(".tres"): continue
		var item: Resource = load(path)
		if item is ItemDefinition and not item_catalog.has(item.id): item_catalog[item.id] = item
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
			elif event.pressed:
				# Start: open or close the submenu.
				start_requested = true
		KEY_Z, KEY_SPACE:
			if event.pressed:
				attack_requested = true
		KEY_X, KEY_SHIFT:
			if event.pressed:
				item_requested = true
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
		start_requested = false

func _physics_process(_delta: float) -> void:
	status_ticks = maxi(0, status_ticks - 1)
	var direction: Vector2i = Vector2i.ZERO if held.is_empty() else held.back()
	simulate_tick(direction, attack_requested, item_requested, start_requested)
	attack_requested = false
	item_requested = false
	start_requested = false
	queue_redraw()

func enter_room(target: Resource, at: Vector2i, facing: Vector2i, entry_walk: int = 0, restoring: bool = false, rise: int = 0) -> void:
	var previous: Resource=room
	var previous_light: int=lighting_stage() if room!=null else 0
	if not restoring: combat.commit_room(state)
	transition = null
	room = target
	ladder.reset()
	raft.reset()
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
	rod.phase = -1
	item_objects.clear()
	recorder_used_here = false
	whirlwind_pending = false
	captor = null
	carried_positions.clear()
	door_openings.clear()
	woken_statues.clear()
	candle_used = false
	item_use_remaining = 0
	rise_remaining = rise * 4
	rise_square = Rect2i(at.x, at.y + 3, 16, 16)
	portal_armed = true
	state.clock_active = false
	state.current_level = room.dungeon_level
	# The room flags' visit bit drives the submenu's sheet map.
	if room.dungeon_level > 0 and room.map_room_id >= 0: state.flags["visited/" + String(room.id)] = true
	secrets.enter(room, state)
	overrides = compute_overrides(room)
	cave_session = null
	if room.cave != null:
		cave_session = preload("res://scripts/cave_session.gd").new()
		cave_session.start(room.cave, room.id, state, combat.source_random)
	combat.enter_room(room, state, restoring, at, facing)
	for spawn in room.reward_spawns: combat.spawn_reward(self, spawn.definition, spawn.position)
	lighting.enter(room,previous!=null and previous.dungeon_level==room.dungeon_level,previous_light,restoring,ganon_intro())
	if raft.can_arrive(room, player.pixel_position(), state): raft.try_start(self)
	state.visit_room(room)
	audio.set_music(room.music)

## Start opens the submenu only while Link is free to act.
func can_open_submenu() -> bool:
	return state.health > 0 and transition == null and entry_walk_remaining == 0 and lift_remaining == 0 and rise_remaining == 0 \
		and level_exit_remaining == 0 and not filling_hearts and recorder_ticks == 0 and captor == null and not combat.ending \
		and not combat.holds_player() and (cave_session == null or not cave_session.blocks_player())

func dialogue_visible() -> bool:
	if cave_session != null:
		return cave_session.visible_text() != "" or cave_session.phase in ["prices", "text"]
	return not room.dialogue.is_empty() and (room.dialogue_until_pickup.is_empty() or not state.has_collected(room.id, room.dialogue_until_pickup))

func simulate_tick(direction: Vector2i, attack_pressed: bool = false, item_pressed: bool = false, start_pressed: bool = false) -> void:
	simulation_tick += 1
	combat.advance_frame()
	if state.tick_rupees(simulation_tick):
		audio.play(&"heart")
	state.sword_block_ticks = maxi(0, state.sword_block_ticks - 1)
	if state.health <= 0:
		return
	if lighting.fading():
		lighting.tick()
		# Hardware object timers continue counting while the play loop is held.
		for object in item_objects:object.timer=maxi(0,object.timer-1)
		return
	if transition != null:
		if transition.tick():
			enter_room(transition.target, transition.destination, transition.direction)
		return
	# Z_05 UpdateMenu: while the submenu is up, only it (and the meters) update.
	if submenu.is_open():
		submenu.tick(state, start_pressed, direction)
		if submenu.moved: audio.play(&"menu_select")
		return
	if start_pressed and can_open_submenu():
		submenu.open(room.dungeon_level > 0, state)
		return
	held_direction = direction
	if filling_hearts:
		# Z_05 World_FillHearts: six units a frame, game paused, heart sound.
		state.health_units = mini(state.max_health * state.HEALTH_UNITS, state.health_units + 6)
		if simulation_tick % 8 == 0: audio.play(&"heart")
		filling_hearts = state.health_units < state.max_health * state.HEALTH_UNITS
		return
	if level_exit_remaining > 0:
		level_exit_remaining -= 1
		if level_exit_remaining == 0: leave_level()
		return
	if recorder_ticks > 0:
		recorder_ticks -= 1
		if recorder_ticks == 0 and whirlwind_pending:
			whirlwind_pending = false
			take_whirlwind()
		return
	tick_item_objects()
	tick_door_openings()
	tick_captor()
	overrides = compute_overrides(room)
	# Zelda's rescue ends play; the ending scenes belong to the front end.
	if combat.ending: return
	if combat.holds_player():
		combat.tick(self)
		return
	if raft.active:
		raft.tick(self)
		if transition == null: combat.tick(self)
		return
	if entry_walk_remaining == 0 and lift_remaining == 0 and rise_remaining == 0 and raft.try_start(self):
		combat.tick(self)
		return
	# Link updates before objects: a lift started by the resident counts from
	# the next tick, and the resident keeps updating during a lift.
	var lifting := lift_remaining > 0
	var cave_halts := false
	if cave_session != null and entry_walk_remaining == 0:
		var was_feeding:bool=cave_session.phase=="feeding"
		cave_session.tick(self)
		cave_halts = was_feeding or cave_session.blocks_player()
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
	elif rod.active():
		rod.tick()
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
			player.step(ladder.constrain(player.pixel_position(), direction), can_occupy, can_enter_segment)
			ladder.update(player.pixel_position())
		if secrets.try_push(self, direction):
			overrides = compute_overrides(room)
		try_doors(direction)
	if player.pixel_position() == before and direction != Vector2i.ZERO: try_wake_statue(direction)
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
	if lift_remaining == 0: raft.try_start(self)
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
		if pickup.requires_secret and not secrets.revealed:
			continue
		var distance: Vector2i = (player.pixel_position() - pickup_position(pickup)).abs()
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

## Z_01 CheckMazes: true when leaving by `edge` should lead back into this room.
func maze_repeats(edge: String) -> bool:
	if room.maze.is_empty():
		maze_step = 0
		return false
	if edge == room.maze[maze_step]:
		if maze_step == room.maze.size() - 1:
			maze_step = 0
			audio.play(&"secret")
			return false
		maze_step += 1
		return true
	if edge == room.maze_free_exit: return false
	maze_step = 0
	return true

## Z_01 CheckPassiveTileObjects: pressing into a statue square wakes it.
## The touched square is the one ahead of Link's feet; when he straddles two,
## either may wake.
func try_wake_statue(direction: Vector2i) -> void:
	if (room.armos == null or room.armos_cells.is_empty()) and (room.ghost == null or room.grave_cells.is_empty()): return
	var at: Vector2i = player.pixel_position()
	var points: Array[Vector2i] = []
	match direction:
		Vector2i.UP: points = [at + Vector2i(0, 3), at + Vector2i(8, 3)]
		Vector2i.DOWN: points = [at + Vector2i(0, 19), at + Vector2i(8, 19)]
		Vector2i.LEFT: points = [at + Vector2i(-8, 11)]
		_: points = [at + Vector2i(16, 11)]
	for point in points:
		var cell := Vector2(point.x / 16, point.y / 16)
		var definition: Resource = room.armos if cell in room.armos_cells and not woken_statues.has(cell) else room.ghost if cell in room.grave_cells else null
		if definition == null: continue
		if combat.wake_statue(definition, Vector2i(cell) * 16) != null: return

## A woken statue's square turns to floor, or reveals the room's Armos secret.
func settle_woken_statues() -> void:
	for actor in combat.enemies:
		if not actor.just_woke: continue
		actor.just_woke = false
		var cell := Vector2(actor.position().x / 16, (actor.position().y) / 16)
		var index: int = room.armos_cells.find(cell)
		if index < 0: continue
		woken_statues[cell] = room.armos_floor_tiles[index] if index < room.armos_floor_tiles.size() else -1
		if room.secret != null and room.secret.trigger == "armos" and Vector2(room.secret.cell) == cell and not secrets.revealed:
			secrets.reveal(self)
		overrides = compute_overrides(room)

## Ganon's ashes move the room item to where he fell; a carrying monster takes
## it along until it finishes dying, and it stays where it was last carried.
func pickup_position(pickup: Resource) -> Vector2i:
	if pickup.id == &"item" and combat.room_item_position != null: return combat.room_item_position
	if pickup.carrier_slot > 0:
		for actor in combat.enemies:
			if actor.slot != pickup.carrier_slot or actor.waiting_spawn: continue
			if actor.health > 0 or actor.death_remaining > 0: carried_positions[pickup.id] = actor.position() - Vector2i(0, 3)
		return carried_positions.get(pickup.id, pickup.position)
	return pickup.position

## Doors and secrets replace 16-pixel squares and their collision.
func compute_overrides(definition: Resource) -> Dictionary:
	var result: Dictionary = secrets.overrides(definition, state)
	if definition == room:
		for cell in woken_statues:
			if not result.has(Vector2i(cell)): result[Vector2i(cell)] = [woken_statues[cell], PackedByteArray([0, 0, 0, 0]), "floor"]
	for door in definition.doors:
		if not door_passable(definition, door): continue
		var door_cells: PackedInt32Array = door.door_cells()
		var collision: PackedInt32Array = door.door_collision()
		var tiles: PackedInt32Array = door.door_tiles()
		for i in range(door_cells.size()):
			var cell := Vector2i(door_cells[i] % 16, door_cells[i] / 16)
			if result.has(cell): continue
			var bits: int = collision[i]
			# A false wall keeps looking like the wall it replaces.
			result[cell] = [tiles[i], PackedByteArray([bits & 1, bits >> 1 & 1, bits >> 2 & 1, bits >> 3 & 1]), "false_door" if door.kind == "false" else "door"]
	return result

func door_key(definition: Resource, direction: Vector2i) -> String:
	return "door/" + String(definition.id) + "/" + DIRECTION_NAMES[direction]

## Z_05 TouchDoor: false walls let Link through, key and bombable doors stay
## open once opened, and shutters open while the room is clear.
func door_passable(definition: Resource, door: Resource) -> bool:
	match door.kind:
		"open", "false": return true
		"key", "bombable": return state.flags.get(door_key(definition, door.direction), false) and not (definition == room and door_openings.has(door.direction))
		"shutter": return definition != room or shutters_open()
	return false

## Z_05 CheckSecretTrigger: shutters close behind Link and reopen only when the
## room's trigger fires. Trigger 0 never fires; the level 9 gate man opens his
## room's shutters through a flag. Trigger 5 reveals stairs and opens nothing.
func shutters_open() -> bool:
	if state.flags.get("shutters/" + String(room.id), false): return true
	match room.shutter_trigger:
		1, 2, 3, 7: return monsters_gone()
		4: return secrets.revealed
		6: return cave_session == null or not cave_session.person_visible()
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
func key_count_text() -> String:
	return "XA" if state.item_value(&"magic_key") > 0 else "X%d" % state.item_value(&"keys")

## A door still opening (TriggeredDoorCmd) blocks Link but spends nothing more.
func try_doors(direction: Vector2i) -> void:
	var at: Vector2i = player.pixel_position()
	for door in room.doors:
		if door.kind != "key" or direction != door.direction or state.flags.get(door_key(room, door.direction), false) or not door.in_doorway(at): continue
		if state.item_value(&"magic_key") == 0:
			if state.item_value(&"keys") == 0: continue
			state.slots[&"keys"] -= 1
		open_door(door)
		# UpdateDoors: the open command steps now and again after DoorTimer 8.
		door_openings[door.direction] = DOOR_OPEN_TICKS
		overrides = compute_overrides(room)

## Counts down doors still opening; each becomes passable when its count ends.
func tick_door_openings() -> void:
	var opened := false
	for direction in door_openings.keys():
		door_openings[direction] -= 1
		if door_openings[direction] <= 0:
			door_openings.erase(direction)
			opened = true
	if opened: overrides = compute_overrides(room)

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

## The whirlwind sets Link down in the chosen level's entrance room (Z_01
## WhirlwindPrevRoomIdList is the room before it; TeleportYs gives the height).
## Provisional: the flight itself is not animated.
func take_whirlwind() -> void:
	var index := whirlwind_destination()
	if index < 0 or world_definition_whirlwinds.is_empty(): return
	var target: Dictionary = world_definition_whirlwinds[index]
	if rooms.has(StringName(target.room)):
		enter_room(rooms[StringName(target.room)], Vector2i(0x80, int(target.y) - 64), Vector2i.RIGHT)

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
		if object.kind=="bait":continue
		if object.kind=="fire" and object.stage==2:lighting.candle(room)
		if object.kind in ["arrow", "boomerang"]:
			tick_thrown(object)
			continue
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
	for actor in combat.enemies:
		if actor.definition.behavior == "dodongo" and actor.alive(): actor.family.dodongo_bombs(actor, item_objects)
	for object in item_objects:
		if not object.detonating(): continue
		for door in room.doors:
			if door.kind != "bombable" or door_passable(room, door): continue
			var delta: Vector2i = (door.bomb_hotspot() - object.position).abs()
			if delta.x < 0x18 and delta.y < 0x18: open_door(door)
	item_objects = item_objects.filter(func(object: RefCounted) -> bool: return object.active)
	secrets.update(self)

## Arrows end at the room bounds or the first monster; boomerangs stun (or kill
## fragile monsters), carry drops back, and return to Link.
func tick_thrown(object: RefCounted) -> void:
	var edge: Rect2i = combat.bounds.grow(16)
	if object.kind == "arrow":
		if object.stage == 1 and not edge.has_point(object.position):
			object.spark()
			return
	elif not object.returning and (not edge.has_point(object.position) or (object.position.x % 8 == 0 and object.position.y % 8 == 0 and is_blocked(object.position + Vector2i(8, 8)))):
		object.returning = true
	if object.kind == "boomerang" and object.returning:
		var delta: Vector2i = player.pixel_position() - object.position
		if absi(delta.x) < 8 and absi(delta.y) < 8:
			object.active = false
			return
		object.position += Vector2i(signi(delta.x), signi(delta.y)) * 3
	for reward in combat.rewards:
		if object.kind in ["boomerang", "arrow"] and reward.available() and reward.touches(object.position):
			reward.take(state)
			audio.play(reward.pickup_sound())
	for actor in combat.enemies:
		# Z_04 Ganon_CheckCollisions tests only an arrow in flight against brown Ganon.
		if object.kind == "arrow" and actor.definition.behavior == "ganon":
			if actor.health > 0 and object.hits(actor.hit_position()) and combat.ganon_arrow_hit(actor, state.item_value(&"arrows") >= 2):
				audio.play(&"enemy_hit")
				object.spark()
				return
			continue
		if not actor.targetable() or not object.hits(actor.hit_position()): continue
		if object.kind == "arrow":
			var damage: int = actor.health if actor.definition.arrow_kills else object.damage()
			if actor.definition.behavior == "gohma" and not actor.family.gohma_eye_hit(actor, object.center(), object.direction):
				audio.play(&"parry")
				object.spark()
				return
			if actor.receive_hit(damage, object.direction, "arrow"):
				audio.play(&"enemy_hit")
				if actor.health == 0:
					audio.play(&"enemy_die")
					combat.record_permanent_kill(self, actor)
			elif actor.parried_hit:
				audio.play(&"parry")
			object.spark()
			return
		if object.returning: continue
		object.returning = true
		if "boomerang" in actor.definition.invincible_to:
			audio.play(&"parry")
		elif actor.definition.fragile:
			if actor.receive_hit(actor.health, object.direction, "boomerang"):
				audio.play(&"enemy_die")
				combat.record_permanent_kill(self, actor)
		elif actor.definition.stunnable:
			actor.stun_ticks = 0xA0
		return

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
			if burning_objects() >= 2:
				item_objects.erase(item_objects.filter(func(object: RefCounted) -> bool: return object.kind == "fire")[0])
			state.slots[&"bombs"] -= 1
			var bomb_item: Resource = item_for_slot(&"bombs")
			var fuse: Array[int] = []
			fuse.assign(bomb_item.use_fuse_ticks if bomb_item != null else ItemObject.BOMB_TIMES)
			item_objects.append(ItemObject.bomb(ahead, player.facing, fuse))
			audio.play(&"bomb_drop")
			ensure_selected_item()
		&"candle":
			# Z_01 WieldCandle: two slots; the blue candle burns once per room.
			var candle: Resource = item_for_slot(&"candle")
			var once: bool = candle.use_once_per_room if candle != null else state.item_value(&"candle") == 1
			if burning_objects() >= 2 or (once and candle_used):
				return false
			candle_used = true
			item_objects.append(ItemObject.fire(ahead, player.facing))
			audio.play(&"flame")
		&"potion":
			# Z_05 WieldPotion: pause the game while World_FillHearts refills.
			state.slots[&"potion"] -= 1
			filling_hearts = true
			ensure_selected_item()
			return true
		&"arrows":
			# Z_05 WieldArrow: needs the bow and a rupee; one arrow at a time.
			if rod.active() or state.item_value(&"bow") == 0 or state.rupees == 0 or item_objects.any(func(o: RefCounted) -> bool: return o.kind == "arrow"):
				return false
			state.rupees_to_subtract += 1
			var arrow: Resource = item_for_slot(&"arrows")
			if arrow != null: item_objects.append(ItemObject.arrow(ahead, player.facing, arrow.use_damage, arrow.use_speed))
			else: item_objects.append(ItemObject.arrow(ahead, player.facing, 4 if state.item_value(&"arrows") >= 2 else 2))
			audio.play(&"arrow")
		&"boomerang":
			# Z_05 WieldBoomerang: thrown along the held direction, diagonals included.
			if item_objects.any(func(o: RefCounted) -> bool: return o.active and o.kind in ["boomerang","bait"]):
				return false
			var aim: Vector2i = held_direction if held_direction != Vector2i.ZERO else player.facing
			var thrown: Resource = item_for_slot(&"boomerang")
			if thrown != null: item_objects.append(ItemObject.boomerang(ahead, aim, thrown.use_range, thrown.use_speed))
			else: item_objects.append(ItemObject.boomerang(ahead, aim, 0xFF if state.item_value(&"boomerang") >= 2 else 0x31))
			audio.play(&"arrow")
		&"bait":
			if item_objects.any(func(o:RefCounted)->bool:return o.active and o.kind in ["boomerang","bait"]):return false
			var food:Resource=item_for_slot(&"bait")
			item_objects.append(ItemObject.bait(ahead,food.use_duration_ticks if food!=null else 765))
			if cave_session!=null:cave_session.try_feed(self)
		&"rod":
			if rod.active() or item_objects.any(func(o: RefCounted) -> bool: return o.active and o.kind == "arrow"): return false
			return rod.start(item_for_slot(&"rod"), player.facing)
		&"recorder":
			play_recorder()
		&"letter":
			return cave_session != null and cave_session.show_letter(self)
		_:
			return false
	item_use_remaining = ITEM_USE_TICKS
	return true

func burning_objects() -> int:
	return item_objects.filter(func(o: RefCounted) -> bool: return o.kind in ["bomb", "fire"]).size()

## Z_07 WieldFlute: the tune halts Link for $98 frames. Outdoors it drains
## level 7's pond or calls the whirlwind; in a dungeon it marks the room.
func play_recorder() -> void:
	audio.play(&"recorder")
	recorder_ticks = 0x98
	if room.dungeon_level > 0:
		recorder_used_here = true
	elif room.secret != null and room.secret.trigger == "recorder" and not secrets.revealed:
		secrets.recorder_pending = true
	elif state.flags.keys().any(func(key: String) -> bool: return key.begins_with("triforce/")):
		whirlwind_pending = true

## Z_01 SummonWhirlwind and AdvanceTeleportingLevelIndex: step through the
## levels whose triforce Link holds, forward when facing right or up.
func whirlwind_destination() -> int:
	var step := 1 if player.facing.x > 0 or player.facing.y < 0 else -1
	for i in range(8):
		teleport_index = posmod(teleport_index + step, 8)
		if state.has_level_item(&"triforce", teleport_index + 1): return teleport_index
	return -1

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
	if secrets.drained(room, state) and Rect2i(Vector2i.ZERO, ROOM_SIZE).has_point(pixel):
		return room.secret.drained_collision[(pixel.y / 8) * 32 + pixel.x / 8] != 0
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
	# Underworld residents block only while present (Z_07 checks ObjType+1).
	if room.cave != null and direction == Vector2i.UP and at.y < CAVE_PERSON_LINE and (room.dungeon_level == 0 or (cave_session != null and cave_session.person_visible())):
		return false
	ladder.update(at)
	if not ladder.active and room.ladder_allowed and state.item_value(&"ladder") > 0 and entry_walk_remaining == 0:
		var probes := movement_probes(at, direction)
		var water := probes.any(func(pixel: Vector2i) -> bool: return ladder_water_at(pixel) and is_blocked(pixel))
		var safe := probes.all(func(pixel: Vector2i) -> bool: return not is_blocked(pixel) or ladder_water_at(pixel))
		# Original deployment needs one of monster slots 1 through 11 free.
		var occupied: int = combat.enemies.filter(func(a: RefCounted) -> bool: return a.alive()).size() + combat.rocks.size()
		if water and safe and occupied < 11:
			ladder.deploy(at, direction)
	if ladder.active: return ladder.allows(at, direction, ordinary_segment)
	return ordinary_segment(at, direction)

func ladder_water_at(pixel: Vector2i) -> bool:
	if not room.is_ladder_water(pixel): return false
	if overrides.has(Vector2i(pixel.x / 16, pixel.y / 16)): return false
	for decoration in room.decorations:
		if decoration_visible(decoration) and decoration.blocking_area.has_point(pixel): return false
	return true

func movement_probes(at: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	var probe := at + Vector2i(0, 11)
	if direction.x != 0:
		probe.x += 16 if direction.x > 0 else -8
		return [probe]
	probe.y += 8 if direction.y > 0 else -8
	return [probe, probe + Vector2i(8, 0)]

func ordinary_segment(at: Vector2i, direction: Vector2i) -> bool:
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
	if maze_repeats(edge): target = room
	var destination := at
	match edge:
		"left": destination.x = target.movement_bounds.end.x - 1
		"right": destination.x = target.movement_bounds.position.x
		"up": destination.y = target.movement_bounds.end.y - 1
		"down": destination.y = target.movement_bounds.position.y
	if not occupiable_in(target, destination) and not raft.can_arrive(target, destination, state): return
	if not scroll_transitions:
		enter_room(target, destination, direction)
		return
	transition = preload("res://scripts/room_transition.gd").new()
	transition.source = room
	transition.target = target
	transition.source_position = at
	transition.destination = destination
	transition.direction = direction
	if target.dark_room and lighting_stage()<3:lighting.begin(false,target.light_step_ticks)
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
	# The open submenu pushes the status bar and play area down.
	if submenu.offset > 0: draw_set_transform(Vector2(0, submenu.offset))
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
	# UpdateMenuCommon1 hides every sprite while the submenu is up.
	if submenu.is_open():
		draw_set_transform(Vector2.ZERO)
		draw_submenu()
		return
	draw_pushed_object()
	draw_ladder()
	draw_raft()
	draw_room_objects()
	draw_item_objects()
	draw_combat()
	if rise_remaining > 0:
		draw_rising_player()
	elif state.clock_active or combat.player_invulnerability == 0 or simulation_tick % 4 < 2:
		var at: Vector2 = Vector2(player.pixel_position()) + Vector2(0, HUD_HEIGHT)
		if lift_remaining > 0 and visual_theme.sprites.has(&"lift"):
			draw_named_sprite(&"lift", Vector2(player.pixel_position()))
			draw_named_sprite(item_sprite(lifted_item), Vector2(player.pixel_position()) - Vector2(4, 16))
		elif ganon_intro() and visual_theme.sprites.has(&"lift"):
			# Ganon_ScenePhase0/1: Link holds up the Triforce of Courage.
			draw_named_sprite(&"lift", Vector2(player.pixel_position()))
			draw_named_sprite(item_sprite(TRIFORCE), Vector2(player.pixel_position()) - Vector2(4, 16))
		elif (sword.active() or rod.active() or item_use_remaining > 0) and visual_theme.sprites.has(StringName("attack_" + direction_name(player.facing))):
			var facing: Vector2i = sword.direction if sword.active() else player.facing
			draw_named_sprite(clock_sprite(StringName("attack_" + direction_name(facing))), Vector2(player.pixel_position()) + Vector2(0, 2))
		elif visual_theme.player_sheet:
			var direction := 0
			if player.facing == Vector2i.LEFT: direction = 1
			elif player.facing == Vector2i.DOWN: direction = 2
			elif player.facing == Vector2i.UP: direction = 3
			var frame := direction * 2 + walk_pose
			# Z_07 applies a two-pixel overworld drawing offset, independent of collision.
			var sheet: Texture2D = visual_theme.sprites.get(StringName("clock_player_" + str(clock_palette())), visual_theme.player_sheet) if state.clock_active else visual_theme.player_sheet
			draw_texture_rect_region(sheet, Rect2(at + Vector2(0, 2), Vector2(16, 16)), Rect2(frame * sheet.get_width() / 8.0, 0, sheet.get_width() / 8.0, sheet.get_height()))
		elif visual_theme.player_texture:
			draw_texture_rect(visual_theme.player_texture, Rect2(at, Vector2(16, 16)), false)
		else:
			draw_rect(Rect2(at + Vector2(3, 2), Vector2(10, 13)), (Color.from_hsv(clock_palette() / 4.0, 0.5, 1.0) if state.clock_active else visual_theme.player_color))
			draw_rect(Rect2(at + Vector2(4, 5), Vector2(8, 5)), visual_theme.accent_color)
			draw_line(at + Vector2(8, 8), at + Vector2(8, 8) + Vector2(player.facing) * 7, Color("263b32"), 2)

		if rod.visible():
			var sprite := StringName("rod_" + direction_name(rod.direction))
			if visual_theme.sprites.has(sprite): draw_named_sprite(sprite, Vector2(player.pixel_position() + rod.offset()))
			else:
				var center := Vector2(player.pixel_position() + rod.offset()) + Vector2(8, HUD_HEIGHT + 8)
				draw_line(center - Vector2(rod.direction) * 7, center + Vector2(rod.direction) * 7, Color("88b8ff"), 3)
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

func clock_palette() -> int:
	return posmod(-int(simulation_tick / 2), 4)

func clock_sprite(base: StringName) -> StringName:
	var variant := StringName(String(base) + "_clock_" + str(clock_palette()))
	return variant if state.clock_active and visual_theme.sprites.has(variant) else base

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
		if not state.has_collected(room.id, pickup.id) and (not pickup.requires_clear or room_clear()) and (not pickup.requires_secret or secrets.revealed):
			var sprite := item_sprite(pickup.item)
			if not visual_theme.sprites.has(sprite): sprite = StringName(String(sprite) + "_" + str((simulation_tick / 8) % 2))
			var spot: Vector2 = Vector2(pickup_position(pickup)) + (Vector2(0, 3) if room.dungeon_level > 0 else Vector2.ZERO)
			if visual_theme.sprites.has(sprite): draw_named_sprite(sprite, spot)
			else:
				# Unthemed items: a diamond with the item's initial.
				var center: Vector2 = spot + Vector2(8, HUD_HEIGHT + 8)
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -7), center + Vector2(7, 0), center + Vector2(0, 7), center + Vector2(-7, 0)]), visual_theme.accent_color)
				var label: String = String(pickup.item.title if "title" in pickup.item and pickup.item.title != "" else pickup.item.id).left(1).to_upper()
				draw_string(font, center + Vector2(-3, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("2a2a2a"))
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
			draw_hud_text(lines[i], Vector2(32, 104 + (i+session.cave.text_line_offset) * 8))

func draw_raft() -> void:
	if not raft.active: return
	var at := Vector2(player.pixel_position() + raft.route.sprite_offset)
	if visual_theme.sprites.has(&"deployed_raft"):
		draw_named_sprite(&"deployed_raft", at)
	else:
		at.y += HUD_HEIGHT
		for x in range(0, 16, 4):
			draw_rect(Rect2(at + Vector2(x, 0), Vector2(3, 16)).intersection(Rect2(0, HUD_HEIGHT, 256, 176)), Color("ad783c"))

func draw_ladder() -> void:
	if not ladder.active: return
	var at: Vector2 = Vector2(ladder.anchor + Vector2i(0, 3))
	if visual_theme.sprites.has(&"deployed_ladder"):
		draw_named_sprite(&"deployed_ladder", at)
	else:
		at.y += HUD_HEIGHT
		for x in [2, 13]: draw_rect(Rect2(at + Vector2(x, 0), Vector2(2, 16)), Color("b88a48"))
		for y in [2, 7, 12]: draw_rect(Rect2(at + Vector2(2, y), Vector2(13, 2)), Color("e8c078"))

## Z_05 DrawSubmenuItems and UpdateSubmenuSelection, over the backdrop the
## original builds in NT2. Without an import the boxes and labels are placeholders.
func draw_submenu() -> void:
	var top := Vector2(0, submenu.offset - Submenu.HEIGHT)
	var backdrop := StringName("submenu_l%d" % room.dungeon_level if room.dungeon_level > 0 else "submenu_ow")
	if visual_theme.sprites.has(backdrop):
		draw_texture(visual_theme.sprites[backdrop], top)
	else:
		draw_rect(Rect2(top, Vector2(256, Submenu.HEIGHT)), Color.BLACK)
		draw_rect(Rect2(top + Vector2(56, 48), Vector2(32, 32)), Color("4a5ce0"), false, 2)
		draw_rect(Rect2(top + Vector2(120, 48), Vector2(104, 40)), Color("4a5ce0"), false, 2)
		draw_string(font, top + Vector2(32, 40), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("d84020"))
		draw_string(font, top + Vector2(16, 92), "B BUTTON ITEM", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)
	# Owned equipment in the top row, selectable items in the boxes.
	for i in range(Submenu.EQUIPMENT.size()):
		draw_submenu_item(Submenu.EQUIPMENT[i], top + Vector2(Submenu.equipment_position(i)))
	for index in range(9):
		var name: StringName = Submenu.SLOT_ITEMS[index] if index != 7 else (&"potion" if state.item_value(&"potion") > 0 else &"letter")
		if index == 3: name = &"bow"
		draw_submenu_item(name, top + Vector2(Submenu.item_position(index)))
	var selected: StringName = Submenu.item_at(state, submenu.slot)
	if selected != &"": draw_submenu_item(selected, top + Vector2(Submenu.SELECTED_BOX + Vector2i(0, 2)))
	if submenu.active():
		# The cursor flashes between palette rows 5 and 6 every eight frames.
		var flash := (simulation_tick >> 3) & 1
		var at: Vector2 = top + Vector2(Submenu.cursor_position(submenu.slot))
		for side in range(2):
			var sprite := StringName("submenu_cursor_%d%s" % [flash, "_right" if side else ""])
			if visual_theme.sprites.has(sprite): draw_texture(visual_theme.sprites[sprite], at + Vector2(side * 8, 0))
			else: draw_rect(Rect2(at + Vector2(side * 8, 0), Vector2(8, 16)), Color("d84020") if flash else Color("f0a050"), false, 1)
	if room.dungeon_level > 0: draw_submenu_map(top)
	else: draw_submenu_triforce(top)

func draw_submenu_item(slot: StringName, at: Vector2) -> void:
	if state.item_value(slot) <= 0: return
	var item: Resource = item_for_slot(slot)
	if item == null: return
	var sprite := item_sprite(item)
	if not visual_theme.sprites.has(sprite): sprite = StringName(String(sprite) + "_0")
	if visual_theme.sprites.has(sprite): draw_texture(visual_theme.sprites[sprite], at)
	else: draw_rect(Rect2(at + Vector2(4, 2), Vector2(8, 12)), Color("f0d070"))

## Z_05 UpdateMenuStartOW: each owned piece fills three tile slots; a slot a
## neighbouring piece already half filled ($E5, $E6) becomes full ($F5).
func draw_submenu_triforce(top: Vector2) -> void:
	var atlas: Texture2D = visual_theme.sprites.get(&"submenu_ow_tiles")
	if submenu_layout == null or atlas == null:
		var count := range(1, 9).filter(func(level: int) -> bool: return state.has_level_item(&"triforce", level)).size()
		draw_string(font, top + Vector2(96, 150), "TRIFORCE %d/8" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("f0a050"))
		return
	var tiles: Dictionary = submenu_triforce_tiles()
	for spot in tiles: draw_menu_tile(atlas, tiles[spot], top + spot)

## Menu-local position -> tile for the Triforce with the pieces Link holds.
func submenu_triforce_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for slot in range(24): tiles[submenu_layout.triforce_positions[slot]] = submenu_layout.triforce_empty[slot]
	for slot in range(24):
		if not state.has_level_item(&"triforce", slot / 3 + 1): continue
		var spot: Vector2 = submenu_layout.triforce_positions[slot]
		tiles[spot] = 0xF5 if tiles[spot] in [0xE5, 0xE6] else submenu_layout.triforce_full[slot]
	return tiles

func draw_menu_tile(atlas: Texture2D, tile: int, at: Vector2) -> void:
	draw_texture_rect_region(atlas, Rect2(at, Vector2(8, 8)), Rect2((tile % 16) * 8, (tile / 16) * 8, 8, 8))

## Z_05 Submenu_WriteSheetMapRowTransferRecord: rows of 16 rooms, rotated
## right by the level's rotation; masked cells and unvisited rooms stay blank,
## visited ones show which of their four doorways are walkable. The map and
## compass sit at the left; Link's room is marked.
func draw_submenu_map(top: Vector2) -> void:
	var level: int = room.dungeon_level
	for pair in [[&"map", 0x76], [&"compass", 0x9E]]:
		if state.has_level_item(pair[0], level):
			var item: Resource = item_for_slot(pair[0])
			if item == null: item = load("res://content/items/%s.tres" % pair[0])
			var sprite := item_sprite(item)
			if visual_theme.sprites.has(sprite): draw_texture(visual_theme.sprites[sprite], top + Vector2(0x2C, pair[1] + 2))
	var atlas: Texture2D = visual_theme.sprites.get(StringName("submenu_l%d_tiles" % level))
	var rotation: int = submenu_layout.map_rotations[level - 1] if submenu_layout != null and level <= submenu_layout.map_rotations.size() else 0
	var by_map: Dictionary = {}
	for definition in rooms.values():
		if definition.dungeon_level == level and definition.map_room_id >= 0: by_map[definition.map_room_id] = definition
	for row in range(8):
		for column in range(16):
			var place := (column + rotation) % 16
			if submenu_layout != null and level <= submenu_layout.map_rotations.size():
				if submenu_layout.map_masks[(level - 1) * 16 + place] & (0x80 >> row) == 0: continue
			var definition: Resource = by_map.get(row * 16 + column)
			if definition == null or not state.flags.get("visited/" + String(definition.id), false): continue
			var at: Vector2 = top + Vector2(96 + place * 8, (13 + row) * 8)
			if atlas != null: draw_menu_tile(atlas, 0xE2 + doorway_mask(definition), at)
			else: draw_rect(Rect2(at + Vector2(1, 1), Vector2(6, 6)), Color("f0a050"))
	if room.map_room_id >= 0:
		var shift: int = rotation * 8 if rotation < 8 else -(16 - rotation) * 8
		var marker: Vector2 = top + Vector2((room.map_room_id & 0x0F) * 8 + shift + 0x62, (room.map_room_id >> 4) * 8 + 0x69 + 2)
		if visual_theme.sprites.has(&"submenu_marker"): draw_texture(visual_theme.sprites[&"submenu_marker"], marker)
		else: draw_rect(Rect2(marker + Vector2(2, 2), Vector2(3, 3)), Color("40d040"))

## Z_05 CalcOpenDoorwayMask: up, down, left, right as bits 3-0; open doorways
## count, walls and false walls do not, and other doors count once opened.
func doorway_mask(definition: Resource) -> int:
	var mask := 0
	for direction in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var walkable := false
		for door in definition.doors:
			if door.direction != direction: continue
			if door.kind == "open": walkable = true
			elif door.kind in ["key", "bombable", "shutter"]: walkable = state.flags.get(door_key(definition, direction), false)
		mask = (mask << 1) | int(walkable)
	return mask

func draw_item_objects() -> void:
	for object in item_objects:
		if object.kind=="bait":
			if visual_theme.sprites.has(&"bait"):draw_named_sprite(&"bait",Vector2(object.position))
			else:draw_circle(Vector2(object.position)+Vector2(8,HUD_HEIGHT+8),4,Color("d89048"))
			continue
		if object.kind == "arrow":
			var name := StringName("monster_arrow_" + direction_name(object.direction))
			if object.stage == 1 and visual_theme.sprites.has(name): draw_named_sprite(name, Vector2(object.position))
			elif object.stage == 1: draw_line(Vector2(object.center()) + Vector2(0, HUD_HEIGHT) - Vector2(object.direction) * 6, Vector2(object.center()) + Vector2(0, HUD_HEIGHT) + Vector2(object.direction) * 6, Color("e8d090"), 2)
			continue
		if object.kind == "boomerang":
			var at := Vector2(object.position) + Vector2(0, HUD_HEIGHT)
			var spin := (simulation_tick / 3) % 4
			if visual_theme.sprites.has(&"boomerang"):
				draw_texture_rect(visual_theme.sprites[&"boomerang"], Rect2(at + Vector2(16 if spin & 1 else 0, 16 if spin & 2 else 0), Vector2(-16 if spin & 1 else 16, -16 if spin & 2 else 16)), false)
			else:
				draw_circle(at + Vector2(8, 8), 4, Color("c87830"))
			continue
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
	if visual_theme.hud_tiles == null:
		for i in range(text.length()):
			draw_string(font, at + Vector2(i * 8, 8), text.substr(i, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
		return
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
	# Z_01: with the magical key the count shows "XA".
	draw_hud_text(key_count_text(), Vector2(96, 32))
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

func ganon_intro() -> bool:
	return combat.enemies.any(func(a: RefCounted) -> bool: return a.definition.behavior == "ganon" and a.health > 0 and a.family.ganon != null and a.family.ganon.holds_player())

## The palette is global during scrolling, as on the NES. Ganon owns its intro.
func lighting_stage() -> int:
	return mini(3,combat.darkness()) if combat.darkness()>0 else lighting.stage

func terrain_atlas(definition: Resource) -> Texture2D:
	var stage:=lighting_stage()
	if stage>0 and definition.dark_tile_atlases.size()==3:return definition.dark_tile_atlases[stage-1]
	return definition.tile_atlas

func floor_tint(color: Color) -> Color:
	return color.darkened(float(lighting_stage())/3.0)

## Z_04 Ganon_DrawAshes and Ganon_DrawBurst: ashes, eight clouds closing in,
## and eight rays flying out with flashing palettes.
func draw_ganon_remains(actor: RefCounted) -> void:
	var fight: RefCounted = actor.family.ganon
	if fight == null or fight.dying < 0x50: return
	var prefix := "l%d_" % room.dungeon_level if room.dungeon_level > 0 else ""
	var at: Vector2i = actor.position()
	var ashes := StringName(prefix + String(actor.definition.sprite) + "_ashes")
	if visual_theme.sprites.has(ashes): draw_named_sprite(ashes, Vector2(at))
	else: draw_rect(Rect2(Vector2(at) + Vector2(2, HUD_HEIGHT + 8), Vector2(12, 8)), Color("c88830"))
	if fight.dying >= 0xA0: return
	var cloud := StringName(prefix + String(actor.definition.sprite) + "_cloud_" + ("0" if fight.cloud_distance >= 6 else "1"))
	for spot in fight.clouds(at):
		if visual_theme.sprites.has(cloud): draw_named_sprite(cloud, Vector2(spot))
		else: draw_circle(Vector2(spot) + Vector2(8, HUD_HEIGHT + 8), 5, Color(1, 1, 1, 0.5))
	for i in range(fight.rays.size()):
		var ray := StringName("%s%s_ray_%d_%d" % [prefix, actor.definition.sprite, i, simulation_tick & 3])
		if visual_theme.sprites.has(ray): draw_named_sprite(ray, Vector2(fight.rays[i]))
		else: draw_rect(Rect2(Vector2(fight.rays[i]) + Vector2(2, HUD_HEIGHT + 4), Vector2(4, 8)), Color("f8d878"))

## PondFairy_MoveHearts draws full hearts in the red palette row (the red
## frame of the flashing drop heart).
func draw_pond_hearts(actor: RefCounted) -> void:
	for heart in actor.family.hearts:
		if heart[0] == 0: continue
		var at := Vector2(floori(heart[2].x / 256.0), floori(heart[2].y / 256.0))
		if visual_theme.sprites.has(&"heart_1"): draw_named_sprite(&"heart_1", at)
		else: draw_circle(at + Vector2(8, HUD_HEIGHT + 8), 3, Color("e04040"))

func draw_combat() -> void:
	for actor in combat.enemies:
		if actor.definition.behavior == "ganon": draw_ganon_remains(actor)
		if actor.definition.behavior == "pond_fairy": draw_pond_hearts(actor)
	# Gleeok's fixed body and necks sit behind the attached/detached head sprites.
	for actor in combat.enemies:
		if actor.health <= 0 or actor.definition.behavior != "gleeok" or actor.family.gleeok == null: continue
		var prefix := "l%d_" % room.dungeon_level if room.dungeon_level > 0 else ""
		var body_sprite := StringName(prefix+String(actor.sprite_name()))
		if visual_theme.sprites.has(body_sprite): draw_named_sprite(body_sprite,Vector2(actor.position()),actor.definition.tint,Vector2(actor.size()))
		else: draw_rect(Rect2(Vector2(actor.position())+Vector2(0,HUD_HEIGHT),Vector2(actor.size())),actor.definition.fallback_color)
		var group: RefCounted = actor.family.gleeok
		for i in range(group.heads.size()):
			var head = group.heads[i].get_ref()
			if head == null or head.health <= 0 or head.family.gleeok_detached: continue
			for segment in range(4):
				var at: Vector2 = group.necks[i][segment]
				var neck_sprite := StringName(prefix+"gleeok_neck")
				if visual_theme.sprites.has(neck_sprite): draw_named_sprite(neck_sprite,at)
				else: draw_circle(at+Vector2(4,HUD_HEIGHT+8),3,actor.definition.fallback_color)
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
				draw_named_sprite(sprite, Vector2(actor.position()), actor.definition.tint, Vector2(actor.size()))
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
		elif rock.kind in ["sword", "magic"]: sprite = StringName(("magic_wave_" if rock.kind == "magic" else "beam_") + direction_name(rock.direction) + "_" + str(simulation_tick % 4))
		elif rock.kind == "fireball": sprite = StringName("fireball_" + str(simulation_tick % 2))
		if visual_theme.sprites.has(sprite):
			draw_named_sprite(sprite, Vector2(rock.position()) + (Vector2(0,3) if rock.kind in ["sword", "magic"] and rock.direction.x != 0 else Vector2.ZERO))
		elif rock.kind == "rock":
			draw_circle(Vector2(rock.position()) + Vector2(8, HUD_HEIGHT + 8), 3, Color("ba9670"))
		else:
			var center: Vector2 = Vector2(rock.position()) + Vector2(8,HUD_HEIGHT+8)
			draw_line(center-Vector2(rock.direction)*6,center+Vector2(rock.direction)*6,Color("eeeecc"),3)

	for reward in combat.rewards:
		if reward.age < reward.definition.pickup_delay_ticks and not reward.definition.flying and (reward.age / 2) % 2 != 0:
			continue
		var pose: int = (simulation_tick / reward.definition.frame_ticks) % 2
		var sprite := StringName(String(reward.definition.sprite) + "_" + str(pose))
		# Single-image drops such as bombs use the plain item sprite.
		if not visual_theme.sprites.has(sprite): sprite = reward.definition.sprite
		if visual_theme.sprites.has(sprite):
			draw_named_sprite(sprite, Vector2(reward.position))
		else:
			draw_circle(Vector2(reward.position) + Vector2(8, HUD_HEIGHT + 8), 4, reward.definition.fallback_color)

	if combat.beam != null:
		var beam = combat.beam
		var palette := simulation_tick % 4
		if beam.flying():
			var name := StringName(("magic_wave_" if beam.kind == "magic" else "beam_") + direction_name(beam.direction) + "_" + str(palette))
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
	var atlas: Texture2D=terrain_atlas(definition)
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
				draw_clipped_texture(atlas, rect, source)
				continue
			if definition.rows()[y][x] == "~":
				draw_rect(rect.intersection(Rect2(0, HUD_HEIGHT, 256, 176)), floor_tint(Color("3878a8")))
				continue
			var texture: Texture2D = visual_theme.wall_texture if wall else visual_theme.floor_texture
			if texture:
				draw_clipped_texture(texture, rect, Rect2(Vector2.ZERO, texture.get_size()),Color.WHITE if wall else floor_tint(Color.WHITE))
			else:
				draw_rect(rect.intersection(Rect2(0, 64, 256, 176)), visual_theme.wall_color if wall else floor_tint(visual_theme.floor_color))
				if wall:
					draw_rect(rect.grow(-3).intersection(Rect2(0, 64, 256, 176)), Color("394f36"), false, 1)
	var replaced: Dictionary = overrides if definition == room else compute_overrides(definition)
	for cell in replaced:
		draw_square(definition, replaced[cell][0], Vector2(cell * 16) + offset, replaced[cell][2])
	if definition.tile_atlas == null: draw_closed_doors(definition, offset)

## Unthemed rooms mark closed key doors and shutters; bombable and false walls
## stay hidden in the wall, as in the original.
func draw_closed_doors(definition: Resource, offset: Vector2) -> void:
	for door in definition.doors:
		if door.kind not in ["key", "shutter"] or door_passable(definition, door): continue
		var cells: PackedInt32Array = door.door_cells()
		if cells.is_empty(): continue
		var outer := Rect2()
		for index in cells:
			var square := Rect2(Vector2((index % 16) * 16, (index / 16) * 16 + HUD_HEIGHT) + offset, Vector2(16, 16))
			outer = square if outer.size == Vector2.ZERO else outer.merge(square)
		var clip := Rect2(0, HUD_HEIGHT, 256, 176)
		draw_rect(outer.grow(-2).intersection(clip), Color("2a2a2a"))
		if door.kind == "key":
			draw_rect(Rect2(outer.get_center() - Vector2(2, 4), Vector2(4, 8)).intersection(clip), visual_theme.accent_color)
		else:
			for bar in range(1, 4):
				var x: float = outer.position.x + outer.size.x * bar / 4.0
				draw_line(Vector2(x, outer.position.y + 2), Vector2(x, outer.end.y - 2), visual_theme.accent_color, 1)

## A replacement square: atlas index, or a placeholder color for unthemed rooms.
func draw_square(definition: Resource, index: int, at: Vector2, kind: String) -> void:
	var rect := Rect2(at + Vector2(0, HUD_HEIGHT), Vector2(16, 16))
	if definition.tile_atlas and index >= 0:
		var cell_size: Vector2i = definition.atlas_cell_size
		var columns: int = definition.tile_atlas.get_width() / cell_size.x
		draw_clipped_texture(terrain_atlas(definition), rect, Rect2(Vector2((index % columns) * cell_size.x, (index / columns) * cell_size.y), Vector2(cell_size)))
	else:
		var colors := {"floor": visual_theme.floor_color, "object": visual_theme.wall_color, "entrance": Color.BLACK, "door": visual_theme.floor_color, "false_door": visual_theme.wall_color}
		draw_rect(rect.intersection(Rect2(0, 64, 256, 176)), floor_tint(colors[kind]) if kind in ["floor","door","object"] else colors[kind])
		# A false wall must look exactly like the placeholder wall around it.
		if kind == "false_door": draw_rect(rect.grow(-3).intersection(Rect2(0, 64, 256, 176)), Color("394f36"), false, 1)

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
	if transition != null or raft.active or ladder.active or lighting.fading() or (cave_session!=null and cave_session.phase=="feeding") or entry_walk_remaining > 0 or lift_remaining > 0 or rise_remaining > 0 or state.health <= 0 or not state.rupees_settled():
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
