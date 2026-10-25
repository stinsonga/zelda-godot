class_name DoorDefinition
extends Resource
## One underworld doorway (Z_05 TouchDoor). Cells are 16-pixel squares replaced
## while the door is passable; collision masks hold four eight-pixel parts,
## column-major, bit set when blocked.
@export var direction: Vector2i = Vector2i.UP
@export_enum("open", "wall", "false", "bombable", "key", "shutter") var kind: String = "open"
@export var cells: PackedInt32Array = PackedInt32Array()
@export var open_tiles: PackedInt32Array = PackedInt32Array()
@export var open_collision: PackedInt32Array = PackedInt32Array()

## Z_05 DoorwayBoundsMinOver/MaxOver and DoorwayRequiredCoord, play-area pixels.
func in_doorway(at: Vector2i) -> bool:
	match direction:
		Vector2i.UP: return at.x == 120 and at.y >= -3 and at.y < 30
		Vector2i.DOWN: return at.x == 120 and at.y >= 125 and at.y < 158
		Vector2i.LEFT: return at.y == 77 and at.x >= 0 and at.x < 33
		_: return at.y == 77 and at.x >= 207 and at.x < 241

## Z_07 BombableWallHotspots.
func bomb_hotspot() -> Vector2i:
	match direction:
		Vector2i.UP: return Vector2i(120, 29)
		Vector2i.DOWN: return Vector2i(120, 125)
		Vector2i.LEFT: return Vector2i(32, 77)
		_: return Vector2i(208, 77)

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if direction.abs().x + direction.abs().y != 1: errors.append("Door direction must be cardinal")
	if cells.size() != open_tiles.size() or cells.size() != open_collision.size(): errors.append("Door cell arrays must match")
	for cell in cells:
		if cell < 0 or cell >= 176: errors.append("Door cell outside the room")
	return errors
