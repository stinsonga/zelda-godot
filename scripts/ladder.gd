class_name LadderCrossing
extends RefCounted
## Z_07 Link_EndMoveAndAnimate and Z_05 CheckLadder. The logical anchor
## is three pixels above the deployed sprite, matching Link's foot alignment.
var active := false
var anchor := Vector2i.ZERO
var direction := Vector2i.ZERO
var stepped_on := false

func reset() -> void:
	active = false
	stepped_on = false

func distance(at: Vector2i) -> int:
	return absi(at.x - anchor.x) if direction.x != 0 else absi(at.y - anchor.y)

func update(at: Vector2i) -> void:
	if not active: return
	var aligned := at.y == anchor.y if direction.x != 0 else at.x == anchor.x
	if not aligned or distance(at) > 16 or (stepped_on and distance(at) == 16):
		reset()
	elif distance(at) < 16:
		stepped_on = true

func constrain(at: Vector2i, wanted: Vector2i) -> Vector2i:
	update(at)
	if not active or wanted == Vector2i.ZERO: return wanted
	if (wanted.x * direction.x + wanted.y * direction.y) != 0: return wanted
	# At the starting shore Link can turn away without stepping on the ladder.
	if not stepped_on and distance(at) == 16:
		reset()
		return wanted
	return Vector2i.ZERO

func deploy(at: Vector2i, facing: Vector2i) -> void:
	active = true
	direction = facing
	anchor = at + facing * (8 if facing == Vector2i.UP else 16)
	stepped_on = false

func allows(at: Vector2i, moving: Vector2i, ordinary: Callable) -> bool:
	update(at)
	if not active: return ordinary.call(at, moving)
	if (moving.x * direction.x + moving.y * direction.y) == 0: return false
	# The source permits approach/retreat freely; at the center it checks
	# the far shore. Upward crossings probe an extra eight pixels ahead.
	if at != anchor or moving == -direction: return true
	return ordinary.call(at + (Vector2i(0, -8) if direction == Vector2i.UP else Vector2i.ZERO), moving)
