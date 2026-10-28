extends RefCounted
const Pack = preload("../shared/room_pack.gd")
static func sample(direction: String = "right", reveal: String = "shutters") -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack)
	pack.id = "block_vault";pack.title = "Block vault"
	var entry: Dictionary = pack.rooms[0]
	entry.title = "The hidden key"
	entry.secret = {"cell":[6,5],"direction":direction,"reveal":reveal}
	entry.shutter_trigger = 4 if reveal == "shutters" else 1
	entry.pickups = [{"id":"hidden_key","item":"key","position":[96,77],"requires_secret":true}]
	entry.connections.up = {"target":"hall","kind":"shutter"}
	var hall := Pack.room("hall","Locked passage");hall.map_position = [0,-1]
	hall.connections = {"down":{"target":"entry","kind":"shutter"},"right":{"target":"vault","kind":"key"}}
	var vault := Pack.room("vault","The block reward");vault.map_position = [1,-1]
	vault.connections.left = {"target":"hall","kind":"key"}
	vault.pickups = [{"id":"reward","item":"rupee","position":[120,77]}]
	pack.rooms.append(hall);pack.rooms.append(vault)
	pack.goals = [{"room":"vault","pickup":"reward"}]
	return pack

static func revisit() -> Dictionary:
	var pack := sample()
	pack.rooms[0].connections.right = {"target":"vault","kind":"shutter","requires":["bow"]}
	pack.rooms[1].connections.erase("right")
	pack.rooms[1].pickups = [{"id":"tool","item":"bow","position":[120,77]}]
	pack.rooms[2].map_position = [1,0]
	pack.rooms[2].connections.left = {"target":"entry","kind":"shutter","requires":["bow"]}
	return pack
