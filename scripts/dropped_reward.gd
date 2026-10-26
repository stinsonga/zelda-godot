class_name DroppedReward
extends RefCounted

const PICKUP_DELAY := 32
const LIFETIME := 510
var definition: Resource
var position := Vector2i.ZERO
## Keep the defeated monster slot for the original Random+1,X flight stream.
var source_slot := 1
var age := 0
var collected := false

func available() -> bool:
	return not collected and age >= definition.pickup_delay_ticks and age < definition.lifetime_ticks

func touches(at: Vector2i) -> bool:
	var delta := (at + Vector2i(0, 3) - position).abs()
	return delta.x < 9 and delta.y < 9

func take(state: RefCounted) -> void:
	if not available():
		return
	if definition.effect == "health":
		state.health_units = mini(state.max_health * state.HEALTH_UNITS, state.health_units + definition.amount * state.HEALTH_UNITS)
	elif definition.effect == "rupees":
		state.rupees = mini(255, state.rupees + definition.amount)
	elif definition.effect == "clock":
		state.clock_active = true
	elif definition.effect == "item" and definition.item != null:
		state.take_item(definition.item)
	collected = true

const DIRECTIONS := [Vector2i.UP, Vector2i(1,-1), Vector2i.RIGHT, Vector2i(1,1), Vector2i.DOWN, Vector2i(-1,1), Vector2i.LEFT, Vector2i(-1,-1)]
var initialized := false
var speed := 127
var fraction := 0
var direction := 0
var flight_state := 0
var turns := 0
var turn_timer := 0

func pickup_sound() -> StringName:
	if not definition.pickup_cue.is_empty(): return definition.pickup_cue
	return &"heart" if definition.effect == "health" else &"rupee"

func tick(bounds: Rect2i, random_byte: int) -> void:
	age += 1
	if not definition.flying: return
	if not initialized:
		initialized = true
		speed = definition.flight_initial_speed
	if turn_timer > 0: turn_timer -= 1
	match flight_state:
		0:
			speed = (speed + 1) & 255
			if (speed & 224) >= definition.flight_max_speed: flight_state = 1
		1:
			flight_state = 3
			turns = definition.flight_turn_count
		3:
			if turn_timer == 0:
				turns -= 1
				if turns == 0: flight_state = 1
				else:
					turn_timer = definition.flight_turn_ticks
					var offset := 0 if random_byte >= 160 else 1 if random_byte >= 80 else -1
					direction = posmod(direction + offset, 8)
	fraction += speed & 224
	if fraction >= 256:
		fraction -= 256
		position += DIRECTIONS[direction]
		var moving: Vector2i = DIRECTIONS[direction]
		if (position.x < bounds.position.x and moving.x < 0) or (position.x >= bounds.end.x and moving.x > 0) or (position.y < bounds.position.y and moving.y < 0) or (position.y >= bounds.end.y and moving.y > 0):
			direction = (direction + 4) % 8
