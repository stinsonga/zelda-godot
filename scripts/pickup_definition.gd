class_name PickupDefinition
extends Resource

@export var id: StringName
@export var item: Resource
@export var position: Vector2i
@export var tolerance: Vector2i = Vector2i(0, 5)
@export var lift_ticks: int = 128
## Appears only once the room is clear (original secret triggers 3 and 7).
@export var requires_clear: bool = false
