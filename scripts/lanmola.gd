class_name LanmolaGroup
extends "res://scripts/moldorm.gd"
## Z_04 UpdateLamnola: every segment moves at the group's speed (type - $39: 1 or
## 2 pixels a frame) in its own direction; segments without one wait. At every
## 8-pixel point the head pulls directions down its body, tail first. At every
## 16-pixel square it picks a new, never reversing, direction. Segment loss and
## kill history are Moldorm's: the tail dies in place of the hit segment.
var speed := 1

## Directions are bits as in the original: right 1, left 2, down 4, up 8.
const BITS := {Vector2i.RIGHT: 1, Vector2i.LEFT: 2, Vector2i.DOWN: 4, Vector2i.UP: 8}

static func from_bit(bit: int) -> Vector2i:
	for direction in BITS:
		if BITS[direction] == bit: return direction
	return Vector2i.ZERO

## Lanmola segments do not share Moldorm's turn timers.
func update(context: Dictionary) -> void:
	var now: int = context.get("frame", frame + 1)
	if now == frame: return
	frame = now
	var base = owner.get_ref()
	if base == null or base.health <= 0: return
	var living := 0
	for chain in chains:
		for weak_part in chain:
			var part = weak_part.get_ref()
			if part != null and part.health > 0: living += 1
	if living == 0:
		base.health = 0
		base.death_remaining = 0

func tick(actor: RefCounted, context: Dictionary) -> void:
	update(context)
	actor.shove_remaining = 0
	if actor.definition.behavior == "moldorm" or actor.health <= 0 or actor.facing == Vector2i.ZERO: return
	actor.subposition += actor.facing * speed * 256
	if actor.family.moldorm_is_head: steer(actor, context)

func steer(head: RefCounted, context: Dictionary) -> void:
	var at: Vector2i = head.position()
	if at.x % 8 != 0 or (at.y + 64 + 3) % 8 != 0: return
	# Lamnola_UpdateHead: copy each segment's direction from the one ahead, tail first.
	var chain: Array = chains[head.family.moldorm_chain]
	for i in range(chain.size() - 1):
		var part = chain[i].get_ref()
		var ahead = chain[i + 1].get_ref()
		if part != null and ahead != null and part.health > 0: part.facing = ahead.facing
	if at.x % 16 != 0 or (at.y + 64 + 3) % 16 != 0: return
	var bit: int = BITS.get(head.facing, 8)
	var opposite: int = ((bit >> 1) & 5) | ((bit << 1) & 0x0A)
	var viable: int = opposite ^ 0x0F
	var choice := bit
	if head.source_random < 0x80:
		# Toward Link: sideways only when that way is allowed and Link faces it too.
		var player: Vector2i = context.get("player", at)
		var across := 1 if player.x >= at.x else 2
		var along := 4 if player.y >= at.y else 8
		var link_facing: int = BITS.get(context.get("player_facing", Vector2i.ZERO), 0)
		choice = across if across & viable and across & link_facing else along
	elif head.source_next_random < 0x80:
		var second: bool = head.source_next_random < 0x40
		choice = bit
		while true:
			choice = choice >> 1 if choice > 1 else 8
			if choice & viable == 0: continue
			if second:
				second = false
				continue
			break
	var probe: Callable = context.get("probe", Callable())
	for attempt in range(8):
		if choice & viable and (not probe.is_valid() or probe.call(at, from_bit(choice))): break
		# Blocked: rotate to the next direction that is not the way it came.
		choice = choice >> 1 if choice > 1 else 8
	head.facing = from_bit(choice)
