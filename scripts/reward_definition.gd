class_name RewardDefinition
extends Resource

@export var id: StringName
## "item" hands over an ItemDefinition, as a dropped bomb gives bombs.
@export_enum("health", "rupees", "item") var effect: String = "health"
@export var item: Resource
@export var amount: int = 2
@export var sprite: StringName = &"heart"
@export var fallback_color: Color = Color("ed6060")
