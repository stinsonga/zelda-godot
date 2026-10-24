extends Node2D

const Room = preload("res://scripts/room_definition.gd")
const Player = preload("res://scripts/player.gd")
const HUD_HEIGHT := 64
const ROOM_SIZE := Vector2i(256, 176)

@export var world_definition: Resource
@export var use_imported_world: bool = true
@export var room_resources: Array[Resource] = [
	preload("res://content/rooms/test_field.tres"),
	preload("res://content/rooms/expansion_field.tres")]
@export var visual_theme: Resource = preload("res://content/themes/default.tres")
var rooms: Dictionary = {}
var state = preload("res://scripts/game_state.gd").new()
var combat = preload("res://scripts/combat_simulation.gd").new()
var sword = preload("res://scripts/sword_action.gd").new()
var attack_requested := false
var simulation_tick := 0
var entry_walk_remaining := 0
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
	var start_id: StringName = &""
	var selected_world: Resource = world_definition
	if selected_world == null and use_imported_world and ResourceLoader.exists("res://imported/world.tres"):
		selected_world = load("res://imported/world.tres")
	if selected_world != null:
		room_resources = selected_world.rooms
		visual_theme = selected_world.visual_theme
		start_id = selected_world.start_room
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
		KEY_ENTER:
			if event.pressed and state.health == 0:
				state.health = state.max_health
				combat.player_invulnerability = 48
				enter_room(room, room.spawn, Vector2i.UP)
		KEY_Z, KEY_SPACE:
			if event.pressed:
				attack_requested = true
		KEY_R:
			if event.pressed:
				player.place(room.spawn)
	if direction != Vector2i.ZERO:
		held.erase(direction)
		if event.pressed:
			held.append(direction)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		attack_requested = false

func _physics_process(_delta: float) -> void:
	var direction: Vector2i = Vector2i.ZERO if held.is_empty() else held.back()
	simulate_tick(direction, attack_requested)
	attack_requested = false
	queue_redraw()

func enter_room(target: Resource, at: Vector2i, facing: Vector2i, entry_walk: int = 0) -> void:
	room = target
	player.grid_origin = room.grid_origin
	player.place(at)
	player.facing = facing
	entry_walk_remaining = entry_walk
	entry_direction = facing
	dialogue_elapsed = 0
	walk_ticks = 0
	walk_pose = 0
	sword.phase = -1
	combat.enter_room(room, state)

func dialogue_visible() -> bool:
	return not room.dialogue.is_empty() and (room.dialogue_until_pickup.is_empty() or not state.has_collected(room.id, room.dialogue_until_pickup))

func simulate_tick(direction: Vector2i, attack_pressed: bool = false) -> void:
	simulation_tick += 1
	if state.health <= 0:
		return
	if lift_remaining > 0:
		lift_remaining -= 1
		return
	var before: Vector2i = player.pixel_position()
	if entry_walk_remaining > 0:
		player.step(entry_direction, can_occupy, can_enter_segment)
		var moved: Vector2i = player.pixel_position() - before
		entry_walk_remaining = maxi(0, entry_walk_remaining - absi(moved.x) - absi(moved.y))
		assert(player.pixel_position() != before, "Portal entry walk is blocked")
	elif dialogue_visible() and dialogue_elapsed < room.dialogue.length() * room.dialogue_character_ticks:
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
	elif attack_pressed and sword.start(state.equipped_weapon, player.facing):
		combat.tick(self)
		return
	else:
		player.step(direction, can_occupy, can_enter_segment)
	if player.pixel_position() != before:
		walk_ticks += 1
		if walk_ticks >= 6:
			walk_ticks = 0
			walk_pose = 1 - walk_pose
	if entry_walk_remaining > 0:
		return
	if try_portal(direction):
		return
	try_exit(direction)
	try_pickups()
	if lift_remaining == 0:
		combat.tick(self)

func try_portal(direction: Vector2i) -> bool:
	for portal in room.portals:
		if not portal.area.has_point(player.pixel_position()):
			continue
		if portal.required_direction != Vector2i.ZERO and portal.required_direction != direction:
			continue
		var target: Resource = rooms[portal.target_room]
		var previous: Resource = room
		room = target
		var valid := can_occupy(portal.target_position)
		room = previous
		if valid:
			enter_room(target, portal.target_position, portal.target_facing, portal.entry_walk_pixels)
			return true
	return false

func try_pickups() -> void:
	for pickup in room.pickups:
		var distance: Vector2i = (player.pixel_position() - pickup.position).abs()
		if distance.x > pickup.tolerance.x or distance.y > pickup.tolerance.y:
			continue
		if state.collect(room.id, pickup):
			lifted_item = pickup.item
			lift_remaining = pickup.lift_ticks
			pickup_ticks[state.pickup_key(room.id, pickup.id)] = simulation_tick
			return

func decoration_visible(decoration: Resource) -> bool:
	if decoration.hide_after_pickup.is_empty() or not state.has_collected(room.id, decoration.hide_after_pickup):
		return true
	var key: String = state.pickup_key(room.id, decoration.hide_after_pickup)
	return pickup_ticks.has(key) and simulation_tick - pickup_ticks[key] < 64

func is_blocked(pixel: Vector2i) -> bool:
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
	var previous: Resource = room
	room = target
	if can_occupy(destination):
		enter_room(target, destination, player.facing)
	else:
		room = previous

func _draw() -> void:
	if room == null:
		return
	draw_rect(Rect2(0, 0, 256, 240), Color("171c20"))
	if visual_theme.hud_tiles:
		draw_original_hud()
	else:
		draw_string(font, Vector2(12, 18), "REPRODUCTION LAB", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, visual_theme.accent_color)
		draw_string(font, Vector2(205, 18), "%s/3" % (state.health / 2.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("ed7770"))
		draw_string(font, Vector2(12, 34), room.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(font, Vector2(12, 50), "ARROWS / WASD    Z: SWORD", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("a6b4bb"))
	for y in range(11):
		for x in range(16):
			var wall: bool = room.is_solid(Vector2i(x, y))
			var rect := Rect2(x * 16, HUD_HEIGHT + y * 16, 16, 16)
			if room.tile_atlas and not room.tile_indices.is_empty():
				var index: int = room.tile_indices[y * 16 + x]
				var cell_size: Vector2i = room.atlas_cell_size
				var columns: int = room.tile_atlas.get_width() / cell_size.x
				var source := Rect2(Vector2((index % columns) * cell_size.x, (index / columns) * cell_size.y), Vector2(cell_size))
				draw_texture_rect_region(room.tile_atlas, rect, source)
				continue
			var texture: Texture2D = visual_theme.wall_texture if wall else visual_theme.floor_texture
			if texture:
				draw_texture_rect(texture, rect, false)
			else:
				draw_rect(rect, visual_theme.wall_color if wall else visual_theme.floor_color)
				if wall:
					draw_rect(rect.grow(-3), Color("394f36"), false, 1)
	draw_room_objects()
	draw_combat()
	if combat.player_invulnerability == 0 or simulation_tick % 4 < 2:
		var at: Vector2 = Vector2(player.pixel_position()) + Vector2(0, HUD_HEIGHT)
		if lift_remaining > 0 and visual_theme.sprites.has(&"lift"):
			draw_named_sprite(&"lift", Vector2(player.pixel_position()))
			draw_named_sprite(lifted_item.id, Vector2(player.pixel_position()) - Vector2(4, 16))
		elif sword.active() and visual_theme.sprites.has(StringName("attack_" + direction_name(sword.direction))):
			draw_named_sprite(StringName("attack_" + direction_name(sword.direction)), Vector2(player.pixel_position()) + Vector2(0, 2))
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
			draw_named_sprite(StringName("sword_" + direction_name(sword.direction)), Vector2(player.pixel_position() + sword.offset()))

	if state.health == 0:
		draw_rect(Rect2(0, 64, 256, 176), Color(0, 0, 0, 0.75))
		if visual_theme.hud_tiles:
			draw_hud_text("GAME OVER", Vector2(88, 112))
			draw_hud_text("ENTER TO RETRY", Vector2(72, 136))
		else:
			draw_string(font, Vector2(60, 120), "GAME OVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			draw_string(font, Vector2(50, 144), "ENTER TO RETRY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func direction_name(direction: Vector2i) -> String:
	if direction == Vector2i.RIGHT: return "right"
	if direction == Vector2i.LEFT: return "left"
	if direction == Vector2i.DOWN: return "down"
	return "up"

func draw_named_sprite(name: StringName, position_in_room: Vector2, tint: Color = Color.WHITE) -> void:
	if visual_theme.sprites.has(name):
		draw_texture_rect(visual_theme.sprites[name], Rect2(position_in_room + Vector2(0, HUD_HEIGHT), Vector2(16, 16)), false, tint)

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
		if not state.has_collected(room.id, pickup.id):
			draw_named_sprite(pickup.item.id, Vector2(pickup.position))
	if dialogue_visible() and entry_walk_remaining == 0:
		var shown: String = room.dialogue.substr(0, dialogue_elapsed / room.dialogue_character_ticks)
		var lines: PackedStringArray = shown.split("\n")
		for i in range(lines.size()):
			draw_hud_text(lines[i], Vector2(32, 104 + i * 8))

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
		elif code == 63: tile = 0x2B
		if tile >= 0:
			draw_texture_rect_region(visual_theme.hud_tiles, Rect2(at + Vector2(i * 8, 0), Vector2(8, 8)), Rect2((tile % 16) * 8, (tile / 16) * 8, 8, 8), color)

func draw_original_hud() -> void:
	# Sword ownership is live; counters and health remain presentation scaffolding.
	draw_rect(Rect2(0, 0, 256, 64), Color.BLACK)
	draw_rect(Rect2(16, 16, 64, 32), Color("666666"))
	var room_number: int = room.map_room_id if room.map_room_id >= 0 else 0
	draw_rect(Rect2(16 + room_number % 16 * 4, 16 + (room_number / 16) * 4, 4, 4), Color("80d010"))
	draw_hud_text("X00", Vector2(96, 16))
	draw_hud_text("X00", Vector2(96, 32))
	draw_hud_text("X00", Vector2(96, 40))
	draw_rect(Rect2(124, 24, 20, 24), Color("4070c0"), false, 2)
	draw_rect(Rect2(148, 24, 20, 24), Color("4070c0"), false, 2)
	draw_hud_text("B", Vector2(128, 16))
	draw_hud_text("A", Vector2(152, 16))
	draw_hud_text("-LIFE-", Vector2(176, 16), Color("e85050"))
	for i in range(state.max_health / 2):
		var tile := 0xF2 if state.health >= (i + 1) * 2 else 0x65 if state.health == i * 2 + 1 else 0x66
		draw_texture_rect_region(visual_theme.hud_tiles, Rect2(176 + i * 8, 32, 8, 8), Rect2((tile % 16) * 8, (tile / 16) * 8, 8, 8), Color("e85050"))

	if state.equipped_weapon != null and visual_theme.sprites.has(state.equipped_weapon.id):
		draw_texture_rect(visual_theme.sprites[state.equipped_weapon.id], Rect2(150, 28, 16, 16), false)

func draw_combat() -> void:
	for actor in combat.enemies:
		var at: Vector2 = Vector2(actor.position()) + Vector2(0, HUD_HEIGHT)
		if actor.spawn_remaining > 0:
			draw_circle(at + Vector2(8, 8), 3 + actor.spawn_remaining % 4, Color("f0e6c8"))
		elif actor.health <= 0:
			if actor.death_remaining > 0:
				draw_circle(at + Vector2(8, 8), actor.death_remaining / 2.0, Color("fff4c8"))
		elif actor.invulnerability == 0 or simulation_tick % 4 < 2:
			var pose: int = (actor.animation_ticks / 6) % 2
			var sprite := StringName(String(actor.definition.sprite) + "_" + direction_name(actor.facing) + "_" + str(pose))
			if visual_theme.sprites.has(sprite):
				draw_named_sprite(sprite, Vector2(actor.position()), actor.definition.tint)
			else:
				draw_rect(Rect2(at + Vector2(1, 2), Vector2(14, 12)), actor.definition.fallback_color)
				draw_line(at + Vector2(8, 8), at + Vector2(8, 8) + Vector2(actor.facing) * 8, Color.BLACK, 2)
	for rock in combat.rocks:
		if visual_theme.sprites.has(&"rock"):
			draw_named_sprite(&"rock", Vector2(rock.position()))
		else:
			draw_circle(Vector2(rock.position()) + Vector2(8, HUD_HEIGHT + 8), 3, Color("ba9670"))
