class_name CombatSimulation
extends RefCounted

const Beam = preload("res://scripts/sword_beam.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Reward = preload("res://scripts/dropped_reward.gd")
const Rock = preload("res://scripts/rock_projectile.gd")
var source_random = preload("res://scripts/nes_random.gd").new()
var spawn_lists: Array[PackedByteArray] = []
var projectile_limit := 4
var chase_target := Vector2i.ZERO
var chase_other := false
var chase_timer := 0
var frame_clock := 0
var edge_timer := 0
var ambush_timer := 50
var edge_cursor := 0x40
var encounter_room: Resource
var encounter_total := 0
var encounter_kills := 0
var base_kills := 0
var beam: RefCounted
var rewards: Array[RefCounted] = []
var enemies: Array[RefCounted] = []
var rocks: Array[RefCounted] = []
var player_invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO
## Z_05 ObjectRoomBoundsOW and ObjectRoomBoundsUW in play-area pixels.
const BOUNDS_OVERWORLD := Rect2i(17, 14, 207, 127)
const BOUNDS_UNDERWORLD := Rect2i(33, 30, 175, 95)
var bounds := BOUNDS_OVERWORLD
var wallmaster_cooldown := 0
## Set when Ganon's ashes release the room item there (Z_04 Ganon_ActivateRoomItem).
var room_item_position = null
## Zelda's rescue finished; the ending (mode $13) is the front end's job.
var ending := false
## Z_04 Statue_ObjFireballTimer per fireball index, and PersonFireballsEnabled.
var statue_timers: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var person_provoked := false
const STATUE_START_TIMES := [0x50, 0x80, 0xF0, 0x60]
## SetUpCommonCaveObjects: residents stand at ($78, $80).
const PERSON_POSITION := Vector2i(0x78, 0x80 - 64)
## Z_07 MoveAndDrawRoomItem: a Like Like, Stalfos, or Gibdo in slot 1 carries the room item.
const CARRIERS := [0x17, 0x2A, 0x30]
## Help drops: five rupees ($0F), a bomb ($00), or a fairy ($23).
const FIVE_RUPEE_DROP = preload("res://content/items/five_rupees.tres")
const BOMB_DROP = preload("res://content/items/bomb_drop.tres")
const FAIRY_DROP = preload("res://content/items/fairy.tres")

func enter_room(room: Resource, state: RefCounted, restoring: bool = false, entry_position: Vector2i = Vector2i.ZERO, entry_direction: Vector2i = Vector2i.UP) -> void:
	beam = null
	enemies.clear()
	rocks.clear()
	rewards.clear()
	shove_remaining = 0
	ambush_timer = 50
	encounter_room = room
	bounds = room.monster_bounds if room.monster_bounds.has_area() else BOUNDS_UNDERWORLD if room.dungeon_level > 0 else BOUNDS_OVERWORLD
	encounter_kills = 0
	base_kills = 0
	var count: int = room.enemies.size()
	if room.enemy_persistence == "overworld":
		count = state.prepare_overworld_room(room, restoring)
		base_kills = int(state.room_records[String(room.id)].kills)
	for i in range(count):
		var spawn: Resource = room.enemies[i]
		if room.enemy_persistence == "permanent" and state.defeated.has(String(room.id) + "/" + String(spawn.id)): continue
		var actor = Actor.new()
		actor.setup(spawn)
		actor.slot = i + 1
		enemies.append(actor)
	encounter_total = enemies.size()
	if room.source_edge_spawns:
		for actor in enemies:
			if actor.definition.behavior != "native":
				actor.waiting_spawn = true
				actor.spawn_remaining = 0
	elif room.source_spawn_lists:
		assign_source_spawns(room, state, entry_position, entry_direction)
	setup_moldorms()
	setup_gleeoks()
	setup_multipart_bosses()
	setup_patras()
	room_item_position = null
	ending = false
	statue_timers = PackedInt32Array([0, 0, 0, 0])
	person_provoked = false
	for actor in enemies:
		if actor.definition.behavior == "ganon": actor.family.ganon = preload("res://scripts/ganon.gd").new()
	encounter_total = enemies.filter(func(a: RefCounted) -> bool: return a.definition.counts_for_persistence).size()

func setup_moldorms() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior!="moldorm":continue
		var lanmola: bool=actor.definition.chain_style=="lanmola"
		var group=preload("res://scripts/lanmola.gd").new() if lanmola else preload("res://scripts/moldorm.gd").new()
		if lanmola: group.speed=actor.definition.chain_speed
		group.setup(actor)
		actor.family.moldorm=group
		for chain_index in range(actor.definition.moldorm_chain_count):
			var parts: Array[RefCounted]=[]
			for i in range(actor.definition.moldorm_segments_per_chain):
				var spawn=preload("res://scripts/enemy_spawn.gd").new()
				spawn.id=StringName(String(actor.id)+"_chain_"+str(chain_index)+"_"+str(i))
				spawn.enemy=actor.definition.moldorm_segment.duplicate()
				var head: bool=i==actor.definition.moldorm_segments_per_chain-1
				spawn.enemy.advances_kill_cycle=head
				spawn.enemy.drops_rewards=head
				if head:spawn.enemy.id=actor.definition.id
				spawn.position=actor.position()
				spawn.facing=Vector2i.ZERO
				spawn.spawn_ticks=0
				var part=Actor.new()
				part.setup(spawn)
				part.spawn_remaining=0
				part.slot=chain_index*actor.definition.moldorm_segments_per_chain+i+1
				part.family.moldorm=group
				part.family.moldorm_chain=chain_index
				part.family.moldorm_is_head=head
				enemies.append(part)
				parts.append(part)
			# InitLamnola: both heads start facing up; Moldorm heads pick at random.
			group.add_chain(parts,Vector2i.UP if lanmola else OverworldEnemy.DIRS[source_random.at(parts.back().slot)&7])
		enemies.erase(actor)
		enemies.append(actor)

func setup_gleeoks() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior != "gleeok": continue
		var group = preload("res://scripts/gleeok.gd").new()
		group.setup(actor)
		actor.family.gleeok = group
		for i in range(actor.definition.gleeok_neck_count):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id)+"_neck_"+str(i))
			spawn.enemy = actor.definition.gleeok_head
			spawn.spawn_ticks = 0
			var head = Actor.new()
			head.setup(spawn)
			head.spawn_remaining = 0
			head.slot = i+7
			head.family.gleeok = group
			group.add_head(head,i,actor.hit_position(),actor.definition.gleeok_head_delay)
			enemies.append(head)
		enemies.erase(actor)
		enemies.append(actor)

func setup_multipart_bosses() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior != "manhandla" or actor.definition.boss_hand == null: continue
		var group = preload("res://scripts/manhandla.gd").new()
		actor.source_random = source_random.at(actor.slot)
		group.setup(actor)
		actor.family.manhandla = group
		for i in range(actor.definition.boss_hand_offsets.size()):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id)+"_hand_"+str(i))
			spawn.enemy = actor.definition.boss_hand
			spawn.position = actor.position()+Vector2i(actor.definition.boss_hand_offsets[i])
			spawn.spawn_ticks = 0
			var hand = Actor.new()
			hand.setup(spawn)
			hand.spawn_remaining = 0
			hand.slot = i+1
			hand.family.manhandla = group
			hand.family.manhandla_offset = Vector2i(actor.definition.boss_hand_offsets[i])
			hand.family.manhandla_index = i
			group.hands.append(weakref(hand))
			enemies.append(hand)
		actor.slot = 5
		# Reverse update order visits the base before its hands, as on the NES.
		enemies.erase(actor)
		enemies.append(actor)

## Z_04 InitPatra fills slots 2-9 with children; the parent keeps slot 1, so
## it updates after them in the reverse loop.
func setup_patras() -> void:
	for actor in enemies.duplicate():
		if actor.definition.behavior != "patra" or actor.definition.patra_child == null: continue
		var group = preload("res://scripts/patra.gd").new()
		group.setup(actor)
		actor.family.patra = group
		actor.slot = 1
		enemies.erase(actor)
		enemies.insert(0, actor)
		for i in range(actor.definition.patra_child_count):
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id)+"_child_"+str(i))
			spawn.enemy = actor.definition.patra_child
			spawn.position = actor.position()
			spawn.spawn_ticks = 0
			var child = Actor.new()
			child.setup(spawn)
			child.spawn_remaining = 0
			child.slot = i+2
			group.add_child(child)
			enemies.insert(1+i, child)

func can_enemy_occupy(world: Node, at: Vector2i) -> bool:
	if at.x < bounds.position.x - 1 or at.x > bounds.end.x or at.y < bounds.position.y - 1 or at.y > bounds.end.y: return false
	for point in [at + Vector2i(2, 8), at + Vector2i(13, 8), at + Vector2i(2, 15), at + Vector2i(13, 15)]:
		if world.is_blocked(point): return false
	return true

func hurt_player(world: Node, damage: int, source: Vector2i) -> bool:
	if world.state.clock_active or player_invulnerability > 0 or world.state.health <= 0: return false
	world.state.take_damage(damage)
	if world.state.health == 0: world.audio.silence()
	world.audio.play(&"player_hurt")
	player_invulnerability = 48
	var delta: Vector2i = world.player.pixel_position() - source
	var relative: Vector2i = world.player.subposition - world.player.grid_origin * 256
	var on_grid: bool = posmod(relative.x, 2048) == 0 and posmod(relative.y, 2048) == 0
	var horizontal: bool = absi(delta.x) >= absi(delta.y) if on_grid else world.player.facing.x != 0
	shove_direction = (Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT) if horizontal else (Vector2i.DOWN if delta.y >= 0 else Vector2i.UP)
	shove_remaining = 32
	world.sword.phase = -1
	world.rod.phase = -1
	return true

func move_shoved_player(world: Node) -> void:
	var before: Vector2i = world.player.pixel_position()
	var facing: Vector2i = world.player.facing
	world.player.facing = shove_direction
	world.player.step(shove_direction, world.can_occupy, world.can_enter_segment, mini(4, shove_remaining) * 256)
	world.player.facing = facing
	var moved: Vector2i = world.player.pixel_position() - before
	if moved == Vector2i.ZERO: shove_remaining = 0
	else: shove_remaining = maxi(0, shove_remaining - absi(moved.x) - absi(moved.y))

func tick(world: Node) -> void:
	if world.state.health <= 0: return
	player_invulnerability = maxi(0, player_invulnerability - 1)
	var launched := false
	if world.sword.phase == 2 and not world.sword.beam_attempted:
		world.sword.beam_attempted = true
		launched = launch_beam(world)
	if world.rod.phase == 2 and not world.rod.beam_attempted:
		world.rod.beam_attempted = true
		launched = launch_magic(world) or launched
	if not launched: tick_beam(world)
	var food_target: Variant=null
	var attracts:bool=world.room.bait_attraction=="enabled"
	if world.room.bait_attraction=="source" and not world.room.enemies.is_empty():
		var template:int=world.room.enemies[0].enemy.nes_type
		attracts=(template>=3 and template<11) or template in [0x12,0x1B,0x1C]
	if attracts:
		for object in world.item_objects:
			if object.active and object.kind=="bait":food_target=object.position;break
	update_chase_target(world.player.pixel_position(),food_target)
	update_edge_spawns(world)
	ambush_timer = maxi(0,ambush_timer-1)
	wallmaster_cooldown = maxi(0, wallmaster_cooldown - 1)
	var context := {"player":world.player.pixel_position(), "player_facing":world.player.facing, "bounds":bounds, "chase_target":chase_target, "rng":source_random, "random":source_random.at(0), "head_random":source_random.at(5),
		"wallmaster_cooldown":wallmaster_cooldown, "player_moving":world.held.size() > 0, "frame":frame_clock,
		"recorder_used":world.recorder_used_here and world.recorder_ticks == 0,
		"ambush_timer":ambush_timer, "active_ambush":enemies.filter(func(a: RefCounted) -> bool: return a.alive() and a.definition.behavior == "burrower" and a.definition.burrow_style == "ambush" and a.family.phase != 0).size(),
		"spawn_allowed":func(at: Vector2i) -> bool: return not world.is_blocked(at+Vector2i(0,11)),
		"blocked":func(at: Vector2i) -> bool: return world.is_blocked(at), "clock":world.state.clock_active}
	# Z_01 Person_CheckCollisions: striking a dungeon resident enables the fires' fireballs.
	if world.room.dungeon_level > 0 and world.cave_session != null and world.cave_session.person_visible() and world.sword.hits(world.player.pixel_position(), PERSON_POSITION):
		person_provoked = true
	var updates: Array = enemies.duplicate()
	updates.reverse()
	for actor in updates:
		actor.source_random = source_random.at(actor.slot)
		actor.source_next_random = source_random.at(actor.slot + 1)
		if actor.targetable() and world.sword.hits(world.player.pixel_position(), actor.hit_position()):
			if actor.receive_hit(world.sword.weapon.damage, world.sword.direction, "sword"):
				world.audio.play(&"enemy_hit")
				if actor.health == 0:
					world.audio.play(&"enemy_die")
					record_permanent_kill(world, actor)
			elif actor.parried_hit:
				world.audio.play(&"parry")
		if actor.targetable() and world.rod.hits(world.player.pixel_position(), actor.hit_position()):
			if actor.receive_hit(world.rod.weapon.damage, world.rod.direction, "rod"):
				world.audio.play(&"enemy_hit")
				if actor.health == 0:
					world.audio.play(&"enemy_die")
					record_permanent_kill(world, actor)
			elif actor.parried_hit: world.audio.play(&"parry")
		var was_alive: bool = actor.health > 0
		var original: bool = actor.definition.behavior != "native"
		var target: Vector2i = chase_target if original else world.player.pixel_position()
		if actor.tick(target, func(at: Vector2i) -> bool: return can_enemy_occupy(world, at),
			func(at: Vector2i, direction: Vector2i) -> bool: return source_can_enter(world, at, direction), rocks.size() < projectile_limit, context):
			if rocks.size() < projectile_limit:
				var rock = Rock.new()
				rock.source_rules = original
				rock.kind = actor.definition.projectile_kind
				rock.damage = actor.definition.projectile_damage
				rock.blockable = actor.definition.projectile_blockable
				if rock.kind == "boomerang":
					rock.owner = actor
					rock.source_rules = false
					actor.shot_out = true
				rock.subposition = actor.subposition if original else (actor.position() + actor.facing * 12) * 256
				rock.direction = actor.facing
				rock.speed_subpixels = actor.definition.projectile_speed_subpixels
				rocks.append(rock)
		if was_alive and actor.health == 0:
			record_permanent_kill(world,actor)
			if actor.definition.behavior == "gleeok": world.audio.play(&"enemy_die")
		if actor.definition.behavior=="moldorm" and actor.family.moldorm!=null and actor.family.moldorm.death_cues>0:
			world.audio.play(&"enemy_die")
			actor.family.moldorm.death_cues=0
		if actor.definition.behavior == "ganon" and actor.family.ganon != null: apply_ganon_cues(world, actor)
		if actor.definition.behavior == "zelda" and actor.family.zelda_state > 0: rescue_zelda(world, actor)
		for shot in actor.pending_shots:
			if rocks.size() >= projectile_limit: break
			var fireball: RefCounted = make_fireball(world, shot.position, shot.spread)
			fireball.damage = actor.definition.projectile_damage
			fireball.magic_blockable = actor.definition.projectile_magic_blockable
			rocks.append(fireball)
		actor.pending_shots.clear()
		if actor.health == 0 and actor.death_remaining == 0 and not actor.drop_resolved:
			actor.drop_resolved = true
			if actor.definition.counts_for_persistence: encounter_kills += 1
			world.state.kill_cycle = (world.state.kill_cycle + 1) % 10 if actor.definition.advances_kill_cycle else world.state.kill_cycle
			var table: Resource = world.loot_tables.get(actor.definition.id, actor.definition.loot_table) if actor.definition.drops_rewards else null
			if original and actor.died_from != "": world.state.note_kill(actor.died_from == "bomb")
			# UpdateDodongo's death leaves a bomb from the fight.
			if actor.definition.behavior == "dodongo":
				world.state.help_drop_count = 10
				world.state.help_drop_bomb = true
			# SetUpDroppedItem: a slot-1 Stalfos or Gibdo may carry the room item, so it drops nothing.
			if original and actor.slot == 1 and actor.definition.nes_type in CARRIERS and actor.definition.nes_type != 0x17: table = null
			if table != null:
				var item: Resource = original_drop(world, table, actor.source_random) if original else table.select(world.state.kill_cycle, actor.rng.randi_range(0, 255))
				if item != null:
					spawn_reward(world, item, actor.position(), actor.slot)
		var reach: Vector2i = actor.collision_size() / 2 + Vector2i.ONE
		var gap: Vector2i = (actor.position() + actor.definition.collision_offset + actor.collision_size() / 2 - world.player.pixel_position() - Vector2i(8, 8)).abs()
		if not world.state.clock_active and not world.raft.active and actor.can_touch_player() and actor.invulnerability == 0 and ((gap.x < reach.x and gap.y < reach.y) if original else actor.hurtbox().intersects(player_box(world))):
			touch_player(world, actor)
	tick_rupee_stash(world)
	tick_statues(world)
	ambush_timer = int(context.ambush_timer)
	wallmaster_cooldown = int(context.wallmaster_cooldown)
	split_zols(world)
	for rock in rocks:
		if rock.kind == "boomerang":
			tick_boomerang(world, rock)
			continue
		if rock.kind == "fireball":
			tick_fireball(world, rock)
			continue
		if rock.source_rules:
			tick_source_rock(world, rock)
			continue
		var remaining: int = rock.speed_subpixels
		while remaining > 0 and rock.alive:
			var amount := mini(256, remaining)
			rock.subposition += rock.direction * amount
			remaining -= amount
			var at: Vector2i = rock.position()
			if at.x < -16 or at.x > 256 or at.y < -16 or at.y > 176:
				rock.alive = false
			elif world.room.is_pixel_solid(at + Vector2i(8, 8)):
				rock.alive = false
			elif not world.state.clock_active and not world.raft.active and rock.hurtbox().intersects(player_box(world)):
				# The basic shield blocks rocks arriving from the facing direction,
				# while Link is free to defend (not using the sword).
				if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
					world.audio.play(&"parry")
					rock.alive = false
				elif hurt_player(world, rock.damage, at):
					rock.alive = false
	rocks = rocks.filter(func(rock: RefCounted) -> bool: return rock.alive)
	for reward in rewards:
		reward.tick(bounds, source_random.at(reward.source_slot + 1))
		if world.state.health > 0 and reward.available():
			var touched: bool = reward.touches(world.player.pixel_position())
			if world.sword.visible():
				touched = touched or reward.touches(world.player.pixel_position() + world.sword.offset())
			if touched:
				reward.take(world.state)
				world.audio.play(reward.pickup_sound())
	rewards = rewards.filter(func(reward: RefCounted) -> bool: return not reward.collected and reward.age < reward.definition.lifetime_ticks)

func spawn_reward(world: Node, definition: Resource, at: Vector2i, source_slot: int = 1) -> RefCounted:
	var reward = Reward.new()
	reward.definition = definition
	reward.source_slot = source_slot
	reward.position = at
	rewards.append(reward)
	if not definition.appearance_cue.is_empty(): world.audio.play(definition.appearance_cue)
	return reward

func apply_ganon_cues(world: Node, actor: RefCounted) -> void:
	var fight: RefCounted = actor.family.ganon
	for cue in fight.cues:
		if cue == &"level_music": world.audio.set_music(world.room.music)
		elif cue in [&"enemy_hit", &"enemy_die", &"item"]: world.audio.play(cue)
	fight.cues.clear()
	if fight.item_released and room_item_position == null: room_item_position = actor.position()

## Z_04 UpdateZelda: the first rescue frame puts Link at ($88, $88) facing left.
func rescue_zelda(world: Node, actor: RefCounted) -> void:
	if actor.family.zelda_state == 1 and actor.family.timer == 0x80:
		world.player.place(Vector2i(0x88, 0x88 - 64))
		world.player.facing = Vector2i.LEFT
		world.audio.play(&"item_fanfare")
	if actor.family.zelda_state == 2 and not ending:
		ending = true
		world.state.flags["zelda_rescued"] = true

## Z_01 UpdateRupeeStash_Full: Link takes a rupee within 9 pixels. Taking one
## counts as taking them all once he leaves (RoomObjCount = 0).
func tick_rupee_stash(world: Node) -> void:
	var at: Vector2i = world.player.pixel_position()
	for actor in enemies:
		if actor.definition.behavior != "rupee_stash" or actor.health <= 0: continue
		var delta: Vector2i = (at - actor.position()).abs()
		if delta.x >= 9 or delta.y >= 9: continue
		world.state.rupees_to_add += 1
		world.audio.play(&"rupee")
		actor.health = 0
		actor.death_remaining = 0
		actor.drop_resolved = true
		encounter_kills = encounter_total

## Z_04 UpdateStatues: each fireball index waits on its own timer; when it runs
## out, random >= $F0 waits 256 more frames, otherwise a start time is chosen and
## a $55 fireball leaves unless Link is within $18 on both axes. A free object
## slot from 6 up is needed. A struck resident's fires replace the room's statues.
func tick_statues(world: Node) -> void:
	var room: Resource = world.room
	if room.dungeon_level == 0: return
	var points: PackedVector2Array = room.provoked_statues if person_provoked else room.statues
	if points.is_empty(): return
	var busy: int = rocks.size() + enemies.filter(func(a: RefCounted) -> bool: return a.alive() and a.slot >= 6).size()
	if busy >= 6: return
	var player: Vector2i = world.player.pixel_position()
	for i in range(points.size() - 1, -1, -1):
		var waited: int = statue_timers[i]
		statue_timers[i] = (waited - 1) & 0xFF
		if waited != 0: continue
		var random_byte: int = source_random.at(i)
		if random_byte >= 0xF0: continue
		statue_timers[i] = STATUE_START_TIMES[random_byte & 3]
		var origin := Vector2i(points[i])
		var delta: Vector2i = (player - (origin - Vector2i(4, 0))).abs()
		if delta.x < 0x18 and delta.y < 0x18: continue
		if rocks.size() >= projectile_limit: continue
		var fireball: RefCounted = make_fireball(world, origin, 0)
		fireball.damage = room.statue_damage
		rocks.append(fireball)

## Z_04 SetUpDroppedItem: the kill-cycle entry of the monster's row, except the
## sixteenth kill since Link was hurt brings a fairy, and a full help counter
## guarantees five rupees or a bomb; otherwise the row's rate may cancel it.
func original_drop(world: Node, table: Resource, roll: int) -> Resource:
	var state: RefCounted = world.state
	var item: Resource = table.entry(state.kill_cycle)
	var helped: bool = state.world_kill_count == 0x10 or state.help_drop_count >= 10
	if state.world_kill_count == 0x10: item = FAIRY_DROP
	elif state.help_drop_count >= 10: item = BOMB_DROP if state.help_drop_bomb else FIVE_RUPEE_DROP
	if helped:
		# @SetHelpItem clears the help counter and bomb flag, not the kill count.
		state.help_drop_count = 0
		state.help_drop_bomb = false
		return item
	if roll >= table.chance: return null
	return item

## Ganon's intro and Zelda's rescue halt Link while monsters keep updating.
func holds_player() -> bool:
	for actor in enemies:
		if actor.definition.behavior == "ganon" and actor.health > 0 and actor.family.ganon != null and actor.family.ganon.holds_player(): return true
		if actor.definition.behavior == "zelda" and actor.family.zelda_state > 0: return true
	return false

## Ganon's room starts dark and brightens in four steps during his intro.
func darkness() -> int:
	for actor in enemies:
		if actor.definition.behavior == "ganon" and actor.health > 0 and actor.family.ganon != null: return actor.family.ganon.darkness
	return 0

## Ganon holds back only the sword; his brown body takes silver arrows.
func ganon_arrow_hit(actor: RefCounted, silver: bool) -> bool:
	return actor.family.ganon != null and actor.family.ganon.arrow_hit(actor, silver)

## The magical shield also turns Lynel sword shots (Z_07 HandleShotBlocked).
func shield_blocks(world: Node, rock: RefCounted) -> bool:
	return rock.blockable or (rock.kind in ["sword", "magic", "fireball"] and rock.magic_blockable and world.state.item_value(&"magic_shield") > 0)

## Contact effects: damage, capture (Like Like, Wallmaster), or a Bubble's
## effect on the sword (Z_04 UpdateBubble).
func touch_player(world: Node, actor: RefCounted) -> void:
	if world.state.clock_active or world.raft.active: return
	match actor.definition.contact_effect:
		"block_sword":
			world.state.sword_block_ticks = 0xA0
		"curse_sword":
			world.state.sword_cursed = true
		"restore_sword":
			world.state.sword_cursed = false
		"capture":
			if world.captor == null and player_invulnerability == 0:
				world.captor = actor
				actor.capture_ticks = 1
				if actor.definition.behavior == "wallmaster": world.player.place(actor.position())
			if actor.definition.contact_damage > 0: hurt_player(world, actor.definition.contact_damage, actor.position())
			# UpdateLikeLike clears Link's shove; a held Link is never knocked away.
			if world.captor == actor: shove_remaining = 0
		_:
			hurt_player(world, actor.definition.contact_damage, actor.position())

## Z_04 Zol_CheckCollisions and UpdateZolState2_Split: a Zol that survives a
## hit becomes two Gels darting perpendicular to it, without a drop.
func split_zols(world: Node) -> void:
	for actor in enemies.duplicate():
		if not actor.split_pending: continue
		actor.split_pending = false
		actor.health = 0
		actor.death_remaining = 0
		actor.drop_resolved = true
		var first := Vector2i.LEFT if actor.facing.y != 0 else Vector2i.UP
		# UpdateVire: two red Keese fly off in their own random directions; Digdogger's
		# children take random eight-way directions from InitDigdogger1.
		var directions: Array = [first, -first] if actor.definition.behavior == "gel" else []
		if directions.is_empty():
			for i in range(actor.definition.split_count): directions.append(Vector2i.ZERO)
		for direction in directions:
			var spawn = preload("res://scripts/enemy_spawn.gd").new()
			spawn.id = StringName(String(actor.id) + "_gel")
			spawn.enemy = actor.definition.splits_into
			spawn.position = actor.position()
			spawn.facing = direction
			spawn.spawn_ticks = 0
			var gel = Actor.new()
			gel.setup(spawn)
			gel.spawn_remaining = 0
			gel.slot = actor.slot
			if actor.definition.behavior == "digdogger":
				gel.subposition = (actor.position() + Vector2i(8, 8)) * 256
				gel.facing = OverworldEnemy.DIRS[(source_random.at(actor.slot) + directions.size()) & 7]
			if actor.definition.behavior == "gel":
				gel.family.split_ticks = 5
				gel.family.initialized = true
			gel.source.grid_offset = actor.source.grid_offset
			enemies.append(gel)
		encounter_total += directions.size() - 1

## Z_04 UpdateFireball: aimed at Link when made (FireballQSpeeds by the
## _CalcDiagonalSpeedIndex angle), still for 16 frames, then flying through walls
## until it leaves the room bounds.
const FIREBALL_X := [0x70, 0x68, 0x60, 0x58, 0x50, 0x3C, 0x26, 0x10, 0x00]
const FIREBALL_Y := [0x00, 0x10, 0x26, 0x3C, 0x50, 0x58, 0x60, 0x68, 0x70]

func make_fireball(world: Node, at: Vector2i, spread: int) -> RefCounted:
	var rock = Rock.new()
	rock.kind = "fireball"
	rock.subposition = at * 256
	rock.blockable = false
	rock.travelled = spread
	var player: Vector2i = world.player.pixel_position()
	var dx := player.x - at.x
	var dy := player.y - at.y
	var far := absi(dx)
	var near := absi(dy)
	var index := 4
	var step := -1
	if far < near:
		var swap := far
		far = near
		near = swap
		step = 1
	if far - near >= 8:
		while true:
			index += step
			if index == 0 or index == 8: break
			far -= near
			if far < near: break
	rock.direction = Vector2i(signi(dx) if dx != 0 else 1, signi(dy) if dy != 0 else 1)
	rock.velocity = Vector2i(FIREBALL_X[index], FIREBALL_Y[index]) * 4
	rock.age = 0
	return rock

func tick_fireball(world: Node, rock: RefCounted) -> void:
	rock.age += 1
	# Aquamentus spreads its three fireballs a pixel every other frame.
	if rock.travelled != 0 and frame_clock % 2 == 0 and rock.age < 0x70: rock.subposition.y += rock.travelled * 256
	if rock.age > 0x10:
		rock.subposition += Vector2i(rock.direction.x * rock.velocity.x, rock.direction.y * rock.velocity.y)
		if not bounds.grow(8).has_point(rock.position()):
			rock.alive = false
			return
	if not world.state.clock_active and not world.raft.active and player_invulnerability == 0 and source_contact(rock.position(), world.player.pixel_position()):
		if shield_blocks(world, rock) and world.player.facing.dot(rock.direction) < 0 and not world.sword.active():
			world.audio.play(&"parry")
		else:
			hurt_player(world, rock.damage, rock.position())
		rock.alive = false

## Z_07 UpdateArrowOrBoomerang for monster boomerangs: 2.5 pixels a frame out to
## $51 pixels or the room bounds, then back to the thrower.
func tick_boomerang(world: Node, rock: RefCounted) -> void:
	var owner: RefCounted = rock.owner
	if owner == null or owner.health <= 0:
		rock.alive = false
		if owner != null: owner.shot_out = false
		return
	if not rock.returning:
		rock.subposition += rock.direction * 640
		rock.travelled += 2
		var at: Vector2i = rock.position()
		if rock.travelled >= 0x51 or not bounds.grow(16).has_point(at): rock.returning = true
	else:
		var delta: Vector2i = owner.position() - rock.position()
		if absi(delta.x) < 8 and absi(delta.y) < 8:
			rock.alive = false
			owner.shot_out = false
			return
		rock.subposition += Vector2i(signi(delta.x), signi(delta.y)) * 640
	if not world.state.clock_active and not world.raft.active and player_invulnerability == 0 and source_contact(rock.position(), world.player.pixel_position()):
		if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
			world.audio.play(&"parry")
			rock.returning = true
		else:
			hurt_player(world, rock.damage, rock.position())

func player_box(world: Node) -> Rect2i:
	return Rect2i(world.player.pixel_position() + Vector2i(2, 2), Vector2i(12, 12))

func launch_beam(world: Node) -> bool:
	if beam != null or not world.sword.weapon.fires_beam:
		return false
	# MakeSwordShot requires the last partial heart to be at least half full.
	if world.state.health < world.state.max_health - 1:
		return false
	var at: Vector2i = world.player.pixel_position() + world.sword.direction * 16
	if world.sword.direction.x != 0 and (at.x < 20 or at.x >= 236):
		return false
	beam = Beam.new()
	beam.position = at
	beam.direction = world.sword.direction
	beam.damage = world.sword.weapon.damage
	return true

func launch_magic(world: Node) -> bool:
	# A magic shot replaces a sword shot, but never another magic shot.
	if beam != null and beam.kind == "magic": return false
	beam = null
	var at: Vector2i = world.player.pixel_position() + world.rod.direction * 16
	world.audio.play(&"magic")
	if world.rod.direction.x != 0 and (at.x < 20 or at.x >= 236): return false
	beam = Beam.new()
	beam.kind = "magic"
	beam.position = at
	beam.direction = world.rod.direction
	beam.damage = world.rod.weapon.use_damage
	beam.speed_subpixels = world.rod.weapon.use_speed_subpixels
	return true

func impact_beam(world: Node) -> void:
	if beam.kind != "magic":
		beam.impact()
		return
	if world.state.item_value(&"book") > 0 and world.burning_objects() < 2:
		var book: Resource = world.item_for_slot(&"book")
		world.item_objects.append(preload("res://scripts/item_object.gd").standing_fire(beam.position, beam.direction, book.use_duration_ticks if book != null else 79))
		world.audio.play(&"flame")
	beam = null

func tick_beam(world: Node) -> void:
	if beam == null: return
	if beam.burst_remaining > 0:
		beam.burst_remaining -= 1
		if beam.burst_remaining == 0:
			beam.finished = true
			beam = null
		return
	# MoveShot checks room bounds. Beam flight does not use rock terrain checks.
	beam.fraction += beam.speed_subpixels
	var pixels: int = beam.fraction / 256
	beam.fraction %= 256
	for pixel in range(pixels):
		var next: Vector2i = beam.position + beam.direction
		if not (bounds if beam.kind == "magic" else world.room.movement_bounds).has_point(next):
			impact_beam(world)
			return
		beam.position = next
		for actor in enemies:
			if actor.targetable() and beam.hits(actor.hit_position()):
				if actor.receive_hit(beam.damage, beam.direction, beam.kind):
					world.audio.play(&"enemy_hit")
					if actor.health == 0:
						world.audio.play(&"enemy_die")
						record_permanent_kill(world, actor)
					impact_beam(world)
					return
				if actor.parried_hit:
					world.audio.play(&"parry")
					impact_beam(world)
					return

func record_permanent_kill(world: Node, actor: RefCounted) -> void:
	if world.room.enemy_persistence == "permanent" and actor.definition.counts_for_persistence:
		world.state.defeated[String(world.room.id) + "/" + String(actor.id)] = true

func persisted_records(state: RefCounted) -> Dictionary:
	var records: Dictionary = state.room_records.duplicate(true)
	if encounter_room != null and encounter_room.enemy_persistence == "overworld" and not encounter_room.enemies.is_empty():
		if encounter_room.persistence_enemy_count>0:
			var kills: int=base_kills
			for actor in enemies:
				if actor.definition.behavior=="moldorm" and actor.family.moldorm!=null:kills+=actor.family.moldorm.resolved_kills()
			var limit: int=encounter_room.persistence_enemy_count
			records[String(encounter_room.id)]={"kills":mini(kills,limit),"cleared":kills>=limit}
			return records
		var cleared := encounter_total == 0 or encounter_kills >= encounter_total
		records[String(encounter_room.id)] = {
			"kills": encounter_room.enemies.size() if cleared else base_kills + encounter_kills,
			"cleared": cleared}
	return records

func commit_room(state: RefCounted) -> void:
	state.room_records.assign(persisted_records(state))

func advance_frame() -> void:
	source_random.advance()
	frame_clock += 1
	if frame_clock % 10 == 0:
		chase_timer = maxi(0, chase_timer - 1)
		edge_timer = maxi(0, edge_timer - 1)

func update_chase_target(player: Vector2i, food: Variant = null) -> void:
	if not chase_other: chase_target = player
	if food!=null:chase_target=food
	if chase_timer != 0: return
	chase_timer = source_random.at(1) & 7
	chase_other = not chase_other
	if chase_other and chase_target.x == player.x:
		# XOR $FF operates on the NES screen Y, including its 64-pixel HUD.
		chase_target = Vector2i(255 - chase_target.x, 127 - chase_target.y)

func source_contact(a: Vector2i, b: Vector2i) -> bool:
	var delta := (a - b).abs()
	return delta.x < 9 and delta.y < 9

func source_can_enter(world: Node, at: Vector2i, direction: Vector2i) -> bool:
	if direction == Vector2i.LEFT and at.x < bounds.position.x: return false
	if direction == Vector2i.RIGHT and at.x >= bounds.end.x: return false
	if direction == Vector2i.UP and at.y < bounds.position.y: return false
	if direction == Vector2i.DOWN and at.y >= bounds.end.y: return false
	var probe := at + Vector2i(0, 11)
	if direction.x != 0:
		probe.x += 16 if direction.x > 0 else -16
		return not world.is_blocked(probe)
	probe.y += 16 if direction.y > 0 else -16
	return not world.is_blocked(probe) and not world.is_blocked(probe + Vector2i(8, 0))

func assign_source_spawns(room: Resource, state: RefCounted, player: Vector2i, direction: Vector2i) -> void:
	# Traps keep their fixed spots; Wallmasters wait in the walls.
	var original: Array = enemies.filter(func(actor: RefCounted) -> bool: return actor.definition.behavior not in ["native", "trap", "wallmaster", "aquamentus", "gohma", "gleeok", "moldorm", "patra", "zelda", "guard_fire", "rupee_stash"])
	if original.is_empty() or spawn_lists.size() != 4: return
	var list_index := 0
	if direction == Vector2i.LEFT: list_index = 1
	elif direction == Vector2i.DOWN: list_index = 2
	elif direction == Vector2i.UP: list_index = 3
	var points: PackedByteArray = spawn_lists[list_index]
	var cursor: int = state.spawn_cycle
	var positions: Array[Vector2i] = []
	# The original assigns nine slots even if fewer enemies are active.
	for slot in range(9):
		var found := false
		for attempt in range(9):
			var packed := int(points[cursor])
			cursor = (cursor + 1) % 9
			var at := Vector2i((packed & 15) * 16, (packed & 240) + 13 - 64)
			var delta := (player - at).abs()
			if not room.is_pixel_solid(at + Vector2i(0, 11)) and (delta.x >= 34 or delta.y >= 34):
				positions.append(at)
				found = true
				break
		if not found:
			for actor in original: actor.waiting_spawn = true
			return
	state.spawn_cycle = cursor
	for i in range(original.size()):
		var actor = original[i]
		actor.subposition = positions[i % 9] * 256
		actor.facing = Vector2i.ZERO
		actor.source.initialize_facing(actor, player)
		actor.waiting_spawn = false

func next_edge_cell(cell: int) -> int:
	if (cell & 15) == 0: cell += 16
	elif (cell & 15) == 15: cell -= 16
	if (cell & 240) == 0xE0: cell += 1
	elif (cell & 240) == 0x40: cell -= 1
	return cell & 255

func update_edge_spawns(world: Node) -> void:
	var waiting: Array = enemies.filter(func(actor: RefCounted) -> bool: return actor.waiting_spawn)
	if waiting.is_empty(): return
	if not world.room.source_edge_spawns:
		assign_source_spawns(world.room, world.state, world.player.pixel_position(), world.player.facing)
		return
	if edge_timer != 0: return
	# Source initialization visits the highest object slot first.
	waiting.reverse()
	var actor = waiting[0]
	var found := false
	for cell in range(50):
		edge_cursor = next_edge_cell(edge_cursor)
		if edge_cursor in world.room.source_edge_cells:
			found = true
			break
	edge_timer = (source_random.at(actor.slot + 1) & 3) + 2
	if not found: return
	var at := Vector2i((edge_cursor & 15) * 16, (edge_cursor & 240) - 3 - 64)
	var delta: Vector2i = (world.player.pixel_position() - at).abs()
	if delta.x < 34 and delta.y < 34: return
	actor.subposition = at * 256
	actor.facing = Vector2i.ZERO
	actor.source.initialize_facing(actor, world.player.pixel_position())
	actor.waiting_spawn = false
	actor.spawn_remaining = 0

func tick_source_rock(world: Node, rock: RefCounted) -> void:
	rock.age += 1
	if rock.age == 1: return
	if rock.bounce_remaining > 0:
		var displacement := Vector2i(1, -2)
		if rock.bounce_direction == Vector2i.DOWN: displacement = Vector2i(-1, 2)
		elif rock.bounce_direction == Vector2i.LEFT: displacement = Vector2i(-2, -1)
		elif rock.bounce_direction == Vector2i.RIGHT: displacement = Vector2i(2, -1)
		rock.subposition += displacement * 256
		rock.bounce_remaining -= 1
		if rock.bounce_remaining == 0: rock.alive = false
		return
	if not source_within_bounds(rock.position(),rock.direction) or (rock.kind not in ["sword", "magic"] and not source_can_enter(world, rock.position(), rock.direction)):
		rock.alive = false
		return
	rock.subposition += rock.direction * rock.speed_subpixels
	var center: Vector2i = rock.position() + (Vector2i(4,8) if rock.kind == "rock" else Vector2i(8,8))
	var player_center: Vector2i = world.player.pixel_position() + Vector2i(8, 8)
	if not world.state.clock_active and not world.raft.active and player_invulnerability == 0 and source_contact(center, player_center):
		if shield_blocks(world, rock) and world.player.facing == -rock.direction and not world.sword.active():
			world.audio.play(&"parry")
			rock.bounce_direction = world.player.facing
			rock.bounce_remaining = 16
		else:
			hurt_player(world, rock.damage, rock.position())
			rock.alive = false

func source_within_bounds(at: Vector2i, direction: Vector2i) -> bool:
	if direction.x < 0 and at.x < bounds.position.x: return false
	if direction.x > 0 and at.x >= bounds.end.x: return false
	if direction.y < 0 and at.y < bounds.position.y: return false
	if direction.y > 0 and at.y >= bounds.end.y: return false
	return true
