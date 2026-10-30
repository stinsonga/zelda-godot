class_name EnemyDefinition
extends Resource

@export_enum("native", "nes_octorok", "walker", "jumper", "burrower", "flyer", "gel", "rope", "pols_voice", "trap", "wallmaster", "blue_wizzrobe", "red_wizzrobe", "aquamentus", "dodongo", "gohma", "digdogger", "manhandla", "gleeok", "gleeok_head", "moldorm", "moldorm_segment", "patra", "patra_child", "ganon", "zelda", "guard_fire", "rupee_stash", "zora", "boulder_set", "pond_fairy") var behavior: String = "native"
@export var nes_type: int = 7
@export var shooting_enabled: bool = true
## Z_04 UpdateRope (second quest): the sprite palette follows FrameCounter & 3,
## drawn from sprites named <sprite>_p0 to _p3.
@export var sprite_palette_cycle: bool = false
@export var loot_table: Resource = preload("res://content/enemies/default_loot.tres")
## Source preserves original clock exceptions; authored variants can override.
@export_enum("source", "freeze", "immune") var clock_response: String = "source"
## Empty uses the original family sample; override with a custom bank cue.
@export var appearance_sample: StringName
@export var hurt_sample: StringName
@export var death_sample: StringName
@export var id: StringName
@export var title: String
@export var health: int = 1
## One unit of contact damage is half a heart. Speeds are 1/256 pixel per tick.
@export var contact_damage: int = 1
## Z_01 BeginShove: a monster that knocks Link back turns to the opposite
## direction (ObjectTypeToAttributes bit 7 clear, except the Vire).
@export var turns_after_hitting_link: bool = false
@export var speed_subpixels: int = 128
@export var sprite: StringName = &"red_octorok"
## "directional" sprites are name_direction_pose; "frames" are name_frame, flipped by the renderer.
## "front_back": front or back image (back when facing up), alternating two
## sets every six frames, as Armos draw (DrawArmosAndCheckCollisions).
## "ghini": back when moving up, else front, mirrored toward the side it heads
## (DrawGhiniAndCheckCollisions).
@export_enum("directional", "frames", "front_back", "ghini") var sprite_style: String = "directional"
@export var animation_frame_ticks: int = 6
## Render-only authored sheet cycle; zero keeps native behavior-specific poses.
@export var authored_frame_count: int = 0
@export var authored_clips: Dictionary = {}
@export var authored_draw_size: Vector2 = Vector2(16,16)
@export var authored_draw_offset: Vector2 = Vector2.ZERO
@export var tint: Color = Color.WHITE
@export var fallback_color: Color = Color("d94b3d")
@export_range(0, 255) var turn_chance: int = 112
@export var shoot_cooldown: int = 128
@export var shoot_windup: int = 32
@export var projectile_speed_subpixels: int = 768
@export var spawn_ticks: int = 32

## Walker settings. Negative shooting threshold selects the NES type's red/blue gate.
@export_enum("aligned", "dominant_axis") var targeting: String = "aligned"
@export_range(-1, 255) var shooting_threshold: int = -1
## Boomerangs fly out and return; their thrower waits for them (Z_04 UpdateGoriya).
## Magic (Wizzrobes) flies through walls like sword shots; only the magical shield stops it.
@export_enum("rock", "arrow", "sword", "boomerang", "magic", "fireball") var projectile_kind: String = "rock"
## Throw only when the slot's random byte is one of these; empty throws whenever ready.
@export var shoot_random_values: PackedInt32Array = PackedInt32Array()
@export var projectile_damage: int = 1
@export var projectile_blockable: bool = true
## Jump settings; no terrain collision while airborne.
@export var jump_velocity_subpixels: int = -1024
@export var jump_up_acceleration: int = 80
@export var jump_down_acceleration: int = 128
@export var jump_horizontal_acceleration: int = 128
@export var jump_target_offset: int = 32
## "boulder": always heading down, bounded only at the sides, jumping again on
## landing, and gone below the screen (Z_04 UpdateTektiteOrBoulder).
@export_enum("red", "blue", "boulder") var jump_wait_style: String = "red"
## Burrow cycle: hidden, mound, emerging, exposed, sinking, mound.
@export_enum("roam", "ambush") var burrow_style: String = "roam"
@export var burrow_times: PackedInt32Array = PackedInt32Array([90, 24, 12, 180, 12, 48])
@export var burrow_speeds: PackedInt32Array = PackedInt32Array([24, 40, 64, 128, 64, 40])
@export var burrow_animation_ticks: PackedInt32Array = PackedInt32Array([12, 8, 2, 6, 2, 8])
@export var ambush_distance: int = 40
## Flight uses six states: accelerate, decide, chase, wander, decelerate, rest.
@export_range(32, 224) var flight_max_speed: int = 160
@export_range(1, 16) var flight_acceleration: int = 1
@export var flight_turn_ticks: int = 16
@export var flight_turn_count: int = 6
@export var flight_rest_min: int = 64
@export var flight_rest_random_mask: int = 63
## Peahats can be hurt only at rest; Keese always. Keese decide to chase at Random >= $A0.
@export var flight_vulnerable_resting_only: bool = true
@export_range(0, 255) var flight_chase_threshold: int = 176
@export var flight_initial_speed: int = 31
## The deciding random byte below the chase threshold wanders at or above
## this value and slows to rest below it (Keese $20, flying Ghini $08).
@export_range(0, 255) var flight_rest_threshold: int = 32
@export var flight_random_start: bool = false
## Gel and Zol pause at each square for one of four delays (Z_04 ZolGelDelays).
@export var hop_delays: PackedInt32Array = PackedInt32Array([8, 24, 40, 56])
## Peahats skip the spawn cloud; Keese and walkers use it.
@export var spawn_cloud: bool = true
## A Zol hit without dying becomes two of these (Vires: two red Keese);
## Digdogger becomes split_count little ones when the recorder plays.
@export var splits_into: Resource
@export var split_count: int = 2
## Damage types that only parry: sword, beam, boomerang, arrow, bomb, fire, magic
## (Z_01 ObjInvincibilityMask). Darknuts also parry anything they face.
@export var invincible_to: PackedStringArray = PackedStringArray()
@export var front_shield: bool = false
## Bubbles and traps do not keep a room's shutters closed (Z_05 CheckHasLivingMonsters).
@export var counts_for_clear: bool = true
## Touching Link: "hurt", "capture" (Like Like, Wallmaster), or a Bubble sword effect.
@export_enum("hurt", "capture", "block_sword", "curse_sword", "restore_sword") var contact_effect: String = "hurt"
## Z_01 CheckMonsterShotCollision: an arrow always kills Pols Voice.
@export var arrow_kills: bool = false
## HP 0 in the original: any hit kills, even the boomerang's zero damage.
@export var fragile: bool = false
## Darknuts are never stunned (Z_04 UpdateDarknut clears ObjStunTimer).
@export var stunnable: bool = true
## Bosses draw and collide at their own size, centered on their middle.
@export var size: Vector2i = Vector2i(16, 16)
## Dodongo is 32 wide facing sideways and 16 wide facing up or down.
@export var wide_when_horizontal: bool = false
## Vires hop while walking sideways (Z_04 VireJumpOffsets).
@export var hops: bool = false

## A multipart boss owns the encounter; hands have their own HP and damage timers.
@export var boss_hand: Resource
@export var boss_hand_offsets: PackedVector2Array = PackedVector2Array([Vector2(0,-16),Vector2(0,16),Vector2(-16,0),Vector2(16,0)])
@export var boss_initial_speed: int = 128
@export var boss_lost_hand_speed: int = 128
@export var boss_turn_ticks: int = 16
@export var advances_kill_cycle: bool = true
@export var counts_for_persistence: bool = true
@export var moldorm_segment: Resource
@export_range(1, 4) var moldorm_chain_count: int = 2
@export_range(1, 8) var moldorm_segments_per_chain: int = 5
@export var moldorm_segment_reset_health: int = 2
## "lanmola" chains move segment by segment (Z_04 UpdateLamnola) at chain_speed
## pixels a frame, heads starting upward; "moldorm" chains fly on turn timers.
@export_enum("moldorm", "lanmola") var chain_style: String = "moldorm"
@export_range(1, 4) var chain_speed: int = 1
@export var drops_rewards: bool = true
@export var gleeok_head: Resource
@export_range(1, 4) var gleeok_neck_count: int = 2
@export var gleeok_head_delay: int = 12
@export var gleeok_next_head_health: int = 6
## Patra: up to eight children orbit the flying parent (Z_04 InitPatra).
@export var patra_child: Resource
@export_range(1, 8) var patra_child_count: int = 8
## PatraManeuverTimes[0]: frames before the orbit pattern may switch again.
@export var patra_maneuver_ticks: int = 255
## Patra children: distance above the parent where each appears, the angle
## decrease per frame (256 per 1/32 circle), and the sine bits used for X and
## Y movement in each of the two maneuvers (Z_04 UpdatePatraChild).
@export var orbit_radius: int = 0x2C
@export var orbit_angle_step: int = 0x70
@export var orbit_x_bits: PackedInt32Array = PackedInt32Array([6, 6])
@export var orbit_y_bits: PackedInt32Array = PackedInt32Array([6, 5])
## Ganon (Z_04 Ganon_CheckCollisions, Ganon_RandomizeLocation, Ganon_Dying):
## frames shown after a sword hit, HP restored on turning brown, the two spots
## he reappears at, and where the ashes land relative to him.
@export var ganon_hit_ticks: int = 0x40
@export var ganon_brown_health: int = 15
@export var ganon_spots: PackedVector2Array = PackedVector2Array([Vector2(0x30, 0xA0 - 64), Vector2(0xB0, 0xA0 - 64)])
@export var ganon_ashes_offset: Vector2i = Vector2i(8, 8)
## Rope (Z_04 UpdateRope): walking uses speed_subpixels; within rope_line_up
## pixels of Link's row or column it rushes, and walking turns come after a
## random timer of up to rope_turn_mask frames.
@export var rope_rush_speed: int = 384
@export var rope_line_up: int = 8
@export var rope_turn_mask: int = 0x3F
## Monsters woken from the scenery (Z_04 InitArmosOrFlyingGhini) fade in for
## wake_ticks frames, drawn every other frame, harmful but not yet hittable,
## then move at one of wake_speeds chosen by a random byte (< $80: first).
@export var wake_ticks: int = 0
@export var wake_speeds: PackedInt32Array = PackedInt32Array()
## Never checks weapon collisions (Z_04 UpdateFlyingGhini): only touches Link.
@export var untouchable: bool = false
## When this monster dies, every monster with this definition ID dies too
## (Z_04 UpdateGhini kills the flying Ghini).
@export var defeat_takes: StringName
## "boulder_set" (Z_04 UpdateBoulderSet): drops `spawns` at the top of the
## screen while fewer than spawn_limit of them exist.
@export var spawns: Resource
@export var spawn_limit: int = 3
@export var collision_size: Vector2i = Vector2i.ZERO
@export var collision_offset: Vector2i = Vector2i.ZERO
## Fireball2 ($56) cannot be blocked, even with the magical shield.
@export var projectile_magic_blockable: bool = true

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if clock_response not in ["source", "freeze", "immune"]: errors.append("Unknown clock response")
	if behavior not in ["native", "nes_octorok", "walker", "jumper", "burrower", "flyer", "gel", "rope", "pols_voice", "trap", "wallmaster", "blue_wizzrobe", "red_wizzrobe", "aquamentus", "dodongo", "gohma", "digdogger", "manhandla", "gleeok", "gleeok_head", "moldorm", "moldorm_segment", "patra", "patra_child", "ganon", "zelda", "guard_fire", "rupee_stash", "zora", "boulder_set", "pond_fairy"]: errors.append("Unknown enemy behavior")
	for kind in invincible_to:
		if kind not in ["sword", "beam", "boomerang", "arrow", "bomb", "fire", "magic"]: errors.append("Unknown damage type: " + kind)
	if id.is_empty() or health < 1: errors.append("Enemy needs an ID and positive health")
	if speed_subpixels < 0 or contact_damage < 0 or projectile_damage < 0: errors.append("Enemy speeds and damage cannot be negative")
	if projectile_kind not in ["rock", "arrow", "sword", "boomerang", "magic", "fireball"]: errors.append("Unknown projectile kind")
	if size.x < 8 or size.y < 8: errors.append("Monster size must be at least 8 pixels")
	if behavior == "gel" and hop_delays.size() != 4: errors.append("Gel hops need four delays")
	if animation_frame_ticks < 1: errors.append("Animation frames need a positive length")
	if behavior == "jumper" and (jump_velocity_subpixels >= 0 or mini(jump_up_acceleration, mini(jump_down_acceleration, jump_horizontal_acceleration)) <= 0): errors.append("Jump needs upward velocity and positive acceleration")
	if behavior == "burrower":
		if burrow_times.size() != 6 or burrow_speeds.size() != 6 or burrow_animation_ticks.size() != 6:
			errors.append("Burrow settings need six entries each")
		else:
			for i in range(6):
				if burrow_times[i] < 0 or burrow_speeds[i] < 0 or burrow_animation_ticks[i] < 1: errors.append("Invalid burrow settings")
	if flight_max_speed < 32 or flight_acceleration < 1 or flight_turn_ticks < 1 or flight_turn_count < 1 or flight_rest_min < 1: errors.append("Invalid flight settings")
	if behavior == "manhandla" and boss_hand != null:
		if boss_hand_offsets.size() != 4 or boss_turn_ticks < 1 or boss_initial_speed < 0 or boss_lost_hand_speed < 0: errors.append("Invalid multipart boss configuration")
	if behavior == "gleeok" and (gleeok_head == null or gleeok_neck_count < 1 or gleeok_neck_count > 4 or gleeok_head_delay < 0): errors.append("Gleeok needs a head resource and one to four necks")
	if behavior == "moldorm" and (moldorm_segment == null or moldorm_chain_count < 1 or moldorm_chain_count > 4 or moldorm_segments_per_chain < 1 or moldorm_segments_per_chain > 8 or boss_turn_ticks < 1 or moldorm_segment_reset_health < 1): errors.append("Invalid Moldorm chains")
	if behavior == "ganon" and (ganon_spots.size() != 2 or ganon_hit_ticks < 2 or ganon_brown_health < 1): errors.append("Ganon needs two spots, a hit time, and brown HP")
	if behavior == "patra" and (patra_child == null or patra_maneuver_ticks < 1): errors.append("Patra needs a child resource")
	if behavior == "patra_child" and (orbit_x_bits.size() != 2 or orbit_y_bits.size() != 2 or orbit_angle_step < 1 or orbit_radius < 0): errors.append("Patra children need two maneuvers of rotation bits")
	for value in orbit_x_bits + orbit_y_bits:
		if value < 1 or value > 8: errors.append("Rotation bits range from 1 to 8")
	return errors
