class_name MoldormGroup
extends RefCounted
## Object slots are represented by stable actors; weak links allow room cleanup.
var owner: WeakRef
var chains: Array[Array] = []
var timers: Array[int] = []
var turns: Array[int] = []
var chase: Array[bool] = []
var bounce: Array[Vector2i] = []
var frame := -1
var death_cues := 0

func setup(actor: RefCounted) -> void:
	owner=weakref(actor)

func add_chain(parts: Array[RefCounted], direction: Vector2i) -> void:
	var chain: Array=[]
	for part in parts: chain.append(weakref(part))
	chains.append(chain)
	timers.append(0)
	turns.append(1)
	chase.append(true)
	bounce.append(Vector2i.ZERO)
	parts.back().facing=direction
	parts.back().family.moldorm_old_direction=direction

func propagate(index: int, head: RefCounted) -> void:
	if bounce[index] != Vector2i.ZERO:
		head.facing=bounce[index]
		bounce[index]=Vector2i.ZERO
	var chain: Array=chains[index]
	# Low-to-high copy preserves each higher segment's previous interval direction.
	for i in range(chain.size()-1):
		var part=chain[i].get_ref()
		var ahead=chain[i+1].get_ref()
		if part==null or ahead==null:continue
		part.family.moldorm_old_direction=ahead.family.moldorm_old_direction
		part.facing=part.family.moldorm_old_direction
	head.family.moldorm_old_direction=head.facing

func update(context: Dictionary) -> void:
	var now: int=context.get("frame",frame+1)
	if now==frame:return
	frame=now
	var base=owner.get_ref()
	if base==null or base.health<=0:return
	var living:=0
	for index in range(chains.size()):
		var chain: Array=chains[index]
		for weak_part in chain:
			var part=weak_part.get_ref()
			if part!=null and part.health>0:living+=1
		var head=chain.back().get_ref()
		if head==null or head.health<=0:continue
		timers[index]=maxi(0,timers[index]-1)
		if timers[index]>0:continue
		turns[index]-=1
		var new_state: bool=turns[index]<=0
		if new_state:
			var rng: RefCounted=context.get("rng")
			var random_byte: int=rng.at(head.slot) if rng!=null else head.source_random
			chase[index]=random_byte>=64
			turns[index]=8
		else:
			if chase[index]:
				head.facing=head.family.turn_toward(head.facing,head.position(),context.get("chase_target",head.position()))
			else:
				var rng: RefCounted=context.get("rng")
				var value: int=rng.at(head.slot+1) if rng!=null else head.source_next_random
				var offset:=0 if value>=160 else 1 if value>=80 else -1
				head.facing=OverworldEnemy.DIRS[posmod(OverworldEnemy.DIRS.find(head.facing)+offset,8)]
		timers[index]=base.definition.boss_turn_ticks
		# On initial state selection, delay the first direction shift until a turn.
		if new_state and chain.size()>1:
			var behind=chain[chain.size()-2].get_ref()
			if behind!=null and behind.facing==Vector2i.ZERO:continue
		propagate(index,head)
	if living==0:
		base.health=0
		base.death_remaining=0

func tick(actor: RefCounted, context: Dictionary) -> void:
	update(context)
	actor.shove_remaining=0
	if actor.definition.behavior=="moldorm" or actor.health<=0 or actor.facing==Vector2i.ZERO:return
	actor.family.flight_fraction+=actor.definition.speed_subpixels
	if actor.family.flight_fraction<256:return
	var distance: int=actor.family.flight_fraction/256
	actor.family.flight_fraction%=256
	actor.subposition+=actor.facing*distance*256
	actor.family.distance+=distance
	if actor.family.moldorm_is_head:
		var bounds: Rect2i=context.get("bounds",Rect2i(33,30,175,95))
		var at: Vector2i=actor.position()
		if (at.x<bounds.position.x and actor.facing.x<0) or (at.x>=bounds.end.x and actor.facing.x>0) or (at.y<bounds.position.y and actor.facing.y<0) or (at.y>=bounds.end.y and actor.facing.y>0):
			bounce[actor.family.moldorm_chain]=-actor.facing

func lose_segment(actor: RefCounted) -> void:
	var chain: Array=chains[actor.family.moldorm_chain]
	var tail: RefCounted
	for weak_part in chain:
		var part=weak_part.get_ref()
		if part!=null and (part.health>0 or part==actor):tail=part;break
	if tail==null:return
	actor.shove_remaining=0
	actor.invulnerability=0
	if tail!=actor:
		tail.subposition=actor.subposition
		tail.health=0
		tail.death_remaining=19
		tail.invulnerability=actor.invulnerability
		var base=owner.get_ref()
		actor.health=base.definition.moldorm_segment_reset_health if base!=null else 2
		actor.death_remaining=0
		death_cues+=1

func resolved_kills() -> int:
	var count:=0
	for chain in chains:
		for weak_part in chain:
			var part=weak_part.get_ref()
			if part==null or (part.health<=0 and part.death_remaining==0):count+=1
	return count
