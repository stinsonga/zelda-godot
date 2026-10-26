class_name ItemDefinition
extends Resource
## Inventory item. Effects follow Z_01 TakeItem: unique items set their slot,
## graded items only replace a lower grade, counted items add up to a limit.
@export var id: StringName
@export var title: String
## "level" items (map, compass, triforce) set a flag for the current dungeon level.
@export_enum("unique", "grade", "count", "heart_container", "rupees", "health", "level", "bomb_capacity") var effect: String = "unique"
## Items sharing a slot replace or add to each other, as the original slot table does.
@export var slot: StringName
@export var value: int = 1
## Count cap. Bombs use GameState.max_bombs instead.
@export var limit: int = 255
## Selectable for the B button.
@export var usable: bool = false
## B-button use, read from the item at Link's current grade of its slot (Z_05
## WieldArrow and WieldBoomerang, Z_07 UpdateBombOrFire). Defaults are the
## original first grades: arrows 2 damage, 3 pixels a frame; a boomerang flies
## $31 pixels out; a candle burns once a room; bomb stages last BombTimes.
@export var use_damage: int = 2
@export var use_speed: int = 3
## Magic-wave fixed-point speed; $A0 quarter-speed = 2.5 pixels per tick.
@export var use_speed_subpixels: int = 640
@export var use_range: int = 0x31
## Bait lives for three $FF-frame states; authored items may change the lifetime.
@export var use_duration_ticks: int = 765
@export var use_once_per_room: bool = true
@export var use_fuse_ticks: PackedInt32Array = PackedInt32Array([0x30, 0x18, 0x0C, 0x06])
## Sprite name in the visual theme; empty uses the ID.
@export var sprite: StringName

func sprite_name() -> StringName:
	return sprite if not sprite.is_empty() else id

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty(): errors.append("Item ID is empty")
	if effect in ["unique", "grade", "count", "level"] and slot.is_empty(): errors.append("Item " + String(id) + " needs a slot")
	if value < 0 or limit < 1: errors.append("Item " + String(id) + " has an invalid value or limit")
	if use_speed_subpixels < 1 or use_duration_ticks < 1 or use_damage < 0 or use_speed < 1 or use_range < 1 or use_fuse_ticks.size() != 4: errors.append("Item " + String(id) + " has invalid use settings")
	return errors
