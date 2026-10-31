extends RefCounted
const Pack = preload("../shared/room_pack.gd")
## A river across the entry (crossed going up) and a stream down the vault
## (crossed going right). width widens both to two tiles, past the ladder.
static func sample(width: int = 1, ladder: bool = true) -> Dictionary:
	var pack := Pack.fresh();Pack.upgrade(pack);pack.id = "river_vault";pack.title = "River vault"
	var entry: Dictionary = pack.rooms[0]
	for y in range(4,4+width): entry.tiles[y] = "##~~~~~~~~~~~~##"
	entry.connections.up = {"target":"vault","kind":"open"}
	if ladder: entry.pickups = [{"id":"ladder","item":"ladder","position":[48,125]}]
	var vault := Pack.room("vault","Across the stream");vault.map_position = [0,-1]
	for y in range(2,9): vault.tiles[y] = vault.tiles[y].substr(0,10)+"~".repeat(width)+vault.tiles[y].substr(10+width)
	vault.connections.down = {"target":"entry","kind":"open"}
	vault.pickups = [{"id":"reward","item":"rupee","position":[200,77]}]
	pack.rooms.append(vault)
	pack.goals = [{"room":"vault","pickup":"reward"}]
	return pack
