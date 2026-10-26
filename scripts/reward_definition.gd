class_name RewardDefinition
extends Resource

@export var id: StringName
## "item" hands over an ItemDefinition, as a dropped bomb gives bombs.
@export_enum("health", "rupees", "item", "clock") var effect: String = "health"
@export var item: Resource
@export var amount: int = 2
@export var sprite: StringName = &"heart"
@export var fallback_color: Color = Color("ed6060")

## Drops remain for $FF half-rate ticks and cannot be picked up for 32 ticks.
@export var lifetime_ticks: int = 510
@export var pickup_delay_ticks: int = 32
@export var frame_ticks: int = 8
@export var pickup_cue: StringName
@export var appearance_cue: StringName
## Fairy flight (Z_04 SetUpFairyObject / ControlFairyFlight).
@export var flying: bool = false
@export var flight_initial_speed: int = 127
@export var flight_max_speed: int = 160
@export var flight_turn_count: int = 6
@export var flight_turn_ticks: int = 16

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty(): errors.append("Reward ID is empty")
	if effect not in ["health", "rupees", "item", "clock"]: errors.append("Unknown reward effect")
	if effect == "item" and item == null: errors.append("Item reward needs an item")
	if amount < 0 or lifetime_ticks < 1 or pickup_delay_ticks < 0 or frame_ticks < 1: errors.append("Invalid reward amount or timing")
	if flight_initial_speed < 0 or flight_initial_speed > 255 or flight_max_speed < 32 or flight_max_speed > 224 or flight_turn_count < 1 or flight_turn_ticks < 1: errors.append("Invalid reward flight settings")
	return errors
