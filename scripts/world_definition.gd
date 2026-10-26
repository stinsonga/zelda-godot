class_name WorldDefinition
extends Resource

@export var id: StringName
@export var items: Array[Resource] = []
@export var start_room: StringName
@export var rooms: Array[Resource] = []
@export var visual_theme: Resource
@export var audio_bank: Resource
## Original submenu layout (SubmenuLayout); without it the menu draws placeholders.
@export var submenu: Resource

@export var loot_tables: Dictionary[StringName, Resource] = {}

@export var spawn_lists: Array[PackedByteArray] = []
@export var projectile_limit: int = 4
## Whirlwind stops per level 1-8: {"room": overworld room ID, "y": TeleportYs height}.
@export var whirlwinds: Array = []
## Renamed room IDs and collected keys, applied when loading older saves.
@export var legacy_ids: Dictionary[String, String] = {}
