class_name DroppedReward
extends RefCounted

const PICKUP_DELAY := 32
const LIFETIME := 510
var definition: Resource
var position := Vector2i.ZERO
var age := 0
var collected := false

func available() -> bool:
	return not collected and age >= PICKUP_DELAY and age < LIFETIME

func touches(at: Vector2i) -> bool:
	var delta := (at + Vector2i(0, 3) - position).abs()
	return delta.x < 9 and delta.y < 9

func take(state: RefCounted) -> void:
	if not available():
		return
	if definition.effect == "health":
		state.health = mini(state.max_health, state.health + definition.amount)
	elif definition.effect == "rupees":
		state.rupees = mini(255, state.rupees + definition.amount)
	elif definition.effect == "item" and definition.item != null:
		state.take_item(definition.item)
	collected = true
