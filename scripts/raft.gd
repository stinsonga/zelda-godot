class_name RaftTravel
extends RefCounted
## Z_04 UpdateDock: idle, one-pixel outbound, or one-pixel inbound travel.
var active := false
var outbound := false
var route: Resource

func reset() -> void:
	active = false
	route = null

func can_arrive(room: Resource, at: Vector2i, state: RefCounted) -> bool:
	return state.item_value(&"raft") > 0 and room.raft_route != null and at == room.raft_route.edge_position

func try_start(world: Node) -> bool:
	if active or world.room.raft_route == null or world.state.item_value(&"raft") == 0: return false
	var definition: Resource = world.room.raft_route
	var at: Vector2i = world.player.pixel_position()
	if at != definition.dock_position and at != definition.edge_position: return false
	route = definition
	outbound = at == route.dock_position
	active = true
	world.player.facing = route.direction() if outbound else -route.direction()
	world.combat.shove_remaining = 0
	world.ladder.reset()
	world.audio.play(&"secret")
	return true

func tick(world: Node) -> void:
	var target: Vector2i = route.edge_position if outbound else route.landing_position
	var at: Vector2i = world.player.pixel_position()
	var remaining: int = absi(target.x - at.x) + absi(target.y - at.y)
	var direction: Vector2i = route.direction() if outbound else -route.direction()
	world.player.place(at + direction * mini(route.speed_pixels_per_tick, remaining))
	world.player.facing = direction
	if world.player.pixel_position() != target: return
	active = false
	if outbound: world.try_exit(direction)
