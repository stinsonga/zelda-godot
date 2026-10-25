class_name DoorDefinition
extends Resource
## One underworld doorway (Z_05 TouchDoor). Cells are 16-pixel squares replaced
## while the door is passable; collision masks hold four eight-pixel parts,
## column-major, bit set when blocked. Authored doors may leave the cell arrays
## empty: direction and kind are then enough (see STANDARD_CELLS).
@export var direction: Vector2i = Vector2i.UP
@export_enum("open", "wall", "false", "bombable", "key", "shutter") var kind: String = "open"
@export var cells: PackedInt32Array = PackedInt32Array()
@export var open_tiles: PackedInt32Array = PackedInt32Array()
@export var open_collision: PackedInt32Array = PackedInt32Array()

## Doorway squares by direction, two deep through the wall, and their collision
## (column-major parts, bit set when blocked): the 16-pixel lane through the
## middle of an up or down door, every part of a left or right door. These match
## what the importer derives for closed doors; open doorways replace only the
## outer row, since the room layout already opens the inner one.
const STANDARD_CELLS := {Vector2i.UP: [7, 8, 23, 24], Vector2i.DOWN: [151, 152, 167, 168], Vector2i.LEFT: [80, 81], Vector2i.RIGHT: [94, 95]}
const STANDARD_COLLISION := {Vector2i.UP: [3, 12, 3, 12], Vector2i.DOWN: [3, 12, 3, 12], Vector2i.LEFT: [0, 0], Vector2i.RIGHT: [0, 0]}

## Cells replaced while passable: the authored ones, or the standard doorway.
func door_cells() -> PackedInt32Array:
	if not cells.is_empty(): return cells
	return PackedInt32Array(STANDARD_CELLS.get(direction, []))

func door_collision() -> PackedInt32Array:
	if not cells.is_empty(): return open_collision
	return PackedInt32Array(STANDARD_COLLISION.get(direction, []))

## Atlas indices for the open doorway; -1 draws the theme's placeholder.
func door_tiles() -> PackedInt32Array:
	if not cells.is_empty(): return open_tiles
	var tiles := PackedInt32Array()
	tiles.resize(door_cells().size())
	tiles.fill(-1)
	return tiles

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
	if kind == "wall" and not cells.is_empty(): errors.append("A wall door has no doorway cells")
	if cells.size() != open_tiles.size() or cells.size() != open_collision.size(): errors.append("Door cell arrays must match")
	for cell in cells:
		if cell < 0 or cell >= 176: errors.append("Door cell outside the room")
	return errors
