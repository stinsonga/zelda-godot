class_name ManhandlaGroup
extends RefCounted
## Weak links let a room unload without keeping a cyclic actor graph alive.
var body: WeakRef
var hands: Array[WeakRef] = []
var center := Vector2i.ZERO
var direction := Vector2i.UP
var frame := -1
var timer := 0
var speed := 128
var fraction := 0
var move_distance := 0
var dead_hands := 0
var bounce := false

func setup(actor: RefCounted) -> void:
	body = weakref(actor)
	center = actor.position()
	direction = OverworldEnemy.DIRS[actor.source_random & 7]
	speed = actor.definition.boss_initial_speed

func update(context: Dictionary) -> int:
	var now: int = context.get("frame",frame+1)
	if now == frame: return move_distance
	frame = now
	var actor = body.get_ref()
	if actor == null or actor.health <= 0: return 0
	var dead := 0
	for hand in hands:
		var part = hand.get_ref()
		if part == null or part.health <= 0: dead += 1
	if dead > dead_hands:
		speed += actor.definition.boss_lost_hand_speed # Source uses one "segment just died" flag per update.
		dead_hands = dead
	if not hands.is_empty() and dead == hands.size():
		var cry: StringName = actor.death_sound()
		if not cry.is_empty(): actor.cues.append(cry)
		actor.health = 0
		actor.death_remaining = 19
		return 0
	if bounce:
		direction = -direction
		bounce = false
	timer = maxi(0,timer-1)
	if timer == 0:
		timer = actor.definition.boss_turn_ticks
		if actor.source_random >= 128:
			direction = actor.family.turn_toward(direction,center,context.get("chase_target",context.get("player",center)))
		else:
			var offset := 0 if actor.source_next_random >= 160 else 1 if actor.source_next_random >= 80 else -1
			direction = OverworldEnemy.DIRS[posmod(OverworldEnemy.DIRS.find(direction)+offset,8)]
	fraction += speed & 224
	var distance := (speed >> 8) + (fraction >> 8)
	fraction &= 255
	move_distance = distance
	center += direction * distance
	return distance

func tick(actor: RefCounted, context: Dictionary) -> void:
	var step := update(context)
	if actor.definition.boss_hand != null:
		actor.subposition = center * 256
	else:
		actor.subposition = (center + actor.family.manhandla_offset) * 256
	actor.facing = direction
	actor.shove_remaining = 0
	var bounds: Rect2i = context.get("bounds",Rect2i(33,30,175,95))
	var at: Vector2i = actor.position()
	if (at.x < bounds.position.x and direction.x < 0) or (at.x >= bounds.end.x and direction.x > 0) or (at.y < bounds.position.y and direction.y < 0) or (at.y >= bounds.end.y and direction.y > 0): bounce = true
	# Every hand animates independently; only closing mouths can emit fireballs.
	var old: int = actor.family.manhandla_animation
	actor.family.manhandla_animation = (old + (actor.source_next_random & 3) + step) & 255
	if actor.definition.boss_hand == null and actor.health > 0 and (old & 16) != 0 and (actor.family.manhandla_animation & 16) == 0 and actor.source_next_random >= 224:
		actor.pending_shots.append({"position":actor.position(),"spread":0})
