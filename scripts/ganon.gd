class_name GanonFight
extends RefCounted
## Z_04 InitGanon and UpdateGanon. Scene phase 0 holds Link lifting the
## Triforce in the dark room, then brightens it; phase 1 holds a little longer;
## phase 2 is the fight. Ganon is invisible while he moves and only the sword
## harms him then. When his HP runs out he turns brown instead of dying, and a
## silver arrow must finish him before he recovers.
var scene := 0
## Link's ObjTimer drives the intro: $40 dark, then $C0 lit.
var scene_timer := 0x40
## Steps of the fade to light still to go (AnimateWorldFading: four, 10 frames apart).
var darkness := 4
var fade_timer := 0
var fade_started := false
## ObjState: 0 while blue; while brown, counts down from $FF every other frame.
var state := 0
## ObjTimer: frames left visible after a sword hit.
var timer := 0
## Ganon_ObjPhase: 0 alive; from 1 the death sequence counts up to $FF.
var dying := 0
var animation := 0
var turn_counter := 0
## BlueWizzrobe_Move direction; zero (no movement) until the first turn.
var direction := Vector2i.ZERO
var cloud_distance := 8
var rays: Array[Vector2i] = []
var palette := "blue"
## Set on the frame the room item appears at the ashes (phase $A0).
var item_released := false
## Cues for the caller: sound names to play this frame.
var cues: Array[StringName] = []

## GanonBurstDirs for slots 2-9 as vectors.
const RAY_DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i(1, 1), Vector2i(-1, 1), Vector2i.UP, Vector2i(1, -1), Vector2i(-1, -1)]
## Z_04 WizzrobeCollisionOffsets for right, left, down, up, plus the $B hotspot.
const PROBES := {Vector2i.RIGHT: Vector2i(0x0F, 4 + 0x0B), Vector2i.LEFT: Vector2i(0, 4 + 0x0B), Vector2i.DOWN: Vector2i(4, 8 + 0x0B), Vector2i.UP: Vector2i(4, -8 + 0x0B)}

func holds_player() -> bool:
	return scene < 2

func visible(frame: int) -> bool:
	if dying >= 0x50: return false
	# Ganon_ScenePhase0 draws nothing until Link's timer runs out.
	if scene == 0: return scene_timer == 0
	if scene < 2 or dying > 0: return true
	if state != 0: return state >= 0x30 or frame & 1 == 1
	return timer != 0

## Sword collisions are checked only while blue and invisible.
func sword_vulnerable() -> bool:
	return scene == 2 and dying == 0 and state == 0 and timer == 0

func touches_link() -> bool:
	return scene == 2 and dying == 0

## Z_04 Ganon_CheckCollisions: lethal damage restores HP $F0 and turns him
## brown; any damage shows him for $40 frames. He never flashes or recoils.
func sword_hit(actor: RefCounted, damage: int) -> bool:
	if not sword_vulnerable(): return false
	actor.health = maxi(0, actor.health - damage)
	if actor.health == 0:
		actor.health = actor.definition.ganon_brown_health
		state = 0xFF
		palette = "brown"
	timer = actor.definition.ganon_hit_ticks
	return true

## A silver arrow in flight while he is brown starts the death sequence.
func arrow_hit(actor: RefCounted, silver: bool) -> bool:
	if scene != 2 or dying != 0 or state == 0 or not silver: return false
	dying = 1
	# The body flashes ($28 frames of invincibility) and clouds start 8 away.
	actor.invulnerability = 0x28
	cloud_distance = 8
	return true

func tick(actor: RefCounted, context: Dictionary) -> void:
	cues.clear()
	actor.shove_remaining = 0
	var frame: int = context.get("frame", 0)
	timer = maxi(0, timer - 1)
	match scene:
		0:
			animation = 0
			# Link's timer counts down before objects update; Ganon waits unseen.
			if scene_timer > 0: scene_timer -= 1
			if scene_timer > 0:
				if scene_timer == 1: cues.append(&"enemy_hit")
				return
			# UpdateCandle: fade toward light, one palette step every 10 frames.
			if not fade_started:
				fade_started = true
				fade_timer = 0
				cues.append(&"ganon_song")
				return
			if fade_timer > 0: fade_timer -= 1
			if fade_timer > 0: return
			darkness -= 1
			fade_timer = 10
			if darkness == 0:
				scene = 1
				scene_timer = 0xC0
		1:
			animation = 0
			scene_timer -= 1
			if scene_timer == 0:
				scene = 2
				cues.append(&"level_music")
		2:
			if dying > 0: tick_dying(actor, frame)
			elif state != 0: tick_brown(actor, frame)
			elif timer == 0: move_and_shoot(actor, context)
			elif timer == 1: randomize_location(actor, frame)

## Ganon_RandomizeLocation: Y $A0 and X $30 or $B0 by the frame counter.
func randomize_location(actor: RefCounted, frame: int) -> void:
	var spot: Vector2 = actor.definition.ganon_spots[frame & 1]
	actor.subposition = Vector2i(spot) * 256

func tick_brown(actor: RefCounted, frame: int) -> void:
	if frame & 1 == 0: return
	state -= 1
	if state == 0:
		randomize_location(actor, frame)
		palette = "blue"

func move_and_shoot(actor: RefCounted, context: Dictionary) -> void:
	# A new pose every frame, so a hit shows him in a random one.
	animation = (animation + 1) % 6
	turn_counter = (turn_counter + 1) & 0xFF
	var player: Vector2i = context.get("player", Vector2i.ZERO)
	if turn_counter & 0x3F == 0:
		var at: Vector2i = actor.position()
		var turn: Vector2i
		if turn_counter & 0x40: turn = Vector2i.UP if at.y >= player.y else Vector2i.DOWN
		else: turn = Vector2i.LEFT if at.x >= player.x else Vector2i.RIGHT
		if turn != direction:
			direction = turn
			# BlueWizzrobe_AlignWithNearestSquare.
			actor.subposition = Vector2i((at.x + 8) & 0xF0, ((at.y + 64 + 8) & 0xF0) - 3 - 64) * 256
	if direction != Vector2i.ZERO:
		actor.subposition += direction * 256
		# Walls reverse him; with ObjRemDistance 1 he never begins a teleport.
		var blocked: Callable = context.get("blocked", Callable())
		if blocked.is_valid() and blocked.call(actor.position() + PROBES[direction]):
			direction = -direction
			actor.subposition += direction * 256
	if context.get("frame", 0) & 0x3F == 0:
		actor.pending_shots.append({"position": actor.position(), "spread": 0})

func tick_dying(actor: RefCounted, frame: int) -> void:
	dying = mini(0xFF, dying + 1)
	if dying < 0x50: return
	if dying == 0x50:
		palette = "triforce"
		# ADC without CLC after CMP #$50 adds the set carry: the ashes land 8 right.
		actor.subposition += actor.definition.ganon_ashes_offset * 256
		rays.clear()
		for i in range(8): rays.append(actor.position() + Vector2i(4, 4))
		cues.append(&"enemy_die")
		cues.append(&"ganon_song")
	if dying < 0xA0:
		if cloud_distance > 0 and frame & 7 == 0: cloud_distance -= 1
		# Cardinal rays (slots 2, 3, 4, and 7) move every frame, diagonals 3 in 4.
		for i in range(8):
			if i < 3 or i == 5 or frame & 3 != 0: rays[i] += RAY_DIRECTIONS[i]
	elif dying == 0xA0:
		rays.clear()
		item_released = true
		cues.append(&"item")
		actor.health = 0
		actor.death_remaining = 0

## The cloud positions around the ashes, in Ganon_DrawBurst order.
func clouds(at: Vector2i) -> Array[Vector2i]:
	var d := cloud_distance
	return [at + Vector2i(-d, -d), at + Vector2i(d, -d), at + Vector2i(-d, d), at + Vector2i(d, d),
		at + Vector2i(0, -d), at + Vector2i(0, d), at + Vector2i(-d, 0), at + Vector2i(d, 0)]
