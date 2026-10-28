extends RefCounted
const Pack = preload("../shared/room_pack.gd")
static func sample(arrival_on_return: bool = false) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "stair_vault";pack.title = "Stair vault"
	var entry: Dictionary = pack.rooms[0]
	entry.secret = {"cell":[6,5],"direction":"right","reveal":"item"}
	entry.stairs = [{"id":"hidden_stairs","cell":[6,5],"target":"cellar","target_position":[48,45] if arrival_on_return else [48,61],"requires_secret":true}]
	entry.connections.up = {"target":"vault","kind":"open","requires":["bow"]}
	var cellar := Pack.cellar("cellar");cellar.map_position = [1,0]
	cellar.stairs = [{"id":"return","cell":[3,3],"target":"entry","target_position":[120,125]}]
	cellar.pickups = [{"id":"bow","item":"bow","position":[120,125]}]
	var vault := Pack.room("vault","The stair reward");vault.map_position = [0,-1]
	vault.connections.down = {"target":"entry","kind":"open","requires":["bow"]}
	vault.pickups = [{"id":"reward","item":"rupee","position":[120,77]}]
	pack.rooms.append(cellar);pack.rooms.append(vault)
	pack.goals = [{"room":"vault","pickup":"reward"}]
	return pack
static func trap(arrival_root: bool = false) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack)
	var entry: Dictionary = pack.rooms[0]
	var pit := Pack.room("pit");pit.map_position = [1,0]
	var hall := Pack.room("hall");hall.map_position = [0,-1];hall.spawn = [112,125]
	for y in range(2,9): hall.tiles[y] = "#######.########"
	hall.stairs = [{"id":"trap","cell":[7,5],"target":"pit","target_position":[120,125]}]
	hall.pickups = [{"id":"goal","item":"rupee","position":[112,45],"requires_clear":arrival_root}]
	entry.stairs = [{"id":"enter","cell":[6,5],"target":"hall","target_position":[112,77] if arrival_root else [112,125]}]
	if arrival_root:
		pack.starting_items = []
		hall.pickups.append({"id":"sword","item":"wooden_sword","position":[112,125]})
		hall.enemies = [{"id":"guard","type":"crawler","position":[112,45]}]
	pack.rooms.append(hall);pack.rooms.append(pit)
	pack.goals = [{"room":"hall","pickup":"goal"}]
	return pack
