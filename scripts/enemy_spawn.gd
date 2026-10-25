class_name EnemySpawn
extends Resource

@export var id: StringName
@export var enemy: Resource
@export var position: Vector2i
@export var facing: Vector2i = Vector2i.DOWN
@export var seed_value: int = 1

## Negative uses the enemy definition; original rooms can stagger each slot.
@export var spawn_ticks: int = -1
