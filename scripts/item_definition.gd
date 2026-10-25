class_name ItemDefinition
extends Resource
## Inventory item. Effects follow Z_01 TakeItem: unique items set their slot,
## graded items only replace a lower grade, counted items add up to a limit.
@export var id: StringName
@export var title: String
## "level" items (map, compass, triforce) set a flag for the current dungeon level.
@export_enum("unique", "grade", "count", "heart_container", "rupees", "health", "level") var effect: String = "unique"
## Items sharing a slot replace or add to each other, as the original slot table does.
@export var slot: StringName
@export var value: int = 1
## Count cap. Bombs use GameState.max_bombs instead.
@export var limit: int = 255
## Selectable for the B button.
@export var usable: bool = false
## Sprite name in the visual theme; empty uses the ID.
@export var sprite: StringName

func sprite_name() -> StringName:
	return sprite if not sprite.is_empty() else id

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty(): errors.append("Item ID is empty")
	if effect in ["unique", "grade", "count", "level"] and slot.is_empty(): errors.append("Item " + String(id) + " needs a slot")
	if value < 0 or limit < 1: errors.append("Item " + String(id) + " has an invalid value or limit")
	return errors
