extends RefCounted
const Pack = preload("../shared/room_pack.gd")
## Two floors stacked on the same map cells: the entry's stairs lead up to a
## landing on 2F, whose neighbour holds the goal.
static func sample() -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "two_floors";pack.title = "Two floors"
	var entry: Dictionary = pack.rooms[0]
	entry.stairs = [{"id":"up","cell":[6,5],"target":"landing","target_position":[48,125]}]
	var landing := Pack.room("landing","Landing");landing.floor = 1;landing.map_position = entry.map_position.duplicate()
	landing.stairs = [{"id":"down","cell":[3,7],"target":"entry","target_position":[120,125]}]
	var gallery := Pack.room("gallery","Gallery");gallery.floor = 1;gallery.map_position = [int(entry.map_position[0]),int(entry.map_position[1])-1]
	landing.connections.up = {"target":"gallery","kind":"open"};gallery.connections.down = {"target":"landing","kind":"open"}
	gallery.pickups = [{"id":"reward","item":"rupee","position":[120,77]}]
	pack.rooms.append(landing);pack.rooms.append(gallery)
	pack.goals = [{"room":"gallery","pickup":"reward"}]
	return pack
