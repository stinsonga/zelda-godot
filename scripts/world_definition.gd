class_name WorldDefinition
extends Resource

@export var id: StringName
@export var items: Array[Resource] = []
@export var start_room: StringName
@export var rooms: Array[Resource] = []
@export var visual_theme: Resource

@export var loot_tables: Dictionary[StringName, Resource] = {}
