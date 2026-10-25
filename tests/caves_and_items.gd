extends SceneTree
## Caves, items, equipment, and overworld secrets. Native checks need no ROM;
## imported checks run when res://imported exists.
var failures := 0
const Lab = preload("res://scenes/item_lab.tscn")
const Main = preload("res://scenes/main.tscn")
const State = preload("res://scripts/game_state.gd")
const Cave = preload("res://scripts/cave_definition.gd")
const Ware = preload("res://scripts/cave_ware.gd")
const Session = preload("res://scripts/cave_session.gd")
const Room = preload("res://scripts/room_definition.gd")
const Secret = preload("res://scripts/secret_definition.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const ItemObject = preload("res://scripts/item_object.gd")
const Saves = preload("res://scripts/save_store.gd")
var temporary := ""

class FixedRandom:
	extends RefCounted
	var values := {}
	func at(index: int) -> int: return values.get(index, 0)

func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Cave and item suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func item(name: String) -> Resource:
	return load("res://content/items/" + name + ".tres")

func ticks(world: Node, count: int, direction: Vector2i = Vector2i.ZERO) -> void:
	for i in range(count): world.simulate_tick(direction)

func lab() -> Node:
	var world = Lab.instantiate()
	world.save_store = Saves.new(temporary)
	root.add_child(world)
	world.set_physics_process(false)
	return world

## Enter a cave and wait out the entry walk and greeting.
func visit(world: Node, id: StringName) -> void:
	world.enter_room(world.rooms[id], Vector2i(112, 157), Vector2i.UP, 48)
	for i in range(600):
		if world.entry_walk_remaining == 0 and not world.cave_session.blocks_player(): break
		world.simulate_tick(Vector2i.ZERO)

func run() -> void:
	temporary = "user://cave_tests_%d" % Time.get_ticks_usec()
	check_item_effects()
	check_money_game_permutations()
	check_shop()
	check_gifts_and_charges()
	check_hints_and_money_game()
	check_letter()
	check_bombs()
	check_candle()
	check_push()
	check_saves()
	check_validation()
	if ResourceLoader.exists("res://imported/world.tres"):
		check_imported()
	for name in DirAccess.get_files_at(temporary): DirAccess.remove_absolute(temporary.path_join(name))
	DirAccess.remove_absolute(temporary)
	print("Cave and item checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func check_item_effects() -> void:
	var state = State.new()
	for i in range(3): state.take_item(item("bombs"))
	check(state.item_value(&"bombs") == 8, "Bombs must add four and stop at the bomb capacity")
	state.slots[&"bombs"] = 1
	state.take_item(item("big_bombs"))
	check(state.item_value(&"bombs") == 8 and state.selected_item == &"bombs", "Custom bomb satchel must use the bomb slot and capacity")
	state.take_item(item("blue_potion"))
	state.take_item(item("blue_potion"))
	state.take_item(item("blue_potion"))
	check(state.item_value(&"potion") == 2, "Blue potions add one dose up to two")
	check(not state.take_item(item("red_potion")), "A red potion must not replace two doses")
	state.slots[&"potion"] = 1
	check(state.take_item(item("red_potion")) and state.item_value(&"potion") == 2, "A red potion must upgrade one dose")
	state.take_item(item("heart_container"))
	check(state.max_health == 8 and state.health == 8, "A heart container must add a container and a heart")
	state.take_item(item("blue_ring"))
	state.take_damage(2)
	check(state.health_units == 8 * 128 - 128 and state.health == 7, "The blue ring must halve damage")
	state.take_item(item("wooden_sword"))
	state.take_item(item("white_sword"))
	state.take_item(item("wooden_sword"))
	check(state.equipped_weapon == item("white_sword") and state.equipped_weapon.damage == 2, "A better sword must equip, a worse one must not")
	state.take_item(item("rupee_purse"))
	check(state.rupees_to_add == 100 and state.rupees == 0, "Custom rupee items add through the counter")
	for frame in range(200): state.tick_rupees(frame)
	check(state.rupees == 100 and state.rupees_settled(), "Rupees must count one every other frame")
	state.rupees_to_subtract = 150
	for frame in range(400): state.tick_rupees(frame)
	check(state.rupees == 0 and state.rupees_to_subtract == 0, "Debits must stop at zero rupees")

func check_money_game_permutations() -> void:
	var session = Session.new()
	var random := FixedRandom.new()
	random.values = {1: 0x00, 2: 0x03}
	session.choose_money_amounts(random)
	check(session.money_amounts == PackedInt32Array([40, 10, 50]), "Low random byte must keep the identity permutation")
	random.values = {1: 0xE0, 2: 0x00}
	session.choose_money_amounts(random)
	check(session.money_amounts == PackedInt32Array([10, 10, 20]), "High random byte must select the last permutation")

func check_shop() -> void:
	var world = lab()
	visit(world, &"lab_shop")
	var session = world.cave_session
	check(session.phase == "shop" and session.wares_visible() and session.show_prices, "Shop must show wares and prices after its greeting")
	world.player.place(Vector2i(88, 85))
	ticks(world, 4)
	check(world.state.item_value(&"magic_shield") == 0 and session.phase == "shop", "A shop must refuse a customer without enough rupees")
	world.state.rupees = 50
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.item_value(&"magic_shield") == 1 and world.lift_remaining == 128 and world.state.rupees_to_subtract == 30, "Buying must take the item, lift it, and post the price")
	check(session.phase == "hide" and not session.ware_visible(0) and session.ware_visible(1), "The sold ware disappears while the shopkeeper flickers")
	ticks(world, 130)
	check(session.phase == "gone" and world.state.rupees == 20, "The shopkeeper must leave after 64 frames and the price must count down")
	visit(world, &"lab_shop")
	check(world.cave_session.phase == "shop" and world.cave_session.ware_visible(0), "Shops must reset when Link returns")
	world.free()

func custom_cave(fields: Dictionary, wares: Array) -> Resource:
	var cave = Cave.new()
	cave.id = &"custom"
	cave.text = "HELLO"
	for i in range(3):
		if wares[i] != null:
			var ware = Ware.new()
			ware.item = wares[i][0]
			ware.price = wares[i][1]
			cave.wares[i] = ware
	for key in fields: cave.set(key, fields[key])
	return cave

func custom_room(world: Node, cave: Resource) -> Resource:
	var room: Resource = world.rooms[&"lab_vault"].duplicate()
	room.id = StringName("custom_" + str(cave.get_instance_id()))
	room.cave = cave
	world.rooms[room.id] = room
	return room

func check_gifts_and_charges() -> void:
	var world = lab()
	world.state.max_health = 4
	world.state.health = 4
	visit(world, &"lab_vault")
	world.player.place(Vector2i(120, 85))
	ticks(world, 3)
	check(world.state.max_health == 4 and world.cave_session.phase == "shop", "A heart requirement must refuse a gift")
	world.state.max_health = 6
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.max_health == 8 and world.state.has_collected(&"lab_vault", &"taken"), "Meeting the requirement must grant the remembered gift")
	visit(world, &"lab_vault")
	check(world.cave_session.phase == "gone" and not world.dialogue_visible(), "A remembered gift cave must be empty on return")
	var gift = custom_room(world, custom_cave({"choose": true, "show_items": true, "remember": true, "gift_money": true}, [null, [item("rupee"), 30], null]))
	world.enter_room(gift, Vector2i(120, 85), Vector2i.UP)
	ticks(world, 60)
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.rupees + world.state.rupees_to_add == 30 and world.cave_session.price_mark == "" and world.cave_session.show_prices, "Secret money must show its amount without a price mark")
	world.enter_room(gift, Vector2i(120, 85), Vector2i.UP)
	check(world.cave_session.phase == "gone", "Secret money is given once")
	world.state.rupees = 15
	world.state.rupees_to_add = 0
	var charge = custom_room(world, custom_cave({"remember": true, "door_charge": 20}, [null, null, null]))
	world.enter_room(charge, Vector2i(120, 109), Vector2i.UP)
	ticks(world, 120)
	check(world.state.rupees == 0 and world.cave_session.phase == "idle", "Door repair must charge twenty rupees, stopping at zero")
	world.enter_room(charge, Vector2i(120, 109), Vector2i.UP)
	check(world.cave_session.phase == "gone", "The door repair charge is collected once")
	world.free()

func check_hints_and_money_game() -> void:
	var world = lab()
	visit(world, &"lab_hint")
	world.state.rupees = 15
	world.player.place(Vector2i(120, 85))
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.rupees_to_subtract == 10 and world.cave_session.phase == "hint_text" and not world.cave_session.show_prices, "Paying a hint must post the price and hide prices")
	ticks(world, 400)
	check(world.cave_session.phase == "idle" and world.cave_session.visible_text() == "BOMB THE WALL\nBY THE SHOP.", "The chosen hint must be typed in full")
	visit(world, &"lab_money")
	var session = world.cave_session
	world.state.rupees = 5
	world.player.place(Vector2i(152, 85))
	world.simulate_tick(Vector2i.ZERO)
	check(session.phase == "wager" and session.chosen == 2, "A wager must wait until Link can cover a loss")
	world.player.place(Vector2i(88, 85))
	world.state.rupees = 60
	world.simulate_tick(Vector2i.ZERO)
	var amount: int = session.money_amounts[2]
	var won := amount in [20, 50]
	check(session.phase == "idle" and session.chosen == 2 and (world.state.rupees_to_add == amount if won else world.state.rupees_to_subtract == amount), "The original choice must win or lose its revealed amount")
	check(session.price_text(2) == ("+" if won else "-") + str(amount), "Revealed amounts must carry their signs")
	world.free()

func check_letter() -> void:
	var world = lab()
	var cave = custom_cave({"choose": true, "pay": true, "show_items": true, "show_prices": true, "requires_letter": true},
		[[item("blue_potion"), 40], null, [item("red_potion"), 68]])
	var shop = custom_room(world, cave)
	world.state.take_item(item("letter"))
	world.enter_room(shop, Vector2i(120, 109), Vector2i.UP)
	world.simulate_tick(Vector2i.ZERO)
	check(world.cave_session.phase == "letter" and not world.cave_session.blocks_player() and not world.cave_session.wares_visible(), "The potion shop waits for the letter")
	check(world.state.selected_item == &"letter" and world.use_item(), "Showing the letter must be a B-button action")
	check(world.state.item_value(&"letter") == 2 and world.state.selected_item == &"potion", "The shown letter must be marked used and select the potion")
	world.enter_room(shop, Vector2i(120, 109), Vector2i.UP)
	check(world.cave_session.phase == "prices", "A used letter opens the shop on later visits")
	world.free()

func enemy_at(world: Node, at: Vector2i) -> RefCounted:
	var spawn = Spawn.new()
	spawn.id = &"target"
	spawn.enemy = preload("res://content/enemies/stout_octorok.tres")
	spawn.position = at
	spawn.spawn_ticks = 0
	var actor = Actor.new()
	actor.setup(spawn)
	world.combat.enemies.append(actor)
	return actor

func check_bombs() -> void:
	var world = lab()
	world.state.take_item(item("bombs"))
	world.player.place(Vector2i(192, 29))
	world.player.facing = Vector2i.UP
	check(world.use_item() and world.item_objects.size() == 1 and world.state.item_value(&"bombs") == 3, "Using bombs must place one ahead and spend it")
	check(world.item_objects[0].position == Vector2i(192, 13) and world.audio.history.has(&"bomb_drop"), "Bombs land 16 pixels ahead with the set sound")
	ticks(world, 16)
	check(not world.use_item(), "A second bomb must wait for the first to detonate")
	ticks(world, 34)
	check(world.item_objects[0].detonating() and world.secrets.revealed and world.state.flags.get("secret/item_lab", false), "A detonating bomb must open the cracked wall")
	ticks(world, 36)
	check(world.item_objects.is_empty(), "Bomb smoke must clear after 48 + 24 + 12 frames")
	ticks(world, 4, Vector2i.UP)
	ticks(world, 20, Vector2i.UP)
	check(world.room.id == &"lab_vault", "The revealed wall must lead into its cave")
	world.enter_room(world.rooms[&"item_lab"], Vector2i(120, 125), Vector2i.UP)
	check(world.secrets.revealed and world.overrides.has(Vector2i(12, 1)), "A bombed wall must stay open")
	var actor = enemy_at(world, Vector2i(120, 93))
	var health: int = actor.health
	world.player.place(Vector2i(120, 125))
	world.player.facing = Vector2i.UP
	world.use_item()
	world.item_objects[0].position = Vector2i(120, 100)
	ticks(world, 50)
	check(actor.health == maxi(0, health - 4), "Bomb blasts deal four damage within 24 pixels")
	world.free()

func check_candle() -> void:
	var world = lab()
	world.state.take_item(item("blue_candle"))
	world.enter_room(world.rooms[&"lab_grove"], Vector2i(128, 77), Vector2i.UP)
	world.player.facing = Vector2i.UP
	check(world.use_item() and world.item_objects[0].position == Vector2i(128, 61), "The candle must start a fire 16 pixels ahead")
	ticks(world, 32)
	check(world.item_objects[0].position == Vector2i(128, 45) and world.item_objects[0].stage == 2, "Fire walks 16 pixels at half a pixel per frame")
	check(not world.use_item(), "The blue candle burns once per room")
	ticks(world, 64)
	check(world.secrets.revealed and world.item_objects.is_empty(), "A fire burning out on a tree must reveal stairs")
	ticks(world, 30, Vector2i.UP)
	check(world.room.id == &"lab_hint", "Burned-tree stairs must lead into their cave")
	world.enter_room(world.rooms[&"lab_grove"], Vector2i(128, 77), Vector2i.UP)
	check(world.secrets.revealed and world.use_item(), "The candle refreshes in a new room and the tree stays burned")
	world.item_objects[0].position = world.player.pixel_position()
	var before: int = world.state.health
	world.simulate_tick(Vector2i.ZERO)
	check(world.state.health == before - 1, "Link's own fire must hurt him")
	var shot = preload("res://scripts/rock_projectile.gd").new()
	shot.kind = "sword"
	shot.blockable = false
	check(not world.combat.shield_blocks(world, shot), "The small shield cannot block sword shots")
	world.state.take_item(item("magic_shield"))
	check(world.combat.shield_blocks(world, shot), "The magical shield must block sword shots")
	world.free()

func check_push() -> void:
	var world = lab()
	world.enter_room(world.rooms[&"lab_graves"], Vector2i(128, 93), Vector2i.UP)
	world.simulate_tick(Vector2i.UP)
	check(world.secrets.pushed and world.player.pixel_position().y == 91, "Pressing up within 16 pixels of a gravestone must push it")
	for i in range(8):
		world.simulate_tick(Vector2i.UP)
		check(world.player.pixel_position().y + 3 - world.secrets.object_position().y >= 12, "A sliding gravestone must hold Link back")
	ticks(world, 24)
	check(world.secrets.revealed and world.overrides.get(Vector2i(8, 4), [0, 0, "none"])[2] == "object", "The gravestone must slide one square and reveal stairs")
	check(not world.state.flags.has("secret/lab_graves"), "Gravestone stairs are not remembered")
	for i in range(20):
		world.simulate_tick(Vector2i.UP)
		if world.room.id != &"lab_graves": break
	check(world.room.id == &"lab_money", "Gravestone stairs must lead into their cave")
	world.enter_room(world.rooms[&"lab_graves"], Vector2i(16, 77), Vector2i.RIGHT)
	check(not world.secrets.revealed and world.is_blocked(Vector2i(130, 82)), "Gravestones return when Link comes back")
	var rock = world.rooms[&"lab_graves"].duplicate()
	rock.id = &"rock_room"
	rock.secret = rock.secret.duplicate()
	rock.secret.trigger = "bracelet_push"
	world.rooms[rock.id] = rock
	world.enter_room(rock, Vector2i(128, 85), Vector2i.UP)
	ticks(world, 4, Vector2i.UP)
	check(not world.secrets.pushed, "Rocks need the power bracelet")
	world.state.slots[&"bracelet"] = 1
	ticks(world, 4, Vector2i.UP)
	check(world.secrets.pushed, "The power bracelet must allow pushing rocks")
	world.free()

func check_saves() -> void:
	var world = lab()
	world.state.take_item(item("bombs"))
	world.state.take_item(item("blue_candle"))
	world.state.take_item(item("magic_shield"))
	world.state.flags["secret/item_lab"] = true
	world.cycle_item()
	check(world.available_items() == [&"bombs", &"candle"] and world.state.selected_item == &"candle", "B items must follow the original submenu order")
	world.state.rupees_to_add = 5
	check(not world.save_game(), "Saving must wait for the rupee counter")
	world.state.rupees_to_add = 0
	check(world.save_game(), "Inventory must be saveable")
	world.free()
	world = lab()
	check(world.load_game(), "Inventory must load")
	check(world.state.item_value(&"bombs") == 4 and world.state.item_value(&"candle") == 1 and world.state.item_value(&"magic_shield") == 1, "Item slots must survive a save")
	check(world.state.selected_item == &"candle" and world.state.max_bombs == 8, "B selection and bomb capacity must survive a save")
	world.enter_room(world.rooms[&"item_lab"], Vector2i(192, 29), Vector2i.UP)
	ticks(world, 12, Vector2i.UP)
	check(world.room.id == &"lab_vault", "Saved secrets must keep entrances open")
	var data: Dictionary = world.snapshot()
	data.slots = {"bombs": 0}
	check(not world.save_store.validate(data, world.world_id).ok, "Empty item slots must be rejected")
	data = world.snapshot()
	data.selected_item = "rod"
	check(not world.save_store.validate(data, world.world_id).ok, "A selected item must be held")
	world.free()

func check_validation() -> void:
	var cave = custom_cave({"hint": true}, [null, null, null])
	check(not cave.validation_errors().is_empty(), "Hints without choosing must be rejected")
	cave = custom_cave({}, [null, null, null])
	cave.wares.resize(1)
	check(not cave.validation_errors().is_empty(), "Caves need three ware slots")
	var secret = Secret.new()
	secret.cell = Vector2i(16, 2)
	check(not secret.validation_errors().is_empty(), "Secrets must lie inside the room")
	var room = Room.new()
	room.id = &"bad"
	var rows := PackedStringArray()
	for y in range(11): rows.append("................")
	room.tiles = "\n".join(rows)
	var portal = preload("res://scripts/portal_definition.gd").new()
	portal.area = Rect2i(0, 0, 1, 1)
	portal.target_room = &"x"
	portal.requires_secret = true
	room.portals.append(portal)
	check(room.validation_errors().has("Secret portal requires a room secret"), "Secret portals need a secret")

func check_imported() -> void:
	var world = Main.instantiate()
	world.save_store = Saves.new(temporary)
	root.add_child(world)
	world.set_physics_process(false)
	var caves := 0
	for id in world.rooms:
		var definition: Resource = world.rooms[id]
		if definition.cave == null: continue
		caves += 1
		var exit: Resource = definition.portals[0]
		var source: Resource = world.rooms[exit.target_room]
		var entries: Array = source.portals.filter(func(portal: Resource) -> bool: return portal.target_room == id)
		check(entries.size() == 1 and String(id) == "cave_" + String(source.id).substr(3), "Cave " + String(id) + " must pair with one overworld entrance")
	check(caves == 59, "All first-quest overworld caves must import")
	var sword: Resource = world.rooms[&"cave_0a"].cave
	check(sword.heart_requirement == 5 and sword.wares[1].item.id == &"white_sword" and sword.remember, "White sword cave must need five hearts")
	check(world.rooms[&"cave_21"].cave.heart_requirement == 12, "Magical sword cave must need twelve hearts")
	var shop: Resource = world.rooms[&"cave_25"].cave
	check(shop.pay and shop.wares.map(func(w: Resource) -> int: return w.price) == [130, 20, 80], "Shop prices must come from the ROM")
	check(world.rooms[&"cave_1a"].cave.hint and world.rooms[&"cave_1a"].cave.wares[2].hint.contains("GO UP,UP,"), "Hint caves must carry their paid hints")
	check(world.rooms[&"cave_0d"].cave.requires_letter and world.rooms[&"cave_0e"].cave.wares[1].item.id == &"letter", "The letter and potion shop must import")
	var shortcut: Array = world.rooms[&"cave_1d"].portals.map(func(portal: Resource) -> String: return String(portal.target_room))
	check(shortcut == ["ow_1d", "ow_23", "ow_49", "ow_79"], "Shortcut stairs must lead around the cellar list")
	# Bomb a wall, burn a tree, and push a gravestone in original rooms.
	world.state.take_item(item("bombs"))
	world.enter_room(world.rooms[&"ow_0d"], Vector2i(144, 29), Vector2i.UP)
	world.player.facing = Vector2i.UP
	world.use_item()
	ticks(world, 50)
	check(world.secrets.revealed and world.state.flags.get("secret/ow_0d", false), "Room 0D's cracked wall must open")
	ticks(world, 30, Vector2i.UP)
	check(world.room.id == &"cave_0d" and world.cave_session.phase == "letter", "The opened wall must lead to the potion shop")
	ticks(world, 120, Vector2i.DOWN)
	check(world.room.id == &"ow_0d", "Leaving the potion shop must return to room 0D")
	world.enter_room(world.rooms[&"ow_28"], Vector2i(208, 125), Vector2i.UP)
	var fire = ItemObject.fire(Vector2i(208, 96), Vector2i.UP)
	fire.stage = 2
	fire.timer = 2
	world.item_objects.append(fire)
	world.simulate_tick(Vector2i.ZERO)
	check(world.secrets.revealed and world.overrides.has(Vector2i(13, 6)), "Room 28's tree must burn into stairs")
	world.enter_room(world.rooms[&"ow_21"], Vector2i(144, 93), Vector2i.UP)
	check(world.secrets.try_push(world, Vector2i.UP), "Room 21's gravestone must accept a push from below")
	ticks(world, 33)
	check(world.secrets.revealed and not world.state.flags.has("secret/ow_21"), "The gravestone must reveal temporary stairs")
	world.free()
