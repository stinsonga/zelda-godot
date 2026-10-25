class_name EnemyDefinition
extends Resource

@export var loot_table: Resource = preload("res://content/enemies/default_loot.tres")
@export var id: StringName
@export var title: String
@export var health: int = 1
## One unit of contact damage is half a heart. Speeds are 1/256 pixel per tick.
@export var contact_damage: int = 1
@export var speed_subpixels: int = 128
@export var sprite: StringName = &"red_octorok"
@export var tint: Color = Color.WHITE
@export var fallback_color: Color = Color("d94b3d")
@export_range(0, 255) var turn_chance: int = 112
@export var shoot_cooldown: int = 128
@export var shoot_windup: int = 32
@export var projectile_speed_subpixels: int = 768
@export var spawn_ticks: int = 32
