class_name PlayerController
extends RefCounted
## Positions use 1/256-pixel units; normal speed is $60 * 4 per tick.
const SPEED_SUBPIXELS := 384
const GRID := 8 * 256
var grid_origin := Vector2i.ZERO
var subposition := Vector2i.ZERO
var facing := Vector2i.DOWN

func place(at: Vector2i) -> void:
	subposition = at * 256

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
