class_name EnemyDefinition
extends Resource

@export_enum("native", "nes_octorok", "walker", "jumper", "burrower", "flyer") var behavior: String = "native"
@export var nes_type: int = 7
@export var shooting_enabled: bool = true
@export var loot_table: Resource = preload("res://content/enemies/default_loot.tres")
@export var id: StringName
@export var title: String
@export var health: int = 1
## One unit of contact damage is half a heart. Speeds are 1/256 pixel per tick.
@export var contact_damage: int = 1
@export var speed_subpixels: int = 128
@export var sprite: StringName = &"red_octorok"
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
@export_enum("rock", "arrow", "sword") var projectile_kind: String = "rock"
@export var projectile_damage: int = 1
@export var projectile_blockable: bool = true
## Jump settings; no terrain collision while airborne.
@export var jump_velocity_subpixels: int = -1024
@export var jump_up_acceleration: int = 80
@export var jump_down_acceleration: int = 128
@export var jump_horizontal_acceleration: int = 128
@export var jump_target_offset: int = 32
@export_enum("red", "blue") var jump_wait_style: String = "red"
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

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if behavior not in ["native", "nes_octorok", "walker", "jumper", "burrower", "flyer"]: errors.append("Unknown enemy behavior")
	if id.is_empty() or health < 1: errors.append("Enemy needs an ID and positive health")
	if speed_subpixels < 0 or contact_damage < 0 or projectile_damage < 0: errors.append("Enemy speeds and damage cannot be negative")
	if projectile_kind not in ["rock", "arrow", "sword"]: errors.append("Unknown projectile kind")
	if behavior == "jumper" and (jump_velocity_subpixels >= 0 or mini(jump_up_acceleration, mini(jump_down_acceleration, jump_horizontal_acceleration)) <= 0): errors.append("Jump needs upward velocity and positive acceleration")
	if behavior == "burrower":
		if burrow_times.size() != 6 or burrow_speeds.size() != 6 or burrow_animation_ticks.size() != 6:
			errors.append("Burrow settings need six entries each")
		else:
			for i in range(6):
				if burrow_times[i] < 0 or burrow_speeds[i] < 0 or burrow_animation_ticks[i] < 1: errors.append("Invalid burrow settings")
	if flight_max_speed < 32 or flight_acceleration < 1 or flight_turn_ticks < 1 or flight_turn_count < 1 or flight_rest_min < 1: errors.append("Invalid flight settings")
	return errors
