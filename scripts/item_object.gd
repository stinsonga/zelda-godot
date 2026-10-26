class_name ItemObject
extends RefCounted
## Bombs and candle fires share object slots $10 and $11 (Z_07 UpdateBombOrFire).
## Bomb minor states 1-5 follow BombTimes; fire walks 16 pixels, then stands.
## Arrows (slot $12) and the boomerang (slot $0F) fly at q-speed $C0, 3 pixels a frame.
const BOMB_TIMES: Array[int] = [0x30, 0x18, 0x0C, 0x06]
const FIRE_STAND_TICKS := 0x3F
var kind := "bomb"
var position := Vector2i.ZERO
var direction := Vector2i.UP
var stage := 1
var timer := 0
var travelled := 0
var subpixel := 0
var active := true
var damage_points := 1
## Pixels a frame for arrows and boomerangs; bomb stage lengths.
var speed := 3
var fuse: Array[int] = BOMB_TIMES
## Boomerang: pixels it may fly out, and whether it is coming back.
var limit := 0
var returning := false

static func bomb(at: Vector2i, facing: Vector2i, fuse_ticks: Array[int] = BOMB_TIMES) -> RefCounted:
	var object = new()
	object.position = at
	object.direction = facing
	object.fuse = fuse_ticks
	return object

static func bait(at: Vector2i, lifetime: int = 765) -> RefCounted:
	var object=new()
	object.kind="bait"
	object.position=at
	object.timer=lifetime
	return object

static func fire(at: Vector2i, facing: Vector2i) -> RefCounted:
	var object = new()
	object.kind = "fire"
	object.position = at
	object.direction = facing
	return object

static func arrow(at: Vector2i, facing: Vector2i, damage: int, pixels_per_tick := 3) -> RefCounted:
	var object = new()
	object.kind = "arrow"
	# Z_05 WieldWeapon: vertical arrows sit 3 pixels right of Link's line.
	object.position = at + (Vector2i(3, 0) if facing.y != 0 else Vector2i.ZERO)
	object.direction = facing
	object.damage_points = damage
	object.speed = pixels_per_tick
	return object

static func boomerang(at: Vector2i, direction: Vector2i, flight_limit: int, pixels_per_tick := 3) -> RefCounted:
	var object = new()
	object.kind = "boomerang"
	object.position = at
	object.direction = direction
	object.limit = flight_limit
	object.speed = pixels_per_tick
	return object

## Arrows end in a three-frame spark (state $20) after a hit or at the room edge.
func spark() -> void:
	if kind == "arrow" and stage == 1:
		stage = 2
		timer = 3

## Returns a sound cue to play, if any. Object timers count down before the
## object updates, so a stage set to N ticks lasts exactly N.
func tick() -> StringName:
	if timer > 0:
		timer -= 1
	if kind == "bait":
		if timer==0:active=false
		return &""
	if kind == "arrow":
		if stage == 1: position += direction * speed
		elif timer == 0: active = false
		return &""
	if kind == "boomerang":
		if not returning:
			position += direction * speed
			travelled += speed
			if travelled >= limit: returning = true
		return &""
	if kind == "bomb":
		if timer > 0:
			return &""
		timer = fuse[stage - 1] if stage <= 4 else 0
		stage += 1
		if stage == 5: active = false
		return &"bomb_blow" if stage == 3 else &""
	if stage == 1:
		# Quarter speed $20: half a pixel per tick, ignoring terrain like MoveObject.
		subpixel += 128
		if subpixel >= 256:
			subpixel -= 256
			position += direction
			travelled += 1
		if travelled == 16:
			stage = 2
			timer = FIRE_STAND_TICKS
		return &""
	if timer == 0:
		active = false
	return &""

func detonating() -> bool:
	return kind == "bomb" and stage == 3

## Bombs hide behind their smoke after detonation begins.
func showing_bomb() -> bool:
	return kind == "bomb" and stage <= 2

## Z_04 UpdateTree: only a standing fire about to go out burns a tree.
func burning_out() -> bool:
	return kind == "fire" and stage == 2 and timer < 2

func center() -> Vector2i:
	return position + Vector2i(8, 8)

## Z_01 CheckMonsterBombOrFireCollision: midpoint distance below $18 or $0E;
## arrows and boomerangs use the shot thresholds.
func hits(target: Vector2i) -> bool:
	if kind=="bait" or not active or (kind == "bomb" and not detonating()) or (kind == "arrow" and stage != 1): return false
	var limit := 0x18 if kind == "bomb" else 0x0E if kind == "fire" else 0x0C
	var delta := (target + Vector2i(8, 8) - center()).abs()
	return delta.x < limit and delta.y < limit

func damage() -> int:
	if kind == "arrow": return damage_points
	return 4 if kind == "bomb" else 1
