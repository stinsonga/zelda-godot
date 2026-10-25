class_name WeaponDefinition
extends "res://scripts/item_definition.gd"

@export var damage: int = 1
@export var phase_ticks: PackedInt32Array = PackedInt32Array([5, 8, 1, 1, 1])
## Four phases, each in up/down/left/right order, copied from original tables.
@export var offsets_x: PackedInt32Array = PackedInt32Array([-1, 1, 0, -8, -1, 1, -11, 11, -1, 1, -7, 7, -1, 1, -3, 3])
@export var offsets_y: PackedInt32Array = PackedInt32Array([-9, -14, -11, -11, -10, 13, 3, 3, -9, 9, 3, 3, -1, 5, 3, 3])

@export var fires_beam: bool = true
## Sword sprite prefix for attack poses; empty uses the wooden sword's.
@export var sprite_prefix: StringName

func _init() -> void:
	effect = "grade"
	slot = &"sword"
