class_name RewardDefinition
extends Resource

@export var id: StringName
@export_enum("health", "rupees") var effect: String = "health"
@export var amount: int = 2
@export var sprite: StringName = &"heart"
@export var fallback_color: Color = Color("ed6060")
