extends RefCounted
const Pack = preload("../shared/room_pack.gd")
static func sample() -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "resident_village";pack.title = "Resident village"
	pack.rooms[0].stairs = []
	pack.rooms[0].pickups = [{"id":"review_goal","item":"rupee","position":[120,77]}]
	pack.goals = [{"room":"entry","pickup":"review_goal"}]
	var modes := ["hint","gift","shop"]
	for i in range(3):
		var mode: String = modes[i]
		var room := Pack.room(mode,mode.capitalize()+" cave");room.kind = "cave";room.map_position = [i+1,0]
		room.resident = Pack.resident(mode)
		room.resident.text = {"hint":"THE PATH LOOPS BACK.","gift":"A SMALL GIFT FOR YOU.","shop":"SUPPLIES FOR YOUR ROAD."}[mode]
		if mode == "gift": room.resident.wares[1].item = "bow"
		if mode == "shop": room.resident.wares = [null,{"item":"key","price":20},null]
		room.stairs = [{"id":"return","cell":[3,7],"target":"entry","target_position":[120,125]}]
		pack.rooms[0].stairs.append({"id":mode,"cell":[4+i*3,3],"target":mode,"target_position":[120,125]})
		pack.rooms.append(room)
	return pack
