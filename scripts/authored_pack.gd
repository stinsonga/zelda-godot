extends RefCounted
## Runtime adapter: the editor's data contract builds the existing game resources.
const Contract = preload("res://editor/shared/room_pack.gd")
const Room = preload("res://scripts/room_definition.gd")
const World = preload("res://scripts/world_definition.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Door = preload("res://scripts/door_definition.gd")
const Pickup = preload("res://scripts/pickup_definition.gd")
const DIRECTIONS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
static func compile(pack: Dictionary) -> Dictionary:
	var errors := Contract.validate(pack)
	if not errors.is_empty(): return {"errors":errors}
	var world = World.new()
	world.id = StringName("authored/" + pack.id)
	world.start_room = StringName(pack.start_room)
	world.visual_theme = load("res://content/themes/default.tres")
	var definitions: Dictionary = {}
	for id in pack.enemy_types:
		var source: Dictionary = pack.enemy_types[id]
		var enemy = Enemy.new()
		enemy.id = StringName("custom_" + pack.id + "_" + id)
		enemy.title = source.title
		enemy.behavior = source.behavior
		enemy.health = int(source.health)
		enemy.speed_subpixels = int(source.speed_subpixels)
		enemy.contact_damage = int(source.contact_damage)
		enemy.shooting_enabled = false
		enemy.fallback_color = Color("ec7967")
		definitions[id] = enemy
	for source in pack.rooms:
		var room = Room.new()
		room.id = StringName(source.id)
		room.title = source.title
		room.tiles = "\n".join(source.tiles)
		room.spawn = Vector2i(int(source.spawn[0]),int(source.spawn[1]))
		room.grid_origin = Vector2i(0,5)
		room.movement_bounds = Rect2i(0,-3,241,161)
		room.dungeon_level = 10
		room.map_room_id = (15+int(source.map_position[1]))*16+int(source.map_position[0])
		room.shutter_trigger = int(source.shutter_trigger)
		room.enemy_persistence = "reset"
		room.music = &""
		for edge in source.connections:
			var link: Dictionary = source.connections[edge]
			room.exits[edge] = link.target
			var door = Door.new()
			door.direction = DIRECTIONS[edge]
			door.kind = link.kind
			room.doors.append(door)
		for placement in source.enemies:
			var spawn = Spawn.new()
			spawn.id = StringName(placement.id)
			spawn.enemy = definitions[placement.type]
			spawn.position = Vector2i(int(placement.position[0]),int(placement.position[1]))
			room.enemies.append(spawn)
		for placement in source.pickups:
			var pickup = Pickup.new()
			pickup.id = StringName(placement.id)
			pickup.item = load("res://content/items/" + placement.item + ".tres")
			pickup.position = Vector2i(int(placement.position[0]),int(placement.position[1]))
			pickup.tolerance = Vector2i(8,8)
			pickup.lift_ticks = 0
			room.pickups.append(pickup)
		errors.append_array(room.validation_errors())
		world.rooms.append(room)
	return {"errors":errors,"world":world}
