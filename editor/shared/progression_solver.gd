extends RefCounted
## Event-state search over inventory and opened doors, with room-local collision.
const Pack = preload("room_pack.gd")
const DIRS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
const EDGE := {"up":Vector2i(120,-3),"down":Vector2i(120,157),"left":Vector2i(0,77),"right":Vector2i(240,77)}
const HOT := {"up":Vector2i(120,29),"down":Vector2i(120,125),"left":Vector2i(32,77),"right":Vector2i(208,77)}
const CELLS := {"up":[7,8,23,24],"down":[151,152,167,168],"left":[80,81],"right":[94,95]}
const COLLISION := {"up":[3,12,3,12],"down":[3,12,3,12],"left":[0,0],"right":[0,0]}
var rooms: Dictionary = {}
var pickups: Array = []
var door_ids: Dictionary = {}
var cache: Dictionary = {}
var reasons: Dictionary = {}
var reached: Dictionary = {}
var goal_mask := 0
var started := 0
var has_stairs := false
const ASSUMPTIONS := "Assumes reachable sword-vulnerable enemies can be defeated without spending progression supplies. Does not model health, combat skill, enemy drops, water/ladder deployment, other secret types or resource farming. Directional blocks reset on room entry and require the room to be cleared. Active stairs force transitions; arriving on a stair suppresses it until Link moves away."
func item_bit(item: String) -> int: return 1 << Pack.REQUIRED_ITEMS.find(item)
func owns(state: Dictionary, item: String) -> bool: return (state.items & item_bit(item)) != 0
func requires_met(state: Dictionary, link: Dictionary) -> bool:
	for item in link.get("requires",[]):
		if not owns(state,item): return false
	return true
func reason(text: String) -> void:
	if reasons.size() < 128: reasons[text] = true
func report(status: String, message: String, states: int = 0, steps: Array = [], events: Array = []) -> Dictionary:
	return {"status":status,"message":message,"states":states,"steps":steps,"events":events,"reached_rooms":reached.keys(),"blockers":reasons.keys(),"assumptions":ASSUMPTIONS}
func solve(pack: Dictionary, state_limit: int = 20000, time_limit_ms: int = 8000) -> Dictionary:
	rooms.clear();pickups.clear();door_ids.clear();cache.clear();reasons.clear();reached.clear();goal_mask = 0;has_stairs = false
	started = Time.get_ticks_msec()
	var errors := Pack.validate(pack)
	if not errors.is_empty(): return report("invalid","\n".join(errors))
	if pack.schema != 2 or pack.goals.is_empty(): return report("unsupported","Choose at least one objective pickup (version 2) before checking progression.")
	if pack.rooms.size() > 32: return report("unsupported","This solver supports at most 32 rooms.")
	for room in pack.rooms:
		if room.has("resident"): return report("unsupported",String(room.id)+": resident gifts, purchases and rupee timing are not modeled; playtest this pack instead.")
		rooms[room.id] = room
		if not room.get("stairs",[]).is_empty(): has_stairs = true
		if int(room.spawn[0])%8 != 0 or posmod(int(room.spawn[1])-5,8) != 0: return report("unsupported",room.id + ": solver requires the dungeon's eight-pixel spawn grid.")
		for y in range(11):
			for x in range(16):
				var tile: String = room.tiles[y][x]
				if tile == "~": return report("unsupported",room.id + ": water traversal is not modeled; no solvability claim.")
				if (x<2 or x>13 or y<2 or y>8) and tile != "#": return report("unsupported",room.id + ": use the standard two-tile wall frame; no doorway-bypass claim.")
		for pickup in room.pickups: pickups.append({"room":room.id,"pickup":pickup})
		for edge in room.connections:
			var link: Dictionary = room.connections[edge]
			var a: String = room.id+"/"+edge
			var b: String = link.target+"/"+Pack.OPPOSITE[edge]
			if not door_ids.has(a):
				var id := door_ids.size()/2
				door_ids[a] = id;door_ids[b] = id
	if pickups.size()>48 or door_ids.size()/2>48: return report("unsupported","This solver supports at most 48 pickups and 48 door pairs.")
	for goal in pack.goals:
		for i in range(pickups.size()):
			if pickups[i].room == goal.room and pickups[i].pickup.id == goal.pickup: goal_mask |= 1<<i
	var bomb_supply := 0
	for item in pack.starting_items:
		if item == "bombs": bomb_supply += 4
	for entry in pickups:
		if entry.pickup.item == "bombs": bomb_supply += 4
	if bomb_supply>8: return report("unsupported","More than eight supplied bombs needs pickup-capacity/timing search; no solvability claim.")
	var first: Dictionary = rooms[pack.start_room]
	var initial := {"room":pack.start_room,"at":Vector2i(int(first.spawn[0]),int(first.spawn[1])),"keys":0,"bombs":0,"items":0,"collected":0,"opened":0,"pushed":false,"portal_armed":true,"parent":-1,"action":"Start in " + String(pack.start_room),"event":{"type":"start","room":pack.start_room}}
	for item in pack.starting_items: take(initial,item)
	var states: Array = [initial]
	var pending: Array[int] = [0]
	var seen: Dictionary = {signature(initial):true}
	while not pending.is_empty():
		if states.size() >= state_limit:
			var limited := report("limit","State limit reached; result is inconclusive, not a solvability proof.",states.size())
			limited.limit_kind = "states";return limited
		if Time.get_ticks_msec()-started > time_limit_ms:
			var limited := report("limit","Time limit reached; result is inconclusive, not a solvability proof.",states.size())
			limited.limit_kind = "time";return limited
		var current_index: int = pending.pop_back()
		var state: Dictionary = states[current_index]
		reached[state.room] = true
		if (state.collected & goal_mask) == goal_mask:
			var steps: Array = []
			var events: Array = []
			var at := current_index
			while at >= 0: steps.push_front(states[at].action);events.push_front(states[at].event);at = states[at].parent
			return report("solved","Found a route collecting every objective under the stated model.",states.size(),steps,events)
		var room: Dictionary = rooms[state.room]
		var view := reachable(state)
		var cells: Dictionary = view.cells
		if cells.is_empty() and view.stairs.is_empty(): reason(state.room + ": entry position is blocked"); continue
		var actions: Array = []
		# Arrival on a stair is a one-time choice of departure direction. Do
		# not merge regions on opposite sides after the portal has rearmed.
		if not state.portal_armed and active_stair_at(room,state.at,state.pushed):
			for direction in DIRS.values():
				if not can_walk_step(room,state.at,direction,door_mask(state,view.monsters_clear),state.pushed): continue
				var next: Dictionary = state.duplicate()
				next.at = state.at+direction*8;next.portal_armed = true
				next.event = {"type":"walk","room":state.room,"at":[next.at.x,next.at.y]}
				next.action = "Step off arrival stairs in " + String(state.room)
				actions.append(next)
		for stair in view.stairs:
			var next: Dictionary = state.duplicate()
			next.event = {"type":"stairs","room":state.room,"stairs":stair.id,"target":stair.target,"at":[Pack.stair_position(stair).x,Pack.stair_position(stair).y]}
			next.room = stair.target
			next.at = Vector2i(int(stair.target_position[0]),int(stair.target_position[1]))
			next.pushed = false
			next.portal_armed = not on_any_stair(rooms[next.room],next.at)
			next.action = "Take stairs %s/%s -> %s" % [state.room,stair.id,stair.target]
			actions.append(next)
		if room.has("secret") and not state.pushed:
			var secret: Dictionary = room.secret
			var cell := Vector2i(int(secret.cell[0]),int(secret.cell[1]))
			var direction: Vector2i = DIRS[secret.direction]
			var approach := (cell-direction)*16+Vector2i(0,-3)
			if view.monsters_clear and cells.has(approach):
				var next: Dictionary = state.duplicate()
				next.pushed = true;next.at = approach
				next.portal_armed = state.portal_armed or approach != state.at
				next.event = {"type":"push","room":state.room,"direction":secret.direction,"at":[approach.x,approach.y]}
				next.action = "Push block %s %s" % [state.room,secret.direction]
				actions.append(next)
			else: reason(state.room+": block requires a cleared room and reachable push approach")
		for i in range(pickups.size()):
			if pickups[i].room != state.room or (state.collected & (1<<i)) != 0: continue
			var pickup: Dictionary = pickups[i].pickup
			if pickup.get("requires_secret",false) and not state.pushed: reason(state.room+"/"+pickup.id+": requires pushing the block");continue
			if pickup.get("requires_clear",false) and not view.clear: reason(state.room+"/"+pickup.id+": requires clearing the room with a sword");continue
			if not near(cells,pickup.position): reason(state.room+"/"+pickup.id+": pickup lies outside the entry's walkable region");continue
			var next: Dictionary = state.duplicate()
			next.event = {"type":"pickup","room":state.room,"pickup":pickup.id}
			if has_stairs:
				next.at = collect_position(cells,pickup.position)
				next.event.at = [next.at.x,next.at.y]
				next.portal_armed = state.portal_armed or next.at != state.at
			next.collected |= 1<<i
			take(next,pickup.item)
			next.action = "Collect %s/%s (%s); keys=%d, bombs=%d" % [state.room,pickup.id,pickup.item,next.keys,next.bombs]
			actions.append(next)
		for edge in Pack.EDGES:
			if not room.connections.has(edge): continue
			var link: Dictionary = room.connections[edge]
			if link.kind == "wall": continue
			if not requires_met(state,link): reason("%s/%s requires %s" % [state.room,edge,", ".join(link.get("requires",[]))]);continue
			var door_id: int = door_ids[state.room+"/"+edge]
			if link.kind in ["key","bombable"] and (state.opened & (1<<door_id)) == 0:
				if not cells.has(HOT[edge]): reason(state.room+"/"+edge+": cannot reach door approach");continue
				if link.kind == "key" and state.keys == 0 and not owns(state,"magic_key"): reason(state.room+"/"+edge+": no key");continue
				if link.kind == "bombable" and state.bombs == 0: reason(state.room+"/"+edge+": no bomb");continue
				var next: Dictionary = state.duplicate()
				next.event = {"type":"door","room":state.room,"edge":edge,"kind":link.kind}
				if has_stairs:
					next.at = HOT[edge]
					next.portal_armed = state.portal_armed or next.at != state.at
				next.opened |= 1<<door_id
				if link.kind == "key" and not owns(state,"magic_key"): next.keys -= 1
				if link.kind == "bombable": next.bombs -= 1
				next.action = "Open %s door %s/%s; keys=%d, bombs=%d" % [link.kind,state.room,edge,next.keys,next.bombs]
				actions.append(next)
				continue
			if not cells.has(EDGE[edge]): reason(state.room+"/"+edge+": doorway blocked or shutter cannot open");continue
			var target: Dictionary = rooms[link.target]
			var reverse: String = Pack.OPPOSITE[edge]
			var distance := 16 if link.kind in ["open","key"] else 32
			var arrival: Vector2i = EDGE[reverse]+DIRS[edge]*distance
			var next: Dictionary = state.duplicate()
			next.event = {"type":"travel","room":state.room,"edge":edge,"target":target.id}
			next.room = target.id
			next.pushed = false
			next.portal_armed = true
			next.at = arrival
			var transit_mask := door_mask(next,false) | (1 << Pack.EDGES.find(reverse))
			var safe := true
			for step in range(distance+1):
				if not standing(target,EDGE[reverse]+DIRS[edge]*step,transit_mask): safe = false;break
			if not safe: reason(target.id+": forced doorway walk is blocked");continue
			next.action = "Travel %s %s -> %s" % [state.room,edge,target.id]
			actions.append(next)
		# Depth-first, pickup-first exploration; visited state includes consumables,
		# collected pickups and both sides of every opened door. No farming.
		for i in range(actions.size()-1,-1,-1):
			var next: Dictionary = actions[i]
			var key := signature(next)
			if seen.has(key): continue
			seen[key] = true
			next.parent = current_index
			states.append(next)
			pending.append(states.size()-1)
	return report("blocked","No route collects every objective under the stated model.",states.size())
func signature(state: Dictionary) -> String:
	return "%s/%d/%d/%d/%d/%d/%d/%d/%s/%s" % [state.room,state.at.x,state.at.y,state.keys,state.bombs,state.items,state.collected,state.opened,state.pushed,state.portal_armed]
func take(state: Dictionary, item: String) -> void:
	match item:
		"key": state.keys = mini(255,state.keys+1)
		"bombs": state.bombs = mini(8,state.bombs+4)
		_:
			if item in Pack.REQUIRED_ITEMS: state.items |= item_bit(item)
func door_mask(state: Dictionary, cleared: bool) -> int:
	var room: Dictionary = rooms[state.room]
	var mask := 0
	for i in range(Pack.EDGES.size()):
		var edge: String = Pack.EDGES[i]
		if not room.connections.has(edge): continue
		var link: Dictionary = room.connections[edge]
		if not requires_met(state,link): continue
		var passable: bool = link.kind in ["open","false"]
		if link.kind in ["key","bombable"]: passable = (state.opened & (1<<int(door_ids[state.room+"/"+edge]))) != 0
		if link.kind == "shutter": passable = (room.shutter_trigger == 1 and cleared) or (room.shutter_trigger == 4 and state.pushed)
		if passable: mask |= 1<<i
	return mask
func reachable(state: Dictionary) -> Dictionary:
	var mask := door_mask(state,false)
	var cells := flood(rooms[state.room],state.at,mask,state.pushed,state.portal_armed)
	var clear: bool = rooms[state.room].enemies.is_empty()
	if not clear and owns(state,"wooden_sword"):
		clear = rooms[state.room].enemies.all(func(enemy): return near(cells,enemy.position))
	if clear: cells = flood(rooms[state.room],state.at,door_mask(state,true),state.pushed,state.portal_armed)
	var final_mask := door_mask(state,clear)
	return {"cells":cells,"stairs":reachable_stairs(rooms[state.room],state,cells,final_mask),"monsters_clear":clear,"clear":clear and (rooms[state.room].shutter_trigger != 4 or state.pushed)}
func near(cells: Dictionary, at: Array) -> bool:
	for y in range(-3,158,8):
		if absi(y-int(at[1])) > 8: continue
		for x in range(0,241,8):
			if absi(x-int(at[0])) <= 8 and cells.has(Vector2i(x,y)): return true
	return false
func blocked(room: Dictionary, pixel: Vector2i, mask: int, pushed: bool = false) -> bool:
	if pixel.x<0 or pixel.x>=256 or pixel.y<0 or pixel.y>=176: return true
	if room.has("secret"):
		var block := Vector2i(int(room.secret.cell[0]),int(room.secret.cell[1]))
		if pushed: block += DIRS[room.secret.direction]
		if Vector2i(pixel.x/16,pixel.y/16) == block: return true
	var cell := (pixel.y/16)*16+pixel.x/16
	for i in range(Pack.EDGES.size()):
		if (mask & (1<<i)) == 0: continue
		var edge: String = Pack.EDGES[i]
		var part: int = CELLS[edge].find(cell)
		if part < 0: continue
		var bit := ((pixel.x%16)/8)*2 + (pixel.y%16)/8
		return (int(COLLISION[edge][part]) & (1<<bit)) != 0
	return room.tiles[pixel.y/16][pixel.x/16] != "."
func standing(room: Dictionary, at: Vector2i, mask: int, pushed: bool = false) -> bool:
	return at.x>=0 and at.x<=240 and at.y>=-3 and at.y<=157 and not blocked(room,at+Vector2i(0,11),mask,pushed) and not blocked(room,at+Vector2i(8,11),mask,pushed)
func flood(room: Dictionary, origin: Vector2i, mask: int, pushed: bool = false, portal_armed: bool = true) -> Dictionary:
	var key := "%s/%d/%d/%d/%s/%s" % [room.id,origin.x,origin.y,mask,pushed,portal_armed]
	if cache.has(key): return cache[key]
	var cells: Dictionary = {}
	if (portal_armed and active_stair_at(room,origin,pushed)) or not standing(room,origin,mask,pushed): cache[key] = cells;return cells
	var pending: Array[Vector2i] = [origin]
	cells[origin] = true
	if not portal_armed and active_stair_at(room,origin,pushed): cache[key] = cells;return cells
	var cursor := 0
	while cursor<pending.size():
		var at: Vector2i = pending[cursor];cursor += 1
		for direction in DIRS.values():
			var candidate: Vector2i = at+direction*8
			if active_stair_at(room,candidate,pushed) or cells.has(candidate) or not standing(room,candidate,mask,pushed): continue
			if can_walk_step(room,at,direction,mask,pushed): cells[candidate] = true;pending.append(candidate)
	cache[key] = cells
	return cells
static func format_report(result: Dictionary) -> String:
	var text := String(result.status).to_upper() + ": " + String(result.message) + "\nStates: " + str(result.states) + "\n\n" + String(result.assumptions)
	if not result.steps.is_empty(): text += "\n\nWitness route:\n" + "\n".join(result.steps)
	elif not result.blockers.is_empty(): text += "\n\nObserved blockers:\n" + "\n".join(result.blockers)
	return text

func on_any_stair(room: Dictionary, at: Vector2i) -> bool:
	return room.get("stairs",[]).any(func(stair): return Pack.stair_position(stair) == at)
func active_stair_at(room: Dictionary, at: Vector2i, pushed: bool) -> bool:
	return room.get("stairs",[]).any(func(stair): return Pack.stair_position(stair) == at and (not stair.get("requires_secret",false) or pushed))
func collect_position(cells: Dictionary, at: Array) -> Vector2i:
	for cell in cells:
		if absi(cell.x-int(at[0]))<=8 and absi(cell.y-int(at[1]))<=8: return cell
	return Vector2i(-999,-999)
func reachable_stairs(room: Dictionary, state: Dictionary, cells: Dictionary, mask: int) -> Array:
	var result: Array = []
	for stair in room.get("stairs",[]):
		if stair.get("requires_secret",false) and not state.pushed: continue
		var at := Pack.stair_position(stair)
		if state.portal_armed and state.at == at: result.append(stair);return result
		if not standing(room,at,mask,state.pushed): continue
		for direction in DIRS.values():
			var approach: Vector2i = at-direction*8
			if not cells.has(approach): continue
			if can_walk_step(room,approach,direction,mask,state.pushed): result.append(stair);break
	return result

func can_walk_step(room: Dictionary, at: Vector2i, direction: Vector2i, mask: int, pushed: bool) -> bool:
	var probe := at+Vector2i(0,11)
	if direction.x != 0: probe.x += 16 if direction.x>0 else -8
	else: probe.y += 8 if direction.y>0 else -8
	if blocked(room,probe,mask,pushed) or (direction.y != 0 and blocked(room,probe+Vector2i(8,0),mask,pushed)): return false
	for i in range(1,9):
		if not standing(room,at+direction*i,mask,pushed): return false
	return true
