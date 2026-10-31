extends RefCounted
const Pack = preload("../shared/room_pack.gd")
## The entry holds the map, compass, five rupees and a red candle; the hall
## above is gated on the blue candle and holds the objective heart container.
static func sample() -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "more_items";pack.title = "More items"
	var entry: Dictionary = pack.rooms[0]
	entry.pickups = [{"id":"map","item":"map","position":[48,77]},{"id":"compass","item":"compass","position":[192,77]},
		{"id":"coins","item":"five_rupees","position":[80,109]},{"id":"candle","item":"red_candle","position":[160,109]}]
	var hall := Pack.room("hall","Hall");hall.map_position = [int(entry.map_position[0]),int(entry.map_position[1])-1]
	entry.connections.up = {"target":"hall","kind":"open","requires":["blue_candle"]}
	hall.connections.down = {"target":"entry","kind":"open","requires":["blue_candle"]}
	hall.pickups = [{"id":"container","item":"heart_container","position":[120,77]}]
	pack.rooms.append(hall)
	pack.goals = [{"room":"hall","pickup":"container"}]
	return pack
