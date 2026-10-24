class_name PortalDefinition
extends Resource

@export var area: Rect2i
@export var required_direction: Vector2i = Vector2i.ZERO
@export var target_room: StringName
@export var target_position: Vector2i
@export var target_facing: Vector2i = Vector2i.DOWN
@export var entry_walk_pixels: int = 0
