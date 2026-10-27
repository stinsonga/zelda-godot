extends SceneTree
const RaftItem = preload("res://content/items/raft.tres")
const Store = preload("res://scripts/save_store.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Raft suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func ticks(direction: Vector2i, count: int) -> void:
	for i in range(count): world.simulate_tick(direction)
func run() -> void:
	world = preload("res://scenes/raft_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.scroll_transitions = false
	world.save_store = Store.new(OS.get_temp_dir().path_join("zelda-raft-%d" % OS.get_process_id()))
	for room in world.room_resources: check(room.validation_errors().is_empty(), "Authored raft room validates")
	world.player.place(Vector2i(96,61))
	ticks(Vector2i.UP,20)
	check(not world.raft.active and world.player.pixel_position().y == 53, "Without raft Link cannot leave dock over water")
	world.state.take_item(RaftItem)
	world.player.place(Vector2i(88,61))
	ticks(Vector2i.ZERO,1)
	check(not world.raft.active, "Dock needs exact horizontal alignment")
	world.player.place(Vector2i(96,61))
	ticks(Vector2i.ZERO,1)
	check(world.raft.active and world.raft.outbound and world.player.facing == Vector2i.UP, "Aligned dock automatically starts outbound ride without directional input")
	check(world.audio.history.back() == &"secret", "Dock activation plays secret cue")
	var cues: int = world.audio.history.count(&"secret")
	var actor = preload("res://scripts/enemy_actor.gd").new()
	actor.definition = preload("res://scripts/enemy_definition.gd").new()
	actor.definition.contact_effect = "curse_sword"
	world.combat.touch_player(world,actor)
	check(not world.state.sword_cursed, "Halted raft rider ignores monster contact effects")
	var shot = preload("res://scripts/rock_projectile.gd").new()
	shot.kind = "fireball"
	shot.subposition = world.player.subposition
	shot.direction = Vector2i.RIGHT
	shot.velocity = Vector2i(256,0)
	shot.age = 16
	world.combat.tick_fireball(world,shot)
	check(shot.alive and shot.position().x == 97 and world.state.health == world.state.max_health, "Existing shots move past halted raft rider")

	check(not world.save_game(), "Cannot checkpoint a transient raft ride")
	world.simulate_tick(Vector2i.RIGHT,true,true)
	check(world.player.pixel_position() == Vector2i(96,60) and not world.sword.active() and world.item_objects.is_empty(), "Raft moves one pixel and ignores movement and attack/item input")
	ticks(Vector2i.DOWN,62)
	check(world.player.pixel_position() == Vector2i(96,-2) and world.raft.active, "Outbound travel lasts exactly 64 moving ticks")
	check(world.audio.history.count(&"secret") == cues, "Ride does not replay the boarding cue")
	ticks(Vector2i.ZERO,1)
	check(world.room.id == &"raft_lab_island" and world.player.pixel_position() == Vector2i(96,157) and not world.raft.active, "Outbound ride enters island at its southern edge")
	ticks(Vector2i.UP,32)
	check(world.state.has_collected(&"raft_lab_island",&"island_treasure"), "Island treasure is reachable")
	world.player.place(Vector2i(96,157))
	world.player.facing = Vector2i.DOWN
	ticks(Vector2i.DOWN,1)
	check(world.room.id == &"raft_lab_dock" and world.raft.active and not world.raft.outbound and world.player.pixel_position() == Vector2i(96,-3), "Returning island exit admits raft onto blocked mainland water")
	ticks(Vector2i.LEFT,65)
	check(world.raft.active and world.player.pixel_position() == Vector2i(96,62), "Inbound ride holds input until the exact landing")
	ticks(Vector2i.UP,1)
	check(not world.raft.active and world.player.pixel_position() == Vector2i(96,63), "Landing stops two pixels below dock to avoid immediate reboarding")
	check(world.save_game() and world.load_game() and world.state.item_value(&"raft") == 1 and not world.raft.active, "Landed checkpoint keeps raft ownership without a travel state")
	ticks(Vector2i.DOWN,8)
	check(world.player.pixel_position().y > 63, "Link can leave the landing despite its two-pixel grid offset")
	check_scroll()
	check_editing()
	check_horizontal()
	world.free()
	check_original()
	print("Raft checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
func finish_scroll() -> void:
	for i in range(300):
		if world.transition == null: return
		ticks(Vector2i.ZERO,1)

func check_scroll() -> void:
	world.scroll_transitions = true
	world.enter_room(world.rooms[&"raft_lab_dock"],Vector2i(96,61),Vector2i.UP)
	ticks(Vector2i.ZERO,65)
	check(world.transition != null and world.room.id == &"raft_lab_dock", "Outbound uses normal screen scrolling")
	# Overworld scrolls take the original's frames before and after the scroll.
	finish_scroll()
	check(world.transition == null and world.room.id == &"raft_lab_island", "Island scroll completes")
	world.player.place(Vector2i(96,157))
	world.player.facing = Vector2i.DOWN
	ticks(Vector2i.DOWN,2)
	check(world.transition != null, "Returning to water uses normal scrolling")
	finish_scroll()
	check(world.transition == null and world.raft.active and not world.raft.outbound, "Arrival starts inbound ride after scrolling")
	# One more frame: InitMode5Play's settle frame comes before the inbound ride.
	ticks(Vector2i.ZERO,67)
	check(world.player.pixel_position() == Vector2i(96,63) and not world.raft.active, "Scrolled return lands correctly")
func check_editing() -> void:
	world.scroll_transitions = false
	var room = world.rooms[&"raft_lab_dock"].duplicate(true)
	room.raft_route.speed_pixels_per_tick = 3
	world.enter_room(room,Vector2i(96,61),Vector2i.UP)
	ticks(Vector2i.ZERO,23)
	check(world.room.id == &"raft_lab_island", "Custom raft speed clamps at boundary without overshooting")
	var bad = room.duplicate(true)
	bad.raft_route.edge_position.x += 8
	check(not bad.validation_errors().is_empty(), "Diagonal raft route fails validation")
	bad = room.duplicate(true)
	bad.raft_route.speed_pixels_per_tick = 0
	check(not bad.validation_errors().is_empty(), "Invalid raft speed fails validation")
func check_horizontal() -> void:
	var dock = world.rooms[&"raft_lab_dock"].duplicate(true)
	var island = world.rooms[&"raft_lab_island"].duplicate(true)
	dock.raft_route.dock_position = Vector2i(64,77)
	dock.raft_route.edge_position = Vector2i(0,77)
	dock.raft_route.landing_position = Vector2i(66,77)
	dock.exits.assign({"left":"raft_lab_island"})
	island.exits.assign({"right":"raft_lab_dock"})
	island.tiles = "\n".join(PackedStringArray(["................","................","................","................","................","................","................","................","................","................","................"]))
	dock.tiles = island.tiles.replace("................", "~~~~............")
	world.rooms[&"raft_lab_dock"] = dock
	world.rooms[&"raft_lab_island"] = island
	check(dock.validation_errors().is_empty(), "Horizontal authored route validates")
	world.enter_room(dock,Vector2i(64,77),Vector2i.LEFT)
	ticks(Vector2i.ZERO,65)
	check(world.room.id == &"raft_lab_island" and world.player.pixel_position() == Vector2i(240,77), "Horizontal route reaches neighboring room")
	world.player.facing = Vector2i.RIGHT
	ticks(Vector2i.RIGHT,1)
	check(world.raft.active and world.room.id == &"raft_lab_dock", "Horizontal return admits rider into blocked water")
	ticks(Vector2i.ZERO,66)
	check(not world.raft.active and world.player.pixel_position() == Vector2i(66,77), "Horizontal route lands on configured bank")

func check_original() -> void:
	if not ResourceLoader.exists("res://imported/deployed_raft.png"): return
	var original = preload("res://scenes/main.tscn").instantiate()
	root.add_child(original)
	original.set_physics_process(false)
	original.scroll_transitions = false
	original.state.take_item(RaftItem)
	for pair in [[&"ow_3f",&"ow_2f",96],[&"ow_55",&"ow_45",128]]:
		var mainland: Resource = original.rooms[pair[0]]
		check(mainland.raft_route != null and mainland.raft_route.dock_position == Vector2i(pair[2],61), "Original dock imports correct lane")
		original.enter_room(mainland,Vector2i(pair[2],61),Vector2i.UP)
		original.combat.enemies.clear()
		for i in range(65): original.simulate_tick(Vector2i.ZERO)
		check(original.room.id == pair[1] and original.player.pixel_position() == Vector2i(pair[2],157), "Original route reaches its island")
		original.combat.enemies.clear()
		for i in range(100):
			if original.room.id != pair[1]: break
			original.simulate_tick(Vector2i.UP)
		check(original.room.id == (&"cave_2f" if pair[1] == &"ow_2f" else &"l4_71"), "Original island entrance is reachable after landing")
		original.enter_room(original.rooms[pair[1]],Vector2i(pair[2],157),Vector2i.DOWN)
		original.combat.enemies.clear()
		original.player.facing = Vector2i.DOWN
		original.simulate_tick(Vector2i.DOWN)
		check(original.room.id == pair[0] and original.raft.active and not original.raft.outbound, "Original island permits return onto mainland water")
		for i in range(66): original.simulate_tick(Vector2i.ZERO)
		check(not original.raft.active and original.player.pixel_position() == Vector2i(pair[2],63), "Original mainland return lands at source position")
	original.free()
