class_name WorldDefinition
extends Resource

@export var id: StringName
@export var items: Array[Resource] = []
@export var start_room: StringName
@export var rooms: Array[Resource] = []
@export var visual_theme: Resource
@export var audio_bank: Resource

@export var loot_tables: Dictionary[StringName, Resource] = {}

@export var spawn_lists: Array[PackedByteArray] = []
@export var projectile_limit: int = 4
