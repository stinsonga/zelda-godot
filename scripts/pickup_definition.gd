class_name PickupDefinition
extends Resource

@export var id: StringName
@export var item: Resource
@export var position: Vector2i
@export var tolerance: Vector2i = Vector2i(0, 5)
@export var lift_ticks: int = 128
