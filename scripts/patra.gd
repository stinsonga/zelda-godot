class_name PatraGroup
extends RefCounted
## Z_04 UpdatePatra and UpdatePatraChild. Children update before the parent
## (slots 9..2, then 1), so they apply the parent's previous-frame movement.
## Weak links let a room unload without keeping a cyclic actor graph alive.
var body: WeakRef
var children: Array[WeakRef] = []
## Flyer_ObjOffsetX/Y of the parent: whole pixels moved during its last update.
var offset := Vector2i.ZERO
## Patra_ObjManeuverIndex selects each child's rotation bits.
var maneuver := 0
## The maneuver timer lives in ObjTimer of slot 2, which that child's own
## initialization (ResetObjMetastateAndTimer) clears before the parent reads it.
var maneuver_timer := 0
## Parent ObjState: set once the last child has appeared; enables child collisions.
var all_shown := false

## Z_04 PatraSines: half a circle in 16 steps.
const SINES := [0x00, 0x18, 0x30, 0x47, 0x5A, 0x6A, 0x76, 0x7D, 0x80, 0x7D, 0x76, 0x6A, 0x5A, 0x47, 0x30, 0x18]
## PatraChildStartAngles: slot 2's angle at which each later child appears.
const START_ANGLES := [0x14, 0x10, 0x0C, 0x08, 0x04, 0x00, 0x1C]
## The default q-speed every child keeps (ObjQSpeedFrac $20).
const Q_SPEED := 0x20

func setup(actor: RefCounted) -> void:
	body = weakref(actor)

func add_child(actor: RefCounted) -> void:
	actor.family.patra = self
	actor.family.patra_index = children.size()
	children.append(weakref(actor))

func living_children() -> int:
	var count := 0
	for weak_child in children:
		var child = weak_child.get_ref()
		if child != null and child.health > 0: count += 1
	return count

## The angle (whole part) of the child at an index, or zero if it is gone.
func whole_angle(index: int) -> int:
	if index >= children.size(): return 0
	var child = children[index].get_ref()
	return 0 if child == null else child.family.patra_angle >> 8

func tick_parent(actor: RefCounted, target: Vector2i) -> void:
	actor.shove_remaining = 0
	maneuver_timer = maxi(0, maneuver_timer - 1)
	var before: Vector2i = actor.position()
	actor.family.tick_flight(actor, target)
	offset = actor.position() - before
	# Flip the maneuver when the timer is out and slot 3's child is at angle 0.
	if maneuver_timer == 0 and whole_angle(1) == 0:
		maneuver ^= 1
		# Y is always 0 here, so the source always reloads PatraManeuverTimes[0].
		maneuver_timer = actor.definition.patra_maneuver_ticks

func tick_child(actor: RefCounted) -> void:
	actor.shove_remaining = 0
	var family = actor.family
	var parent = body.get_ref()
	if family.patra_state == 0:
		# The first update after InitPatra is the child's own initialization.
		if not family.patra_initialized:
			family.patra_initialized = true
			return
		if family.patra_index > 0:
			var first = children[0].get_ref()
			if first == null or first.family.patra_state == 0: return
			if first.family.patra_angle >> 8 != START_ANGLES[mini(family.patra_index - 1, START_ANGLES.size() - 1)]: return
		if family.patra_index == children.size() - 1: all_shown = true
		family.patra_state = 1
		family.patra_angle = (0x18 << 8) | (family.patra_angle & 0xFF)
		if parent != null:
			var origin: Vector2i = parent.position() - Vector2i(0, actor.definition.orbit_radius)
			actor.subposition = origin * 256 + Vector2i(posmod(actor.subposition.x, 256), posmod(actor.subposition.y, 256))
		return
	actor.subposition += offset * 256
	family.patra_angle = (family.patra_angle - actor.definition.orbit_angle_step) & 0x1FFF
	actor.subposition += orbit_step(family.patra_angle >> 8, actor.definition.orbit_x_bits[maneuver], actor.definition.orbit_y_bits[maneuver])

## Z_04 RotateObjectLocation: the subpixel change for one frame at an angle
## (whole part, 32 steps a circle): q-speed times the top bits of the sine.
static func orbit_step(whole: int, bits_x: int, bits_y: int) -> Vector2i:
	var step_x: int = Q_SPEED * (SINES[whole & 0x0F] >> (8 - bits_x))
	var step_y: int = Q_SPEED * (SINES[(whole + 8) & 0x0F] >> (8 - bits_y))
	return Vector2i(-step_x if (whole & 0x18) >= 0x10 else step_x, -step_y if ((whole - 8) & 0x18) >= 0x10 else step_y)

func child_active(actor: RefCounted) -> bool:
	return actor.family.patra_state == 1

func child_collides(actor: RefCounted) -> bool:
	return actor.family.patra_state == 1 and all_shown
