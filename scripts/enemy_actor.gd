class_name EnemyActor
extends RefCounted

const AuthoredAnimation = preload("res://editor/shared/sprite_animation.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
var family = preload("res://scripts/overworld_enemy.gd").new()
var source = preload("res://scripts/nes_octorok.gd").new()
var waiting_spawn := false
var source_random := 0
var source_next_random := 0
var slot := 1
var drop_resolved := false
var definition: Resource
var id: StringName
var subposition := Vector2i.ZERO
var facing := Vector2i.DOWN
var health := 1
var spawn_remaining := 0
var death_remaining := 0
var invulnerability := 0
var shove_remaining := 0
var shove_direction := Vector2i.ZERO
var animation_ticks := 0
var cooldown := 0
var windup := 0
var rng := RandomNumberGenerator.new()
## A thrown boomerang is out; the thrower waits for it.
var shot_out := false
## Set when a Zol survives a hit; the combat simulation splits it.
var split_pending := false
## Set on the frame a monster comes in from the edge: it is initialized, not updated.
var initializing := false
## Set by a Red Leever's init, which restarts RedLeeverLongTimer.
var resets_ambush_timer := false
## Whether the monster's init (Z_07 InitObject) has run; the spawn cloud starts then.
var cloud_started := false
## Like Like and Wallmaster: ticks spent holding Link; 0 when free.
var capture_ticks := 0
## The boomerang stuns monsters for $A0 frames; clocks last for the visit.
var stun_ticks := 0
## The weapon of the killing hit, for HandleMonsterDied's help-drop count.
var died_from := ""
## Frames left fading in after waking from the scenery; just_woke is set on
## the frame the fade ends, for the world to replace the statue's square.
var wake_remaining := 0
## Set once this monster's death has taken its linked monsters down.
var defeat_applied := false
var just_woke := false

## A world may substitute its own variant for the spawn's monster.
func setup(spawn: Resource, variant: Resource = null) -> void:
	authored_state = "idle";authored_state_ticks = 0;authored_attack_remaining = 0;authored_attack_active = false
	id = spawn.id
	definition = spawn.enemy if variant == null else variant
	health = definition.health
	subposition = spawn.position * 256
	facing = spawn.facing
	rng.seed = spawn.seed_value
	spawn_remaining = definition.spawn_ticks if spawn.spawn_ticks < 0 else spawn.spawn_ticks
	cooldown = definition.shoot_cooldown
	wake_remaining = definition.wake_ticks
	if definition.behavior != "native":
		source.setup(definition.nes_type)
		spawn_remaining += 12
		if definition.behavior != "nes_octorok": source.move_speed = definition.speed_subpixels
		# Cloudless flyers (Peahats) still wait for InitObject on their first update.
		if not definition.spawn_cloud and definition.behavior != "flyer": spawn_remaining = 0

## Z_07 InitObject: the cloud waits for ObjTimer, then AnimateAndDrawMetaObject
## takes three six-frame steps. Most monsters start the timer at their slot; the
## family's own init can set it instead (InitSlowOctorockOrGhini: (slot + 1) * $10;
## InitTektite: its direction * 4). The last step leaves the timer at 6.
## The monster appears on the frame of the last step: init frame + T + 12, which
## this countdown (starting on the init frame) reaches with T + 13.
const CLOUD_STEPS := 13
func start_cloud(target: Vector2i) -> void:
	if definition.behavior == "native": return
	if not definition.spawn_cloud:
		# InitPeahat: no cloud; the monster appears from this frame, flying up.
		if definition.behavior == "flyer" and family != null and family.has_method("initialize"):
			spawn_remaining = 1
			family.initialize(self)
		return
	spawn_remaining = slot + CLOUD_STEPS
	# Z_04 InitWalker faces by ChaseTarget on this frame.
	if definition.behavior in ["nes_octorok", "walker"]:
		facing = Vector2i.ZERO
		source.initialize_facing(self, target)
	if definition.behavior == "nes_octorok":
		spawn_remaining = (slot + 1) * 0x10 + CLOUD_STEPS
	elif definition.behavior in ["jumper"] and family != null and family.has_method("initialize"):
		# The family's init runs now, on the monster's first frame.
		family.initialize(self)
		spawn_remaining = family.timer + CLOUD_STEPS
		family.timer = 6
	elif definition.behavior == "burrower" and definition.burrow_style == "ambush":
		# InitLeever runs on into InitSlowOctorockOrGhini: no cloud, and a facing
		# by ChaseTarget (InitWalker). It also restarts RedLeeverLongTimer at 5.
		spawn_remaining = 1
		facing = Vector2i.ZERO
		source.initialize_facing(self, target)
		resets_ambush_timer = true
	elif definition.behavior == "flyer" and family != null and family.has_method("initialize"):
		# InitBlueKeese picks its direction from Random,X now; the timer stays the slot.
		family.initialize(self)

func position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

## Hit checks compare 16-pixel shapes; larger monsters are measured from their middle.
func hit_position() -> Vector2i:
	return position() + definition.collision_offset + (collision_size() - Vector2i(16, 16)) / 2

func collision_size() -> Vector2i:
	return definition.collision_size if definition.collision_size != Vector2i.ZERO else size()

func size() -> Vector2i:
	if definition.wide_when_horizontal and facing.x != 0: return Vector2i(32, 16)
	return definition.size

## Sound cues an actor raises this tick, played by the combat simulation.
var cues: Array[StringName] = []

## Several shots fired in one tick (Aquamentus): {kind, position, spread}.
var pending_shots: Array[Dictionary] = []

func alive() -> bool:
	return health > 0 and spawn_remaining == 0 and not waiting_spawn

func hurtbox() -> Rect2i:
	return Rect2i(position() + Vector2i(2, 2), Vector2i(12, 12))

## Z_01 HandleMonsterWeaponCollision. Returns false for misses and parries;
## parried() reports a parry so the caller can play the sound.
var parried_hit := false

func receive_hit(damage: int, direction: Vector2i, kind: String = "sword") -> bool:
	parried_hit = false
	if not targetable() or invulnerability > 0:
		return false
	if definition.behavior == "gleeok" and kind in ["sword", "beam", "rod"] and family.gleeok != null:
		family.gleeok.writhing = 6
		family.gleeok.animation_timer = 6
	if definition.behavior == "gleeok_head" and family.gleeok != null and family.gleeok.hit_timer > 0: return false
	# Only the sword reaches Ganon here; arrows go through Ganon_CheckCollisions.
	if definition.behavior == "ganon":
		var accepted: bool = kind == "sword" and family.ganon.sword_hit(self, damage)
		if accepted and not hurt_sound().is_empty(): cues.append(hurt_sound())
		return accepted
	# A rod thrust uses the sword mask, except Ganon only accepts his sword path.
	var damage_kind := "sword" if kind == "rod" else kind
	# Darknuts parry weapons arriving head-on; masks parry whole damage types.
	if damage_kind in definition.invincible_to or (definition.front_shield and direction == -facing):
		parried_hit = true
		return false
	health = maxi(0, health - damage)
	var sample_cue: StringName = death_sound() if health == 0 else hurt_sound()
	if not sample_cue.is_empty(): cues.append(sample_cue)
	if health == 0: died_from = kind
	# Z_01 BeginShove: $10, counted down on even FrameCounter values only.
	invulnerability = 0x10
	windup = 0
	source.shove_started = false
	shove_direction = direction
	shove_remaining = 64
	if definition.behavior in ["moldorm_segment", "patra", "patra_child"]: shove_remaining=0
	if definition.behavior == "gleeok_head" and family.gleeok != null:
		shove_remaining = 0
		family.gleeok.head_hit(self)
		return true
	if health == 0:
		death_remaining = 19 if definition.behavior != "native" else 12
		if definition.behavior == "moldorm_segment" and family.moldorm != null: family.moldorm.lose_segment(self)
	elif definition.splits_into != null:
		split_pending = true
	return true

func appearance_sound() -> StringName:
	if not definition.appearance_sample.is_empty(): return definition.appearance_sample
	if definition.behavior == "digdogger" and definition.size.x == 16: return &""
	match definition.behavior:
		"aquamentus", "gleeok": return &"roar_aquamentus"
		"dodongo", "gohma": return &"roar_dodongo"
		"digdogger", "manhandla", "patra": return &"roar_manhandla"
		"ganon": return &"boss_hit"
	return &""

func hurt_sound() -> StringName:
	if not definition.hurt_sample.is_empty(): return definition.hurt_sample
	return &"boss_hit" if definition.behavior in ["aquamentus", "manhandla", "gleeok", "gleeok_head", "gohma", "patra", "ganon"] else &""

func death_sound() -> StringName:
	if not definition.death_sample.is_empty(): return definition.death_sample
	if definition.behavior == "gleeok_head": return hurt_sound()
	return &"boss_hit" if definition.behavior in ["aquamentus", "dodongo", "gohma", "manhandla", "gleeok", "patra", "digdogger"] else &""

func affected_by_clock() -> bool:
	if definition.clock_response != "source": return definition.clock_response == "freeze"
	return definition.behavior not in ["trap", "dodongo", "gohma", "manhandla", "gleeok", "gleeok_head", "patra", "patra_child", "ganon", "zelda", "guard_fire", "rupee_stash"]

## Returns true on the frame a rock should be emitted.
var authored_state := "idle"
var authored_state_ticks := 0
var authored_attack_remaining := 0
var authored_attack_active := false
func tick(target: Vector2i, can_occupy: Callable, segment_probe: Callable = Callable(), can_shoot: bool = true, context: Dictionary = {}) -> bool:
	if definition.authored_clips.is_empty(): return tick_behavior(target,can_occupy,segment_probe,can_shoot,context)
	var before := subposition
	var animate: bool = alive() and wake_remaining==0 and stun_ticks==0 and not (context.get("clock",false) and affected_by_clock())
	var shoved := shove_remaining>0
	var shot := tick_behavior(target,can_occupy,segment_probe,can_shoot,context)
	if animate:
		var attacking: bool = windup>0 or (definition.shooting_enabled and definition.behavior in ["walker","nes_octorok"] and source.shoot_timer>0)
		var started: bool = (attacking and not authored_attack_active) or (shot and not authored_attack_active) or not pending_shots.is_empty()
		if started:
			authored_attack_remaining = AuthoredAnimation.duration(definition.authored_clips,"attack")
		else: authored_attack_remaining = maxi(0,authored_attack_remaining-1)
		var next := "attack" if attacking or shot or authored_attack_remaining>0 else "walk" if subposition!=before and not shoved else "idle"
		authored_state_ticks = authored_state_ticks+1 if authored_state==next and not started else 0
		authored_state = next
		authored_attack_active = attacking
	return shot
func authored_frame() -> int:
	return AuthoredAnimation.frame(definition.authored_clips,authored_state,authored_state_ticks,definition.authored_frame_count,definition.animation_frame_ticks)
func tick_behavior(target: Vector2i, can_occupy: Callable, segment_probe: Callable = Callable(), can_shoot: bool = true, context: Dictionary = {}) -> bool:
	if waiting_spawn: return false
	if spawn_remaining > 0:
		if not cloud_started:
			cloud_started = true
			start_cloud(target)
			if resets_ambush_timer: context["ambush_timer"] = 5
		spawn_remaining -= 1
		return false
	if health <= 0:
		death_remaining = maxi(0, death_remaining - 1)
		return false
	if wake_remaining > 0:
		wake_remaining -= 1
		if wake_remaining == 0: finish_waking()
		return false
	animation_ticks += 1
	if int(context.get("frame_counter", 0)) % 2 == 0: invulnerability = maxi(0, invulnerability - 1)
	if stun_ticks > 0:
		stun_ticks -= 1
		return false
	if context.get("clock", false) and affected_by_clock() and shove_remaining == 0:
		# Global object timers keep counting; movement and attacks do not run.
		family.timer = maxi(0, family.timer - 1)
		source.turn_timer = maxi(0, source.turn_timer - 1)
		cooldown = maxi(0, cooldown - 1)
		return false
	if definition.behavior != "native":
		var probe := segment_probe
		if not probe.is_valid(): probe = func(at: Vector2i, direction: Vector2i) -> bool: return can_occupy.call(at + direction * 16)
		if definition.behavior in ["nes_octorok", "walker"]:
			# A capturing Like Like stays on Link instead of walking.
			if capture_ticks > 0: return false
			var shot: bool = source.tick(self, target, probe, can_shoot, source_random, source_next_random)
			if definition.hops and facing.x != 0 and shove_remaining == 0:
				subposition.y += family.VIRE_HOPS[absi(source.grid_offset) % 16] * 256
			return shot
		return family.tick(self, target, probe, context)
	if shove_remaining > 0:
		for pixel in range(mini(4, shove_remaining)):
			var candidate := position() + shove_direction
			if not can_occupy.call(candidate):
				shove_remaining = 0
				break
			subposition += shove_direction * 256
			shove_remaining -= 1
		return false
	if windup > 0:
		windup -= 1
		if windup == 0:
			cooldown = definition.shoot_cooldown
			return true
		return false
	cooldown = maxi(0, cooldown - 1)
	var remaining: int = definition.speed_subpixels
	while remaining > 0:
		var at := position()
		var coordinate := subposition.x if facing.x != 0 else subposition.y - 13 * 256
		var phase := posmod(coordinate, 4096)
		if phase == 0:
			var choices: Array[Vector2i] = []
			for direction in DIRECTIONS:
				var clear := true
				for distance in range(1, 17):
					if not can_occupy.call(at + direction * distance):
						clear = false
						break
				if clear: choices.append(direction)
			if choices.is_empty(): return false
			var delta := target - at
			var aimed := Vector2i.ZERO
			if absi(delta.x) < 9: aimed = Vector2i.DOWN if delta.y >= 0 else Vector2i.UP
			elif absi(delta.y) < 9: aimed = Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
			if aimed in choices and rng.randi_range(0, 255) <= definition.turn_chance:
				facing = aimed
				if cooldown == 0 and definition.shoot_cooldown > 0:
					windup = definition.shoot_windup
					return false
			elif facing not in choices or rng.randi_range(0, 255) < 48:
				facing = choices[rng.randi_range(0, choices.size() - 1)]
			coordinate = subposition.x if facing.x != 0 else subposition.y - 13 * 256
			phase = posmod(coordinate, 4096)
		var to_boundary := 4096 - phase if facing.x + facing.y > 0 else phase
		if to_boundary == 0: to_boundary = 4096
		var amount := mini(remaining, mini(256, to_boundary))
		var candidate := subposition + facing * amount
		var pixel := Vector2i(floori(candidate.x / 256.0), floori(candidate.y / 256.0))
		if not can_occupy.call(pixel):
			# A surviving enemy can be left between grid points by a shove.
			# Back out along the same axis rather than turning off-grid.
			facing = -facing
			return false
		subposition = candidate
		remaining -= amount
	return false

## InitArmosOrFlyingGhini at timer 0: facing down at a random speed, and three
## pixels into the walker grid, since the statue stood square-aligned.
func finish_waking() -> void:
	just_woke = true
	facing = Vector2i.DOWN
	source.grid_offset = 3
	if not definition.wake_speeds.is_empty():
		source.move_speed = definition.wake_speeds[0 if source_next_random < 0x80 or definition.wake_speeds.size() == 1 else 1]

func targetable() -> bool:
	return alive() and wake_remaining == 0 and not definition.untouchable and family.vulnerable(self)

func can_touch_player() -> bool:
	return alive() and family.contact_enabled(self)

func body_visible() -> bool:
	if wake_remaining > 0: return wake_remaining % 2 == 0
	return family.visible(self)

func sprite_name() -> StringName:
	if definition.behavior == "moldorm_segment":
		if definition.chain_style == "lanmola": return StringName(String(definition.sprite) + ("_head" if family.moldorm_is_head else "_body"))
		return &"moldorm"
	if definition.behavior == "gleeok": return StringName("gleeok_body_"+str(family.gleeok.animation if family.gleeok != null else 0))
	if definition.behavior == "gleeok_head": return StringName("gleeok_flying_"+str(animation_ticks&1)) if family.gleeok_detached else &"gleeok_head"
	if definition.behavior in ["jumper", "burrower", "flyer"]:
		return StringName(String(definition.sprite) + "_" + str(family.frame(self)))
	if definition.behavior == "ganon":
		return StringName("%s_%s_%d" % [definition.sprite, family.ganon.palette, family.ganon.animation])
	# UpdateGuardFire: one image, flipped every six frames.
	if definition.behavior == "guard_fire":
		return StringName(String(definition.sprite) + "_" + str((animation_ticks / 6) % 2))
	if definition.behavior in ["zelda", "rupee_stash"]: return definition.sprite
	if definition.behavior == "zora": return StringName("%s_%d" % [definition.sprite, family.zora_frame()])
	# Patra flips horizontally every two frames; children alternate two tiles.
	if definition.behavior in ["patra", "patra_child"]:
		return StringName(String(definition.sprite) + "_" + str((animation_ticks / 2) % 2))
	if definition.behavior == "manhandla":
		var part: String = "body" if definition.boss_hand != null else ["up","down","left","right"][family.manhandla_index]
		return StringName("manhandla_%s_%d" % [part,(family.manhandla_animation >> 4)&1])
	if definition.behavior == "dodongo":
		return family.dodongo_sprite(self)
	if definition.behavior == "gohma":
		return StringName("%s_%d_%d" % [definition.sprite, family.eye_state, (animation_ticks / 16) % 2])
	if definition.behavior == "digdogger":
		# Shrinking after the recorder flickers big and little every eight frames.
		var little: bool = definition.size.x == 16 or (family.shrink > 0 and (family.shrink / 8) % 2 == 1)
		return StringName("%s_%d" % [&"little_digdogger" if little else definition.sprite, (animation_ticks / 6) % 2])
	if definition.sprite_style == "ghini":
		var back := facing.y < 0
		var mirrored := facing.x < 0 if back else facing.x > 0
		return StringName("%s_%s%s" % [definition.sprite, "back" if back else "front", "_mirrored" if mirrored else ""])
	if definition.sprite_style == "front_back":
		# UpdateArmos: sets 0/1 and 2/3 alternate every six frames; up shows the back.
		return StringName("%s_%d" % [definition.sprite, ((animation_ticks / 6) % 2) * 2 + (1 if facing == Vector2i.UP else 0)])
	if definition.sprite_style == "frames":
		return StringName(String(definition.sprite) + "_" + str((animation_ticks / definition.animation_frame_ticks) % 2))
	var direction := "right" if facing.x > 0 else "left" if facing.x < 0 else "down" if facing.y > 0 else "up"
	return StringName(String(definition.sprite) + "_" + direction + "_" + str((animation_ticks / 6) % 2))
