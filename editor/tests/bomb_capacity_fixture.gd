extends RefCounted
const Pack = preload("../shared/room_pack.gd")
## Nine bombable walls in a corridor of rooms, with twelve bombs: two bundles
## in the entry and one in room_<late>. With late = 0 all three lie in the
## entry, the bag overflows, and only eight bombs exist for nine walls.
static func sample(late: int = 4) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "bomb_corridor";pack.title = "Bomb corridor"
	pack.rooms[0].pickups = [{"id":"bombs_a","item":"bombs","position":[48,125]},{"id":"bombs_b","item":"bombs","position":[192,125]}]
	var previous: Dictionary = pack.rooms[0]
	for i in range(1,10):
		var room := Pack.room("room_%d" % i);room.map_position = [i,0]
		previous.connections.right = {"target":room.id,"kind":"bombable"}
		room.connections.left = {"target":previous.id,"kind":"bombable"}
		pack.rooms.append(room);previous = room
	pack.rooms[late].pickups.append({"id":"bombs_c","item":"bombs","position":[120,125]})
	previous.pickups.append({"id":"reward","item":"rupee","position":[120,77]})
	pack.goals = [{"room":previous.id,"pickup":"reward"}]
	return pack
