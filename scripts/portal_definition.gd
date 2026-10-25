class_name PortalDefinition
extends Resource

@export var area: Rect2i
@export var required_direction: Vector2i = Vector2i.ZERO
@export var target_room: StringName
@export var target_position: Vector2i
@export var target_facing: Vector2i = Vector2i.DOWN
@export var entry_walk_pixels: int = 0
## Z_07 StepOutside: arrive this far below the target and rise 1 pixel every
## 4 ticks, drawn only inside the doorway square.
@export var exit_rise_pixels: int = 0
## Active only after the room's secret has been revealed.
@export var requires_secret: bool = false
