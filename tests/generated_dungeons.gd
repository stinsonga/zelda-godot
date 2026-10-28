extends SceneTree
const Pack = preload("res://editor/shared/room_pack.gd")
const Templates = preload("res://editor/shared/dungeon_templates.gd")
const Generator = preload("res://editor/shared/dungeon_generator.gd")
const Solver = preload("res://editor/shared/progression_solver.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
const DIRS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
const EDGE := {"up":Vector2i(120,-3),"down":Vector2i(120,157),"left":Vector2i(0,77),"right":Vector2i(240,77)}
const HOT := {"up":Vector2i(120,29),"down":Vector2i(120,125),"left":Vector2i(32,77),"right":Vector2i(208,77)}
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("Native generation checks timed out");quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1;push_error(message)
func tick(direction: Vector2i = Vector2i.ZERO) -> void:
	world.combat.player_invulnerability = 100000
	world.simulate_tick(direction)
func prepare_room() -> void:
	for i in range(65): tick()
	# The solver explicitly assumes these sword-vulnerable encounters are won.
	check(world.state.item_value(&"sword")>0,"Generated loadout supplies the assumed sword")
	for actor in world.combat.enemies:
		actor.invulnerability = 0
		if actor.health>0: actor.receive_hit(actor.health,Vector2i.RIGHT,"sword")
	for i in range(65): tick()
func path_to(predicate: Callable) -> Array:
	var start: Vector2i = world.player.pixel_position()
	var parents: Dictionary = {start:Vector2i(-999,-999)}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor<queue.size():
		var at: Vector2i = queue[cursor];cursor += 1
		if predicate.call(at):
			var path: Array = []
			while at != start: path.push_front(at);at = parents[at]
			return path
		for direction in DIRS.values():
			# Item/door input may stop Link between grid points. First finish
			# that axis using real movement, then resume eight-pixel routing.
			var stride := 8
			if posmod(at.x,8) != 0:
				if direction.y != 0: continue
				stride = 8-posmod(at.x,8) if direction.x>0 else posmod(at.x,8)
			elif posmod(at.y-5,8) != 0:
				if direction.x != 0: continue
				stride = 8-posmod(at.y-5,8) if direction.y>0 else posmod(at.y-5,8)
			var candidate: Vector2i = at+direction*stride
			if parents.has(candidate) or not world.room.movement_bounds.has_point(candidate): continue
			if not world.can_enter_segment(at,direction): continue
			var safe := true
			for i in range(1,stride+1):
				if not world.can_occupy(at+direction*i): safe = false;break
			if safe: parents[candidate] = at;queue.append(candidate)
	return [Vector2i(-999,-999)]
func walk_to(predicate: Callable) -> bool:
	var path := path_to(predicate)
	if path == [Vector2i(-999,-999)]: return false
	for waypoint in path:
		for i in range(30):
			var at: Vector2i = world.player.pixel_position()
			if at == waypoint: break
			var delta: Vector2i = waypoint-at
			tick(Vector2i(signi(delta.x),0) if delta.x != 0 else Vector2i(0,signi(delta.y)))
		if world.player.pixel_position() != waypoint: return false
	return predicate.call(world.player.pixel_position())
func replay(pack: Dictionary, proof: Dictionary) -> void:
	var compiled := Adapter.compile(pack)
	check(compiled.errors.is_empty(),"Generated pack compiles through existing engine")
	world = preload("res://scenes/main.tscn").instantiate()
	world.use_imported_world = false;world.world_definition = compiled.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	prepare_room()
	for event in proof.events:
		if event.type == "start": continue
		check(String(world.room.id) == event.room,"Native witness is in expected room for "+str(event))
		if String(world.room.id) != event.room: break
		if event.type == "pickup":
			if world.state.has_collected(StringName(event.room),StringName(event.pickup)): continue
			var pickup: Resource
			for item in world.room.pickups:
				if String(item.id) == event.pickup: pickup = item;break
			check(pickup != null,"Witness pickup exists")
			if pickup == null: break
			var at: Vector2i = pickup.position
			check(walk_to(func(p): return absi(p.x-at.x)<=8 and absi(p.y-at.y)<=8),"Native geometry reaches witness pickup "+event.pickup)
			for i in range(4): tick()
			check(world.state.has_collected(StringName(event.room),StringName(event.pickup)),"Native pickup collected "+event.pickup)
		elif event.type == "push":
			var approach := Vector2i(int(event.at[0]),int(event.at[1]))
			check(walk_to(func(p): return p == approach),"Native geometry reaches the block's push approach")
			for i in range(16): tick(DIRS[event.direction])
			for i in range(40): tick()
			check(world.secrets.revealed and world.secrets.pushed,"Native block push reveals the secret")
			var original: Vector2i = world.room.secret.cell*16+Vector2i(0,8)
			check(not world.is_blocked(original) and world.is_blocked(original+DIRS[event.direction]*16),"Native pushed collision agrees with solver")
		elif event.type == "door":
			var hotspot: Vector2i = HOT[event.edge]
			check(walk_to(func(p): return p == hotspot),"Native geometry reaches door approach")
			if event.kind == "key":
				tick(DIRS[event.edge])
				for i in range(20): tick()
			else:
				var bombs_before: int = world.state.item_value(&"bombs")
				world.player.facing = DIRS[event.edge]
				world.state.selected_item = &"bombs"
				world.combat.player_invulnerability = 100000
				world.simulate_tick(Vector2i.ZERO,false,true)
				for i in range(160): tick()
				check(world.state.item_value(&"bombs") == bombs_before-1,"Native bombable door spends an actual bomb")
			check(world.state.flags.get("door/"+event.room+"/"+event.edge,false),"Native door opened from witness")
		else:
			var edge: Vector2i = EDGE[event.edge]
			check(walk_to(func(p): return p == edge),"Native geometry reaches exit "+event.room+"/"+event.edge)
			for i in range(100):
				tick(DIRS[event.edge])
				if String(world.room.id) == event.target and world.entry_walk_remaining == 0 and world.settle_ticks == 0: break
			check(String(world.room.id) == event.target,"Native room transition follows solver")
			prepare_room()
	for goal in pack.goals: check(world.state.has_collected(StringName(goal.room),StringName(goal.pickup)),"All solver goals collected natively")
	check(world.state.flags.get("authored/complete",false),"Native authored completion flag records the objective set")
	world.combat.encounter_room = null;world.free()
func run() -> void:
	for recipe in [[42,8,"blue_candle"],[7,6,"bow"],[91,8,"magic_key"]]:
		var generated := Generator.new().generate(Templates.defaults(),recipe[0],recipe[1],recipe[2])
		check(generated.errors.is_empty(),"Recipe generates")
		if generated.errors.is_empty(): replay(generated.pack,generated.proof)
	# Generic item gates must block even manually painted-away doorway walls.
	var pack := Pack.fresh();Pack.upgrade(pack);pack.starting_items = []
	var end := Pack.room("end");end.map_position = [0,-1]
	pack.rooms[0].connections.up = {"target":"end","kind":"open","requires":["bow"]}
	end.connections.down = {"target":"entry","kind":"open","requires":["bow"]};pack.rooms.append(end)
	var result := Adapter.compile(pack)
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = result.world
	root.add_child(world);world.set_physics_process(false);world.scroll_transitions = false
	check(world.state.item_value(&"sword") == 0,"Version 2 empty loadout does not receive a free preview sword")
	check(not world.door_passable(world.room,world.room.doors[0]),"Item requirement enforced in native door state")
	world.room.tiles = world.room.tiles.replace("################\n################","#######..#######\n#######..#######")
	world.overrides = world.compute_overrides(world.room)
	check(world.is_blocked(Vector2i(120,8)),"Item gate cannot be erased by painting floor under its door cells")
	world.player.place(Vector2i(120,-3));world.try_exit(Vector2i.UP)
	check(world.room.id == &"entry","Missing item cannot bypass gate at room edge")
	world.state.take_item(load("res://content/items/bow.tres"))
	world.try_exit(Vector2i.UP)
	check(world.room.id == &"end","Owning required item permits transition")
	world.combat.encounter_room = null;world.free()
	pack.rooms[0].connections.up.kind = "key"
	pack.rooms[1].connections.down.kind = "key"
	pack.starting_items = ["key"]
	result = Adapter.compile(pack)
	world = preload("res://scenes/main.tscn").instantiate();world.use_imported_world = false;world.world_definition = result.world
	root.add_child(world);world.set_physics_process(false)
	world.player.place(Vector2i(120,29))
	world.try_doors(Vector2i.UP)
	check(world.state.item_value(&"keys") == 1,"Unmet item gate does not prematurely spend a key")
	world.state.take_item(load("res://content/items/bow.tres"))
	world.try_doors(Vector2i.UP)
	check(world.state.item_value(&"keys") == 0,"Satisfied item gate lets the native key lock spend exactly one key")
	world.combat.encounter_room = null;world.free()
	print("Generated native replay checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
