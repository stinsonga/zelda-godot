extends RefCounted
const Pack = preload("../shared/room_pack.gd")
static func keys(locks: int = 2, price: int = 2, coins: int = 4, gift: bool = false) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "resident_route";pack.title = "Resident route"
	var entry: Dictionary = pack.rooms[0]
	entry.stairs = [{"id":"market","cell":[4,3],"target":"market","target_position":[120,125]}]
	for i in range(coins): entry.pickups.append({"id":"coin_"+str(i),"item":"rupee","position":[48+(i%10)*16,109+(i/10)*16]})
	var previous: Dictionary = entry
	for i in range(locks):
		var room := Pack.room("hall_"+str(i));room.map_position = [0,-i-1]
		previous.connections.up = {"target":room.id,"kind":"key"}
		room.connections.down = {"target":previous.id,"kind":"key"}
		pack.rooms.append(room);previous = room
	previous.pickups = [{"id":"goal","item":"heart","position":[120,77]}]
	pack.goals = [{"room":previous.id,"pickup":"goal"}]
	var market := Pack.room("market","Key market");market.kind = "cave";market.map_position = [1,0]
	market.resident = {"mode":"gift" if gift else "shop","text":"A KEY FOR YOUR ROUTE.","wares":[null,{"item":"key","price":0 if gift else price},null]}
	market.stairs = [{"id":"return","cell":[3,7],"target":"entry","target_position":[120,125]}]
	pack.rooms.append(market)
	return pack
static func barrier(mode: String = "hint") -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "resident_barrier";pack.title = "Resident barrier"
	pack.rooms[0].resident = Pack.resident(mode)
	if mode == "gift": pack.rooms[0].resident.wares[1].item = "key"
	pack.rooms[0].pickups = [{"id":"goal","item":"heart","position":[120,45]}]
	pack.goals = [{"room":"entry","pickup":"goal"}]
	return pack
static func item_gift(item: String = "bow") -> Dictionary:
	var pack := keys(1,0,0,true)
	pack.rooms[-1].resident.wares[1].item = item
	pack.rooms[0].connections.up = {"target":"hall_0","kind":"open","requires":[item]}
	pack.rooms[1].connections.down = {"target":"entry","kind":"open","requires":[item]}
	if item == "wooden_sword":
		pack.starting_items = []
		pack.rooms[1].enemies = [{"id":"guard","type":"crawler","position":[176,61]}]
		pack.rooms[1].pickups[0].requires_clear = true
	return pack
static func choice(coins: int = 1, need_both: bool = false) -> Dictionary:
	var pack := keys(1,1,coins)
	pack.rooms[-1].resident.wares = [{"item":"key","price":1},null,{"item":"bow","price":1}]
	pack.rooms[0].connections.up.requires = ["bow"];pack.rooms[1].connections.down.requires = ["bow"]
	if not need_both: pack.rooms[0].connections.up.kind = "open";pack.rooms[1].connections.down.kind = "open"
	return pack
static func bomb_shop() -> Dictionary:
	var pack := keys(1,1,1)
	pack.rooms[-1].resident.wares[1].item = "bombs"
	pack.rooms[0].connections.up.kind = "bombable";pack.rooms[1].connections.down.kind = "bombable"
	return pack
static func funded_by_gift() -> Dictionary:
	var pack := keys(1,1,0)
	var gift := Pack.room("donor","Coin donor");gift.kind = "cave";gift.map_position = [2,0]
	gift.resident = {"mode":"gift","text":"A COIN FOR YOUR ROUTE.","wares":[null,{"item":"rupee","price":0},null]}
	gift.stairs = [{"id":"return","cell":[3,7],"target":"entry","target_position":[120,125]}]
	pack.rooms[0].stairs.append({"id":"donor","cell":[10,3],"target":"donor","target_position":[120,125]})
	pack.rooms.append(gift)
	return pack
