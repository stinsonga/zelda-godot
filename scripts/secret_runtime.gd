class_name SecretRuntime
extends RefCounted
## The current room's tile object: Z_04 UpdateRockWall, UpdateTree, and
## UpdateRockOrGravestone. Persistent reveals are GameState flags.
## Tile objects never set a speed; half a pixel per tick is provisional.
const PUSH_SUBPIXELS := 128
var room: Resource
var revealed := false
var pushed := false
var push_direction := Vector2i.ZERO
var push_travel := 0
var push_timer := 0
## Recorder: waiting for the tune to end, then the 12-step pond color cycle.
var recorder_pending := false
var drain_ticks := 0

static func flag_key(definition: Resource) -> String:
	return "secret/" + String(definition.id)

func enter(definition: Resource, state: RefCounted) -> void:
	room = definition
	pushed = false
	push_direction = Vector2i.ZERO
	push_travel = 0
	push_timer = 0
	recorder_pending = false
	drain_ticks = 0
	revealed = definition.secret != null and state.flags.get(flag_key(definition), false)

## Walkability for a remembered drained pond.
func drained(definition: Resource, state: RefCounted) -> bool:
	var secret: Resource = definition.secret
	if secret == null or secret.drained_collision.is_empty(): return false
	return revealed if definition == room else state.flags.get(flag_key(definition), false)

func moving() -> bool:
	return push_direction != Vector2i.ZERO and push_travel < 16 * 256

## The pushed object's pixel position while it slides.
func object_position() -> Vector2i:
	return room.secret.cell * 16 + push_direction * (push_travel / 256)

## Z_01 CheckTileObjectsBlocking: a sliding object stops Link nearby.
func blocks_player(at: Vector2i) -> bool:
	if not moving(): return false
	var object := object_position()
	return absi(at.x - object.x) < 0x10 and absi(at.y + 3 - object.y) < 0x10

## Square replacements by cell: [atlas index, four collision bytes, kind].
func overrides(definition: Resource, state: RefCounted) -> Dictionary:
	var result := {}
	var secret: Resource = definition.secret
	if secret == null: return result
	var current := definition == room
	# A push block stands on its cell until pushed. Imported layouts already draw
	# and collide it; this makes authored rooms need only the secret itself.
	if (secret.trigger == "block" or secret.authored_object) and not (current and pushed) and not (revealed if current else state.flags.get(flag_key(definition), false)):
		result[secret.cell] = [secret.object_tile, secret.object_collision, "object"]
	if secret.authored_object and (revealed if current else state.flags.get(flag_key(definition), false)):
		result[secret.cell] = [secret.floor_tile, PackedByteArray([0,0,0,0]), "floor"]
	if current and pushed:
		result[secret.cell] = [secret.floor_tile, PackedByteArray([0, 0, 0, 0]), "floor"]
		if not moving():
			result[secret.cell + push_direction] = [secret.object_tile, secret.object_collision, "object"]
	if secret.reveal_kind != "shutters" and (revealed if current else state.flags.get(flag_key(definition), false)):
		result[secret.reveal_cell] = [secret.reveal_tile, secret.reveal_collision, "floor" if secret.reveal_kind == "item" else "entrance"]
	return result

## Every tick: bombs and fires against walls and trees, and pushed objects.
## Returns true on the tick the secret is revealed.
func update(world: Node) -> bool:
	if room == null or room.secret == null: return false
	var secret: Resource = room.secret
	if moving():
		push_travel += PUSH_SUBPIXELS
		if moving(): return false
		var was_revealed := revealed
		reveal(world)
		return not was_revealed
	if secret.trigger == "recorder":
		if revealed or not recorder_pending or world.recorder_ticks > 0: return false
		# Twelve color steps, one every eight frames, then the stairs appear.
		drain_ticks += 1
		if drain_ticks < 12 * 8: return false
		recorder_pending = false
		reveal(world)
		return true
	if revealed or secret.trigger in ["push", "bracelet_push", "block", "armos"]: return false
	var center: Vector2i = secret.cell * 16 + Vector2i(8, 8)
	for object in world.item_objects:
		var ready: bool = object.detonating() if secret.trigger == "bomb" else object.burning_out()
		var delta: Vector2i = (object.center() - center).abs()
		if ready and delta.x < 0x10 and delta.y < 0x10:
			reveal(world)
			return true
	return false

## While Link walks: gravestones and rocks move only vertically, away from him.
func try_push(world: Node, input: Vector2i) -> bool:
	if room == null or room.secret == null: return false
	if room.secret.trigger == "block": return try_block(world, input)
	if room.secret.trigger not in ["push", "bracelet_push"]: return false
	var secret: Resource = room.secret
	if pushed or input.x != 0 or input.y == 0: return false
	if secret.trigger == "bracelet_push" and world.state.item_value(&"bracelet") == 0: return false
	var at: Vector2i = world.player.pixel_position()
	if at.x != secret.cell.x * 16: return false
	# Z_04 RockPushDirections: from below push up, from above push down.
	var distance: int = at.y + 3 - secret.cell.y * 16
	var wanted := Vector2i.UP if distance >= 0 else Vector2i.DOWN
	if absi(distance) >= 0x11 or input != wanted: return false
	pushed = true
	push_direction = wanted
	push_travel = 0
	return true

## Z_04 UpdateBlock0Idle: aligned with the block, pushing away from Link for
## 16 ticks, with every monster gone.
func try_block(world: Node, input: Vector2i) -> bool:
	if pushed or not world.monsters_gone():
		push_timer = 0
		return false
	var at: Vector2i = world.player.pixel_position()
	var block: Vector2i = room.secret.cell * 16
	var wanted := Vector2i.ZERO
	if at.x == block.x and absi(at.y + 3 - block.y) < 0x11:
		wanted = Vector2i.UP if at.y + 3 >= block.y else Vector2i.DOWN
	elif at.y + 3 == block.y and absi(at.x - block.x) < 0x11:
		wanted = Vector2i.LEFT if at.x >= block.x else Vector2i.RIGHT
	if wanted == Vector2i.ZERO or input != wanted or (room.secret.block_direction != Vector2i.ZERO and input != room.secret.block_direction):
		push_timer = 0
		return false
	push_timer += 1
	if push_timer < 0x10: return false
	pushed = true
	push_direction = wanted
	push_travel = 0
	return true

func reveal(world: Node) -> void:
	revealed = true
	# Pushing a remembered rock again still plays the tune, without a new flag.
	if not (room.secret.persistent and world.reveal_secret(flag_key(room))):
		world.audio.play(&"secret")
