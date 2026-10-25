class_name ItemObject
extends RefCounted
## Bombs and candle fires share object slots $10 and $11 (Z_07 UpdateBombOrFire).
## Bomb minor states 1-5 follow BombTimes; fire walks 16 pixels, then stands.
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

static func bomb(at: Vector2i, facing: Vector2i) -> RefCounted:
	var object = new()
	object.position = at
	object.direction = facing
	return object

static func fire(at: Vector2i, facing: Vector2i) -> RefCounted:
	var object = new()
	object.kind = "fire"
	object.position = at
	object.direction = facing
	return object

## Returns a sound cue to play, if any. Object timers count down before the
## object updates, so a stage set to N ticks lasts exactly N.
func tick() -> StringName:
	if timer > 0:
		timer -= 1
	if kind == "bomb":
		if timer > 0:
			return &""
		timer = BOMB_TIMES[stage - 1] if stage <= 4 else 0
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

## Z_01 CheckMonsterBombOrFireCollision: midpoint distance below $18 or $0E.
func hits(target: Vector2i) -> bool:
	if not active or (kind == "bomb" and not detonating()): return false
	var limit := 0x18 if kind == "bomb" else 0x0E
	var delta := (target + Vector2i(8, 8) - center()).abs()
	return delta.x < limit and delta.y < limit

func damage() -> int:
	return 4 if kind == "bomb" else 1
