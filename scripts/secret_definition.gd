class_name SecretDefinition
extends Resource
## One overworld tile object (Z_05 CheckTileObject). Cells are 16-pixel squares.
@export_enum("bomb", "fire", "push", "bracelet_push") var trigger: String = "bomb"
@export var cell: Vector2i
## Where the entrance appears. Pushes use the room's shortcut position.
@export var reveal_cell: Vector2i
## Atlas indices; -1 draws placeholder colors in unthemed rooms.
@export var reveal_tile: int = -1
@export var floor_tile: int = -1
@export var object_tile: int = -1
## Eight-pixel collision for the revealed square, column-major like the importer.
@export var reveal_collision: PackedByteArray = PackedByteArray([0, 0, 0, 0])
@export var object_collision: PackedByteArray = PackedByteArray([1, 1, 1, 1])
## Bomb walls and trees set this flag. Rock shortcuts remember their stairs too.
@export var persistent: bool = true

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for value in [cell, reveal_cell]:
		if value.x < 0 or value.x >= 16 or value.y < 0 or value.y >= 11: errors.append("Secret cell is outside the room")
	if reveal_collision.size() != 4 or object_collision.size() != 4: errors.append("Secret collision needs four eight-pixel cells")
	return errors
