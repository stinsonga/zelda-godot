class_name CaveDefinition
extends Resource
## A cave resident. Flags mirror Z_01 InitCave's CaveFlags byte, so original
## caves import exactly and custom caves can mix behaviors.
@export var id: StringName
@export var person_sprite: StringName = &"old_man"
## A non-breaking space is shown without taking typing time, like tile $25.
@export_multiline var text: String = ""
## Exactly three slots; a null entry is empty.
@export var wares: Array[Resource] = [null, null, null]
@export var choose: bool = false
@export var pay: bool = false
@export var show_items: bool = false
@export var show_prices: bool = false
@export var negative_prices: bool = false
@export var hint: bool = false
@export var money_game: bool = false
## Minimum heart containers before a gift can be taken; 0 disables.
@export var heart_requirement: int = 0
## Taken state survives leaving: gifts, letters, door charges, secret money.
@export var remember: bool = false
@export var door_charge: int = 0
## Touching the middle ware awards its price instead of charging it.
@export var gift_money: bool = false
## The resident only does business after the letter is shown.
@export var requires_letter: bool = false

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty(): errors.append("Cave ID is empty")
	if wares.size() != 3: errors.append("Cave " + String(id) + " needs exactly three ware slots")
	for ware in wares:
		if ware != null and (ware.price < 0 or ware.price > 255): errors.append("Cave " + String(id) + " has an invalid price")
	if (hint or money_game or gift_money) and not choose: errors.append("Cave " + String(id) + " hint and money behaviors require choosing")
	if heart_requirement < 0 or door_charge < 0: errors.append("Cave " + String(id) + " has a negative requirement")
	return errors
