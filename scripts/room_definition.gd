class_name RoomDefinition
extends Resource
## Optional authored room graphics; no collision or trigger behavior.
@export var authored_sprites: Dictionary = {}
@export var authored_frame_ticks: Dictionary = {}
@export var authored_sprite_layouts: Dictionary = {}
## A room is 16 x 11 logical tiles. IDs are independent of NES addresses.
## Native unique encounters default to permanent; imported overworld uses counts.
@export_enum("permanent", "overworld", "reset") var enemy_persistence: String = "permanent"
## Original Moldorm uses ten live segments but stores at most eight kills.
@export var persistence_enemy_count: int = 0
## Dark rooms fade background palettes; sprites and HUD remain unaffected.
@export var dark_room: bool = false
## Source mode follows the first enemy template; custom rooms may override it.
@export_enum("source", "enabled", "disabled") var bait_attraction: String = "source"
@export var dark_tile_atlases: Array[Texture2D] = []
@export_range(1, 120) var light_step_ticks: int = 10
@export var source_spawn_lists: bool = false
@export var source_edge_spawns: bool = false
@export var source_edge_cells: PackedByteArray = PackedByteArray()
@export var history_id: StringName
@export var tracks_history: bool = true
@export var enemies: Array[Resource] = []
@export var portals: Array[Resource] = []
@export var pickups: Array[Resource] = []
@export var reward_spawns: Array[Resource] = []
@export var decorations: Array[Resource] = []
## Cave resident and wares (CaveDefinition); people in caves block the upper half.
@export var cave: Resource
## At most one overworld tile object per room, as in the original.
@export var secret: Resource
## Automatic mainland dock route; island rooms use their normal exits.
@export var raft_route: Resource
## Underworld doorways (DoorDefinition) and the room's original secret trigger
## (Z_05 CheckSecretTrigger: 1 and 7 all dead, 3 boss, 4 push block, 5 block stairs).
@export var doors: Array[Resource] = []
@export var dungeon_level: int = 0
@export var shutter_trigger: int = 0
@export_multiline var dialogue: String = ""
@export var dialogue_until_pickup: StringName
@export var dialogue_character_ticks: int = 6
@export var map_room_id: int = -1
@export var id: StringName
@export var title: String = ""
@export var ambient_sample: StringName
## Empty means unconditional ambience; otherwise stop after this boss room clears.
@export var ambient_boss_room: StringName
@export var music: StringName = &"overworld" # Empty selects silence.
@export_multiline var tiles: String = ""
@export var exits: Dictionary[String, String] = {}
@export var movement_bounds: Rect2i = Rect2i(0, 0, 241, 161)
## Where monsters may roam (Z_05 ObjectRoomBoundsOW/UW); empty uses the
## original overworld or underworld bounds.
@export var monster_bounds: Rect2i = Rect2i()
## Dungeon statues that shoot (Z_04 UpdateStatues): fireball origins, and the
## origins used instead once Link strikes the room's resident.
@export var statues: PackedVector2Array = PackedVector2Array()
@export var provoked_statues: PackedVector2Array = PackedVector2Array()
@export var statue_damage: int = 1
## Z_04 CheckZora: a room whose attribute A has $08 keeps one Zora surfacing
## in its water (`ladder_water`). Null means no Zora.
@export var zora: Resource
## Z_01 CheckPassiveTileObjects: statue squares (tiles $C0-$C3) that wake as
## `armos` when Link presses into them, and the floor each leaves behind (atlas
## index; -1 draws the placeholder floor).
@export var armos: Resource
@export var armos_cells: PackedVector2Array = PackedVector2Array()
@export var armos_floor_tiles: PackedInt32Array = PackedInt32Array()
## Gravestone squares (tiles $BC-$BF): pressing into one raises `ghost`, a
## flying Ghini; the stone stays.
@export var ghost: Resource
@export var grave_cells: PackedVector2Array = PackedVector2Array()
## Z_01 CheckMazes: leaving by the next direction of `maze` advances a step and
## repeats the room, the last step lets Link through with the secret tune,
## `maze_free_exit` leaves without resetting, and anything else starts over.
@export var maze: PackedStringArray = PackedStringArray()
@export var maze_free_exit: String = ""
@export var grid_origin: Vector2i = Vector2i.ZERO
@export var tile_atlas: Texture2D
@export var atlas_cell_size: Vector2i = Vector2i(16, 16)
@export var tile_indices: PackedInt32Array = PackedInt32Array()
@export var collision_tiles: PackedByteArray = PackedByteArray()
## Ladder-eligible water, independent of art and ordinary collision. Fine masks
## use the same 32 x 22 eight-pixel cells as collision_tiles.
@export var ladder_allowed: bool = true
## Z_07 GetCollidableTile: vertical moves keep the higher of two adjacent column
## tiles, so a blocking tile beside a higher walkable one is missed. Each cell says
## whether the pair starting there blocks; empty means check each column alone.
@export var pair_collision: PackedByteArray = PackedByteArray()
## The room's layout holds a tile object (a bush, rock, or gravestone square,
## Z_05 RoomTileObjType), which takes object slot 11 for the whole visit.
@export var tile_object_slot: bool = false
## A false wall Link alone walks through vertically (Z_07 GetCollidingTileMoving:
## room $1F, X $80, Y below $56): with his X at false_wall_x and Y above
## false_wall_below_y, vertical moves ignore the tiles. -1 means none.
@export var false_wall_x: int = -1
@export var false_wall_below_y: int = 0
@export var ladder_water: PackedByteArray = PackedByteArray()
## Mountain stairs (overworld tiles $74/$75) per eight-pixel cell: Z_05 InitLinkSpeed
## halves Link's speed on them. Empty means none.
@export var stairs_tiles: PackedByteArray = PackedByteArray()

@export var spawn: Vector2i = Vector2i(120, 136)

func rows() -> PackedStringArray:
	return tiles.strip_edges().split("\n")

func is_solid(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= 16 or cell.y < 0 or cell.y >= 11:
		return true
	return rows()[cell.y][cell.x] in ["#", "~"]

func is_pixel_solid(pixel: Vector2i) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= 256 or pixel.y >= 176:
		return true
	if not collision_tiles.is_empty():
		return collision_tiles[(pixel.y / 8) * 32 + pixel.x / 8] != 0
	return is_solid(Vector2i(pixel.x / 16, pixel.y / 16))

## The eight-pixel column at pixel and the one to its right, as a vertical move reads them.
func is_pair_solid(pixel: Vector2i) -> bool:
	if pair_collision.is_empty() or pixel.x < 0 or pixel.y < 0 or pixel.x >= 256 or pixel.y >= 176:
		return is_pixel_solid(pixel) or is_pixel_solid(pixel + Vector2i(8, 0))
	return pair_collision[(pixel.y / 8) * 32 + pixel.x / 8] != 0

func is_ladder_water(pixel: Vector2i) -> bool:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= 256 or pixel.y >= 176: return false
	if not ladder_water.is_empty():
		return ladder_water[(pixel.y / 8) * 32 + pixel.x / 8] != 0
	return rows()[pixel.y / 16][pixel.x / 16] == "~"

func is_stairs(pixel: Vector2i) -> bool:
	if stairs_tiles.is_empty() or pixel.x < 0 or pixel.y < 0 or pixel.x >= 256 or pixel.y >= 176: return false
	return stairs_tiles[(pixel.y / 8) * 32 + pixel.x / 8] != 0

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if light_step_ticks < 1: errors.append("Lighting steps need positive timing")
	if not dark_tile_atlases.is_empty():
		if dark_tile_atlases.size()!=3:errors.append("Lighting requires three progressively darker atlases")
		for atlas in dark_tile_atlases:
			if atlas==null or tile_atlas==null or atlas.get_size()!=tile_atlas.get_size():errors.append("Lighting atlases must match the base atlas")
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
	if not pair_collision.is_empty() and pair_collision.size() != 704:
		errors.append("Pair collision requires 704 eight-pixel cells")
	if not ladder_water.is_empty() and ladder_water.size() != 704:
		errors.append("Ladder water requires 704 eight-pixel cells")
	if not stairs_tiles.is_empty() and stairs_tiles.size() != 704:
		errors.append("Stairs tiles require 704 eight-pixel cells")
	if dialogue_character_ticks < 1:
		errors.append("Dialogue character interval must be positive")
	if raft_route != null:
		errors.append_array(raft_route.validation_errors())
		for at in [raft_route.dock_position, raft_route.edge_position, raft_route.landing_position]:
			if not movement_bounds.has_point(at): errors.append("Raft route point is outside movement bounds")
		var direction: Vector2i = raft_route.direction()
		var edge: Vector2i = raft_route.edge_position
		if (direction == Vector2i.UP and edge.y != movement_bounds.position.y) or (direction == Vector2i.DOWN and edge.y != movement_bounds.end.y - 1) or (direction == Vector2i.LEFT and edge.x != movement_bounds.position.x) or (direction == Vector2i.RIGHT and edge.x != movement_bounds.end.x - 1): errors.append("Raft edge must meet the screen boundary")
		if not exits.has(raft_route.exit_name()): errors.append("Raft route needs a matching room exit")
	var enemy_ids: Dictionary = {}
	for spawn in enemies:
		if spawn.id.is_empty() or enemy_ids.has(spawn.id):
			errors.append("Enemy spawn IDs must be unique and nonempty")
		enemy_ids[spawn.id] = true
		if spawn.enemy != null:
			errors.append_array(spawn.enemy.validation_errors())
		if spawn.enemy == null:
			errors.append("Enemy spawn is missing a definition")
		elif spawn.enemy.health < 1 or spawn.enemy.speed_subpixels < 0 or spawn.enemy.shoot_windup < 1:
			errors.append("Enemy health, speed, or shooting timing is invalid")
	for spawn in reward_spawns:
		if spawn.definition == null: errors.append("Reward spawn needs a definition")
		else: errors.append_array(spawn.definition.validation_errors())
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
		if portal.requires_secret and secret == null:
			errors.append("Secret portal requires a room secret")
	if cave != null:
		errors.append_array(cave.validation_errors())
	for door in doors:
		errors.append_array(door.validation_errors())
	if secret != null:
		errors.append_array(secret.validation_errors())
	var lines := rows()
	if lines.size() != 11:
		errors.append("Room must have 11 rows")
	for line in lines:
		if line.length() != 16:
			errors.append("Room rows must have 16 tiles")
		for tile in line:
			if tile not in [".", "#", "~"]:
				errors.append("Unknown tile: " + tile)
	for edge in exits:
		if edge not in ["left", "right", "up", "down"]:
			errors.append("Unknown exit edge: " + edge)
	return errors
