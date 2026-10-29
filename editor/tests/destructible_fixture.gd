extends RefCounted
const Pack = preload("../shared/room_pack.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Economy = preload("economy_fixture.gd")
const Blocks = preload("block_fixture.gd")
static func sample(trigger: String = "bomb", direction: String = "right", reveal: String = "item") -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "secret_trial";pack.title = "Secret trial"
	pack.starting_items.append("bombs" if trigger == "bomb" else "blue_candle")
	pack.rooms[0].secret = {"cell":[6,5],"direction":direction,"trigger":trigger,"reveal":reveal}
	pack.rooms[0].shutter_trigger = 4 if reveal == "shutters" else 1
	pack.rooms[0].pickups = [{"id":"reward","item":"heart","position":[96,77],"requires_secret":true}]
	pack.goals = [{"room":"entry","pickup":"reward"}]
	return pack
static func revisit(trigger: String = "bomb") -> Dictionary:
	var pack := Blocks.revisit()
	pack.id = "secret_return";pack.title = "Secret return"
	pack.rooms[0].secret.trigger = trigger
	pack.starting_items.append("bombs" if trigger == "bomb" else "blue_candle")
	if trigger == "bomb":
		pack.rooms[0].connections.right.kind = "bombable";pack.rooms[2].connections.left.kind = "bombable"
		pack.rooms[2].pickups = []
		var previous: Dictionary = pack.rooms[2]
		for i in range(2):
			var room := Pack.room("passage_"+str(i));room.map_position = [i+2,0]
			previous.connections.right = {"target":room.id,"kind":"bombable"}
			room.connections.left = {"target":previous.id,"kind":"bombable"}
			pack.rooms.append(room);previous = room
		previous.pickups = [{"id":"reward","item":"heart","position":[120,77]}]
		pack.goals = [{"room":previous.id,"pickup":"reward"}]
	return pack

static func catalog() -> Dictionary:
	var result := Templates.defaults()
	result.id = "destructible_templates"
	for entry in result.templates:
		if entry.role == "key":
			entry.room.secret = {"trigger":"bomb","cell":[4,4],"direction":"right","reveal":"item"}
			entry.room.pickups = [{"id":"supply","item":"bombs","position":[176,125]}]
	return result

static func gifted_candle() -> Dictionary:
	var pack := sample("fire")
	pack.starting_items = ["wooden_sword"]
	var gift := Pack.room("gift","Candle gift");gift.kind = "cave";gift.map_position = [1,0]
	gift.resident = Pack.resident("gift");gift.resident.wares[1].item = "blue_candle"
	gift.stairs = [{"id":"return","cell":[3,7],"target":"entry","target_position":[120,125]}]
	pack.rooms[0].stairs = [{"id":"gift","cell":[4,3],"target":"gift","target_position":[120,125]}]
	pack.rooms.append(gift)
	return pack
static func purchased_bombs() -> Dictionary:
	var pack := Economy.bomb_shop()
	pack.rooms[0].secret = {"trigger":"bomb","cell":[6,5],"direction":"right","reveal":"item"}
	pack.rooms[0].pickups.append({"id":"hidden_key","item":"key","position":[96,77],"requires_secret":true})
	pack.rooms[0].connections.up.kind = "key";pack.rooms[1].connections.down.kind = "key"
	return pack

static func doorway_revisit(trigger: String) -> Dictionary:
	var pack := Blocks.revisit()
	pack.starting_items.append("bombs" if trigger == "bomb" else "blue_candle")
	var entry: Dictionary = pack.rooms[0]
	entry.secret = {"trigger":trigger,"cell":[2,5],"direction":"left","reveal":"shutters"}
	entry.map_position = [1,0];entry.connections.erase("up")
	entry.connections.left = {"target":"hall","kind":"shutter"}
	pack.rooms[1].map_position = [0,0];pack.rooms[1].connections = {"right":{"target":"entry","kind":"shutter"}}
	pack.rooms[2].map_position = [2,0]
	return pack
