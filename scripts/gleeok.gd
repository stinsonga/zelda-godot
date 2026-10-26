class_name GleeokGroup
extends RefCounted
var body: WeakRef
var heads: Array[WeakRef] = []
var necks: Array[PackedVector2Array] = []
var frame := -1
var animation := 0
var animation_timer := 0
var writhing := 0
var head_health := 10
var hit_timer := 0

func setup(actor: RefCounted) -> void:
	body = weakref(actor)
	head_health = actor.definition.gleeok_head.health

func add_head(actor: RefCounted, index: int, base: Vector2i, delay: int) -> void:
	heads.append(weakref(actor))
	var points := PackedVector2Array()
	for segment in range(5): points.append(Vector2(base+Vector2i(0,segment*5)))
	necks.append(points)
	actor.family.gleeok_index = index
	actor.family.gleeok_delay = index*delay
	actor.family.gleeok_step = Vector2i(-1,1) if index%2 == 0 else Vector2i(1,-1)
	actor.subposition = Vector2i(points[4])*256

func update(context: Dictionary) -> void:
	var now: int = context.get("frame",frame+1)
	if now == frame: return
	frame = now
	hit_timer = maxi(0,hit_timer-1)
	if animation_timer > 0: animation_timer -= 1
	else:
		animation_timer = 6 if writhing > 0 else 16
		writhing = maxi(0,writhing-1)
		animation = (animation+1)&3
	var alive := 0
	for weak_head in heads:
		var head = weak_head.get_ref()
		if head != null and head.health > 0 and not head.family.gleeok_detached: alive += 1
	if alive == 0 and not heads.is_empty():
		var base = body.get_ref()
		if base != null and base.health > 0:
			var cry: StringName = base.death_sound()
			if not cry.is_empty(): base.cues.append(cry)
			base.health = 0
			base.death_remaining = 19
		for weak_head in heads:
			var head = weak_head.get_ref()
			if head != null:
				head.health = 0
				head.death_remaining = 0
				head.drop_resolved = true
		return
	# The source updates one selected neck each frame, including initial delays.
	var index := frame & 3
	if index >= heads.size(): return
	var actor = heads[index].get_ref()
	if actor == null or actor.family.gleeok_detached or actor.health <= 0: return
	move_neck(index, int(context.get("random",0)))
	if actor.family.gleeok_delay > 0: actor.family.gleeok_delay -= 1
	else:
		var points: PackedVector2Array = necks[index]
		points[4] += Vector2(actor.family.gleeok_step)
		necks[index] = points
		actor.family.gleeok_direction_timer += 1
		if actor.family.gleeok_direction_timer == 4:
			actor.family.gleeok_direction_timer = 0
			actor.family.gleeok_horizontal = (actor.family.gleeok_horizontal+1)%12
			actor.family.gleeok_vertical = (actor.family.gleeok_vertical+1)%6
			if actor.family.gleeok_horizontal == 0: actor.family.gleeok_step.x *= -1
			if actor.family.gleeok_vertical == 0: actor.family.gleeok_step.y *= -1
	actor.subposition = Vector2i(necks[index][4])*256
	if actor.definition.shooting_enabled and int(context.get("head_random",255)) < 32:
		actor.pending_shots.append({"position":actor.position(),"spread":0})

func move_neck(index: int, random_byte: int) -> void:
	var p: PackedVector2Array = necks[index]
	var quarter := Vector2i(int(p[4].x-p[0].x)/4,absi(int(p[4].y-p[0].y))/4)
	var primary := Vector2i(mini(absi(quarter.x),4),mini(quarter.y,4))
	var secondary := primary+Vector2i(4,4)
	var tertiary := Vector2i(mini(secondary.x+4,11),mini(secondary.y+4,11))
	for i in range(4):
		for axis in range(2):
			if absf(p[i][axis]-p[i+1][axis]) >= tertiary[axis]: p[i+1][axis] += 2 if p[i+1][axis] < p[i][axis] else -2
	for i in range(1,4):
		# Preserve the original SBC same-X quirk: horizontal gap is always zero.
		var mode := int(0 >= primary.x)+int(0 >= secondary.x)
		var dy := absf(p[i+1].y-p[i].y)
		mode += 3*int(dy >= primary.y)+3*int(dy >= secondary.y)
		if mode == 0:
			var axis := 0 if random_byte < 128 else 1
			p[i][axis] += 2 if p[i][axis] >= p[i+1][axis] and (axis==0 or p[i][axis]!=p[i+1][axis]) else -2
		elif mode in [2,5,6,7,8]:
			var axis := 0 if mode in [2,5] or (mode==8 and random_byte<128) else 1
			p[i][axis] += 2 if p[i][axis] < p[i+1][axis] or (axis==1 and p[i][axis]==p[i+1][axis]) else -2
	for i in range(3,0,-1):
		var reference := p[0].x+quarter.x*i
		p[i].x += 1 if p[i].x <= reference else -1
	for i in [3,2]:
		if p[i].y < p[i-1].y and p[i].y < p[i+1].y: p[i].y += 1
		elif p[i].y >= p[i-1].y and p[i].y >= p[i+1].y: p[i].y -= 1
	necks[index] = p

func head_hit(actor: RefCounted) -> void:
	writhing = 6
	animation_timer = 6
	if actor.health <= 0:
		detach(actor)
		var base = body.get_ref()
		head_health = base.definition.gleeok_next_head_health if base != null else 6
		hit_timer = 0
	else:
		head_health = actor.health
		hit_timer = 32
	for weak_head in heads:
		var head = weak_head.get_ref()
		if head != null and not head.family.gleeok_detached:
			head.health = head_health
			head.invulnerability = 0

func detach(actor: RefCounted) -> void:
	actor.family.gleeok_detached = true
	actor.health = actor.definition.health
	actor.death_remaining = 0
	actor.invulnerability = 0
	actor.shove_remaining = 0
	actor.family.phase = 0
	actor.family.flight_speed = actor.definition.flight_initial_speed
	actor.family.timer = 0
	actor.family.initialized = true
	actor.facing = OverworldEnemy.DIRS[actor.source_random & 7]
	writhing = 6
	animation_timer = 6

func tick(actor: RefCounted, context: Dictionary) -> void:
	update(context)
	actor.shove_remaining = 0
	if actor.definition.behavior == "gleeok": return
	if actor.health <= 0: return
	if actor.family.gleeok_detached:
		actor.family.tick_flight(actor,context.get("player",actor.position()))
		if actor.definition.shooting_enabled and (actor.family.distance&1)==0 and actor.source_next_random < 32:
			actor.pending_shots.append({"position":actor.position(),"spread":0})
	else:
		actor.subposition = Vector2i(necks[actor.family.gleeok_index][4])*256
