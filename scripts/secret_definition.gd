class_name SecretDefinition
extends Resource
## One overworld tile object (Z_05 CheckTileObject). Cells are 16-pixel squares.
## "block" is an underworld push block: any direction, after 16 ticks of pushing.
## "recorder" drains a pond after the tune (Z_07 UpdateFluteSecret).
## "armos": revealed when the Armos standing on `cell` wakes (Z_04
## InitArmosOrFlyingGhini's SecretArmosRoomIds/Xs).
@export_enum("bomb", "fire", "push", "bracelet_push", "block", "recorder", "armos") var trigger: String = "bomb"
## Eight-pixel collision once a pond is drained: water below tile $99 becomes walkable.
@export var drained_collision: PackedByteArray = PackedByteArray()
## What a revealed block opens: stairs at reveal_cell, or the room's shutters.
## "item" shows floor and lets the room's requires_secret pickups appear.
@export_enum("entrance", "stairs", "shutters", "item") var reveal_kind: String = "entrance"
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
