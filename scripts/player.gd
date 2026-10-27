class_name PlayerController
extends RefCounted
## Positions use 1/256-pixel units; normal speed is $60 * 4 per tick.
const SPEED_SUBPIXELS := 384
const QUARTER_SPEED := 0x60
## Z_05 InitLinkSpeed: half speed on mountain stairs.
const STAIRS_QUARTER_SPEED := 0x30
const GRID := 8 * 256
## Z_07 MoveObject: Link's grid offset stops at +8 and -8.
const GRID_LIMIT := 8
var grid_origin := Vector2i.ZERO
var subposition := Vector2i.ZERO
var facing := Vector2i.DOWN
## ObjPosFrac: one fraction byte shared by both axes, as in the original.
var fraction := 0
## ObjGridOffset: pixels moved since the last grid point, +1 right or down and
## -1 left or up, kept across frames and reversals.
var grid_offset := 0
## Where move_frame last left Link; if anything else moved him since (shoves,
## entry walks), the offset is taken again from his position.
var moved_to := Vector2i(-1, -1)
## ObjQSpeedFrac, and whether the last tile probed ahead (ObjCollidedTile) was stairs.
var quarter_speed := QUARTER_SPEED
var collided_stairs := false
## Link_GoStraight: diagonal input at the last grid point; a perpendicular part of
## the input then keeps Link going straight until the next grid point.
var go_straight := false

func place(at: Vector2i) -> void:
	subposition = at * 256
	fraction = 0
	grid_offset = 0
	moved_to = at
	quarter_speed = QUARTER_SPEED
	collided_stairs = false

## One frame of free movement. The direction follows Z_05 Link_HandleInput: at a
## grid point Link takes the input (Link_ModifyDirAtGridPoint); between points
## Link_ModifyDirOnGridLine keeps, reverses, or turns him back. Z_07 MoveObject
## then applies four quarter-steps of $60 into the shared fraction. A carry moves
## Link one pixel unless his grid offset is already +-8
## (AddQSpeedToPositionFraction / SubQSpeedFromPositionFraction), so he stops on
## each grid point for the rest of the frame. Link_EndMoveAndAnimate then clears
## an offset that is a multiple of 8.
##
## stairs_at(pixel, direction) reports whether the tile probed ahead is mountain
## stairs (overworld only). InitLinkSpeed reads the tile the previous frame's
## collision check found, or at a grid point the one just probed for the input.
##
## With move false (Link wielding the sword), only the turning runs: Walker_Move
## zeroes the moving direction, so MoveObject does nothing.
func move_frame(wanted: Vector2i, can_enter_segment: Callable, stairs_at: Callable = Callable(), move: bool = true) -> void:
	if wanted == Vector2i.ZERO:
		return
	var pixel := pixel_position()
	subposition = pixel * 256
	if pixel != moved_to:
		grid_offset = grid_phase(pixel)
	var diagonal := wanted.x != 0 and wanted.y != 0
	if grid_offset == 0:
		# Link_ModifyDirAtGridPoint checks right, left, down, up and keeps the last
		# walkable one, so with two directions held vertical wins. Neither walkable:
		# Link stays as he is.
		go_straight = false
		if diagonal:
			var choices := [Vector2i(0, wanted.y), Vector2i(wanted.x, 0)]
			var walkable := choices.filter(func(choice: Vector2i) -> bool: return can_enter_segment.call(pixel, choice))
			if walkable.is_empty(): return
			facing = walkable[0]
			go_straight = true
		else:
			facing = wanted
		if stairs_at.is_valid(): collided_stairs = stairs_at.call(pixel, facing)
		init_speed()
		# Walker_CheckTileCollision checks the next segment only at a grid point.
		if not diagonal and not can_enter_segment.call(pixel, facing):
			return
	else:
		# GetOppositeDir keeps one direction, the lowest bit: horizontal first.
		if diagonal: wanted = Vector2i(wanted.x, 0)
		move_on_line(wanted)
	if not move:
		moved_to = pixel
		return
	var forward := facing.x + facing.y > 0
	# Walker_CheckTileCollision probes ahead before the move; InitLinkSpeed uses it next frame.
	if stairs_at.is_valid(): collided_stairs = stairs_at.call(pixel, facing)
	apply_quarter_steps(forward)

## Z_05 Link_ModifyDirOnGridLine with a single input direction.
func move_on_line(wanted: Vector2i) -> void:
	if wanted == facing:
		init_speed()
	elif wanted == -facing:
		facing = wanted
	elif not go_straight and absi(grid_offset) < GRID_LIMIT / 2:
		# Perpendicular input less than halfway along: keep going if Link is already
		# heading back to the grid point he left, else turn back toward it.
		var heading_back := grid_offset >= 0 if facing.x + facing.y < 0 else grid_offset < 0
		if not heading_back:
			facing = -facing
			# The same spot measured the other way: -1 => 7, 3 => -5.
			grid_offset += GRID_LIMIT if grid_offset < 0 else -GRID_LIMIT

## Z_07 MoveObject's four quarter-steps, then Link_EndMoveAndAnimate's offset reset.
func apply_quarter_steps(forward: bool) -> void:
	for quarter in range(4):
		var carry := false
		if forward:
			fraction += quarter_speed
			carry = fraction >= 256
		else:
			fraction -= quarter_speed
			carry = fraction < 0
		fraction = posmod(fraction, 256)
		if carry and absi(grid_offset) != GRID_LIMIT:
			subposition += facing * 256
			grid_offset += 1 if forward else -1
	if grid_offset != 0 and grid_offset % GRID_LIMIT == 0:
		grid_offset = 0
	moved_to = pixel_position()

## Z_07 UpdateMode4and6EnterLeave: mode 4 walks Link into a dungeon room with
## MoveObject alone, from the grid offset InitMode_EnterRoom set, until it reaches
## +-8. The offset isn't reset at 16 on the way. Returns true when he has arrived.
func walk_in_frame(direction: Vector2i) -> bool:
	facing = direction
	var forward := direction.x + direction.y > 0
	for quarter in range(4):
		fraction += quarter_speed if forward else -quarter_speed
		var carry := fraction >= 256 if forward else fraction < 0
		fraction = posmod(fraction, 256)
		if carry and absi(grid_offset) != GRID_LIMIT:
			subposition += direction * 256
			grid_offset += 1 if forward else -1
	moved_to = pixel_position()
	if absi(grid_offset) != GRID_LIMIT: return false
	grid_offset = 0
	return true

## Z_05 InitLinkSpeed: $30 on stairs, else $60. Slowing down clears the fraction.
func init_speed() -> void:
	var speed := STAIRS_QUARTER_SPEED if collided_stairs else QUARTER_SPEED
	if speed == STAIRS_QUARTER_SPEED and quarter_speed != STAIRS_QUARTER_SPEED: fraction = 0
	quarter_speed = speed

## Pixels past the last grid point along the facing axis (a positive offset).
func grid_phase(pixel: Vector2i) -> int:
	var relative := pixel - grid_origin
	return posmod(relative.x if facing.x != 0 else relative.y, GRID_LIMIT)

func pixel_position() -> Vector2i:
	return Vector2i(floori(subposition.x / 256.0), floori(subposition.y / 256.0))

func step(wanted: Vector2i, can_occupy: Callable, can_enter_segment: Callable = Callable(), movement_budget: int = SPEED_SUBPIXELS) -> void:
	if wanted == Vector2i.ZERO:
		return
	var remaining := movement_budget
	while remaining > 0:
		var relative := subposition - grid_origin * 256
		var horizontal := facing.x != 0
		var coordinate := relative.x if horizontal else relative.y
		var phase := posmod(coordinate, GRID)
		var turning := wanted.x * facing.x + wanted.y * facing.y == 0
		if turning and phase != 0:
			# Z_05 Link_ModifyDirOnGridLine: return toward the nearer grid
			# point when less than halfway through a segment. No sideways snap.
			var sign_to_grid := -1 if phase < GRID / 2 else 1
			if phase == GRID / 2:
				sign_to_grid = facing.x + facing.y
			facing = Vector2i(sign_to_grid, 0) if horizontal else Vector2i(0, sign_to_grid)
		else:
			facing = wanted
			horizontal = facing.x != 0
			coordinate = relative.x if horizontal else relative.y
			phase = posmod(coordinate, GRID)
		# The NES checks the next segment at a grid point, then lets Link
		# complete it. Continuous rectangle checks can strand him off-grid.
		if phase == 0 and can_enter_segment.is_valid():
			if not can_enter_segment.call(pixel_position(), facing):
				return
		var to_boundary := GRID - phase if facing.x + facing.y > 0 else phase
		if to_boundary == 0:
			to_boundary = GRID
		var amount := mini(remaining, to_boundary)
		if not can_enter_segment.is_valid():
			# Generic occupancy callback retained for isolated controller checks.
			amount = mini(amount, 256)
			var candidate := subposition + facing * amount
			var pixel := Vector2i(floori(candidate.x / 256.0), floori(candidate.y / 256.0))
			if not can_occupy.call(pixel):
				return
		subposition += facing * amount
		remaining -= amount
