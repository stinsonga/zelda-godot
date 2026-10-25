class_name RoomDefinition
extends Resource
## A room is 16 x 11 logical tiles. IDs are independent of NES addresses.
## Native unique encounters default to permanent; imported overworld uses counts.
@export_enum("permanent", "overworld", "reset") var enemy_persistence: String = "permanent"
@export var source_edge_spawns: bool = false
@export var source_edge_cells: PackedByteArray = PackedByteArray()
@export var history_id: StringName
@export var tracks_history: bool = true
@export var enemies: Array[Resource] = []
@export var portals: Array[Resource] = []
@export var pickups: Array[Resource] = []
@export var decorations: Array[Resource] = []
@export_multiline var dialogue: String = ""
@export var dialogue_until_pickup: StringName
@export var dialogue_character_ticks: int = 6
@export var map_room_id: int = -1
@export var id: StringName
@export var title: String = ""
@export_multiline var tiles: String = ""
@export var exits: Dictionary[String, String] = {}
@export var movement_bounds: Rect2i = Rect2i(0, 0, 241, 161)
@export var grid_origin: Vector2i = Vector2i.ZERO
@export var tile_atlas: Texture2D
@export var atlas_cell_size: Vector2i = Vector2i(16, 16)
@export var tile_indices: PackedInt32Array = PackedInt32Array()
@export var collision_tiles: PackedByteArray = PackedByteArray()
@export var spawn: Vector2i = Vector2i(120, 136)

func rows() -> PackedStringArray:
	return tiles.strip_edges().split("\n")

func is_solid(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= 16 or cell.y < 0 or cell.y >= 11:
		return true
	return rows()[cell.y][cell.x] == "#"

func is_pixel_solid(pixel: Vector2i) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= 256 or pixel.y >= 176:
		return true
	if not collision_tiles.is_empty():
		return collision_tiles[(pixel.y / 8) * 32 + pixel.x / 8] != 0
	return is_solid(Vector2i(pixel.x / 16, pixel.y / 16))

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if enemy_persistence not in ["permanent", "overworld", "reset"]:
		errors.append("Unknown enemy persistence policy")
	if id.is_empty():
		errors.append("Room ID is empty")
	if not tile_indices.is_empty() and (tile_indices.size() != 176 or tile_atlas == null):
		errors.append("Visual tiles require 176 atlas indices and a texture")
	if atlas_cell_size.x <= 0 or atlas_cell_size.y <= 0:
		errors.append("Atlas cell dimensions must be positive")
	elif tile_atlas != null:
		var capacity := (tile_atlas.get_width() / atlas_cell_size.x) * (tile_atlas.get_height() / atlas_cell_size.y)
		for index in tile_indices:
			if index < 0 or index >= capacity:
				errors.append("Atlas tile index out of bounds")
	if not collision_tiles.is_empty() and collision_tiles.size() != 704:
		errors.append("Fine collision requires 704 eight-pixel cells")
	if dialogue_character_ticks < 1:
		errors.append("Dialogue character interval must be positive")
	var enemy_ids: Dictionary = {}
	for spawn in enemies:
		if spawn.id.is_empty() or enemy_ids.has(spawn.id):
			errors.append("Enemy spawn IDs must be unique and nonempty")
		enemy_ids[spawn.id] = true
		if spawn.enemy == null:
			errors.append("Enemy spawn is missing a definition")
		elif spawn.enemy.health < 1 or spawn.enemy.speed_subpixels < 0 or spawn.enemy.shoot_windup < 1:
			errors.append("Enemy health, speed, or shooting timing is invalid")
	var pickup_ids: Dictionary = {}
	for pickup in pickups:
		if pickup.id.is_empty() or pickup_ids.has(pickup.id):
			errors.append("Pickup IDs must be unique and nonempty within a room")
		pickup_ids[pickup.id] = true
		if pickup.item == null:
			errors.append("Pickup is missing an item definition")
	for portal in portals:
		if portal.target_room.is_empty() or portal.area.size.x <= 0 or portal.area.size.y <= 0:
			errors.append("Portal requires an area and destination")
	var lines := rows()
	if lines.size() != 11:
		errors.append("Room must have 11 rows")
	for line in lines:
		if line.length() != 16:
			errors.append("Room rows must have 16 tiles")
		for tile in line:
			if tile != "." and tile != "#":
				errors.append("Unknown tile: " + tile)
	for edge in exits:
		if edge not in ["left", "right", "up", "down"]:
			errors.append("Unknown exit edge: " + edge)
	return errors
