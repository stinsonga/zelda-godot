class_name RaftRoute
extends Resource
## One mainland screen's automatic dock-to-edge route. The neighboring island
## uses ordinary movement; entering this edge on return starts the inbound ride.
@export var dock_position := Vector2i(96, 61)
@export var edge_position := Vector2i(96, -3)
@export var landing_position := Vector2i(96, 63)
@export var speed_pixels_per_tick: int = 1
@export var sprite_offset := Vector2i(0, 6)

func direction() -> Vector2i:
	return (edge_position - dock_position).sign()

func exit_name() -> String:
	match direction():
		Vector2i.UP: return "up"
		Vector2i.DOWN: return "down"
		Vector2i.LEFT: return "left"
		Vector2i.RIGHT: return "right"
	return ""

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var vector := edge_position - dock_position
	if vector == Vector2i.ZERO or (vector.x != 0 and vector.y != 0): errors.append("Raft route needs a straight, nonzero crossing")
	var landing := landing_position - dock_position
	var facing := direction()
	if (landing.x != 0 and facing.x == 0) or (landing.y != 0 and facing.y == 0) or landing.x * facing.x + landing.y * facing.y >= 0: errors.append("Raft landing must be behind the dock on the same line")
	if speed_pixels_per_tick < 1: errors.append("Raft speed must be positive")
	return errors
