class_name CaveSession
extends RefCounted
## One visit to a cave resident (Z_01 InitCave and UpdateCavePerson). Results
## that outlive the visit are recorded in GameState under room_id/taken.
const WARE_X: Array[int] = [88, 120, 152]
const WARE_Y := 88
## Tile $25: a space shown without typing time. Text resources mark it with an
## underscore, since Godot 4.6 decodes U+00A0 in .tres files as U+FFFD.
const UNTIMED_SPACE := "_"
const TAKEN := &"taken"
var cave: Resource
var room_id: StringName
## prices, text, shop, hide, hint_text, idle, letter, or gone.
var phase := "prices"
var timer := 0
var text := ""
var shown := 0
var halting := true
var show_prices := false
var price_mark := "X"
var prices: PackedInt32Array = PackedInt32Array([0, 0, 0])
var signs: PackedStringArray = PackedStringArray(["", "", ""])
var taken: Array[bool] = [false, false, false]
var chosen := -1
var money_amounts: PackedInt32Array = PackedInt32Array()

func start(definition: Resource, room: StringName, state: RefCounted, random: RefCounted) -> void:
	cave = definition
	room_id = room
	text = cave.text
	show_prices = cave.show_prices
	for i in range(3):
		var ware: Resource = cave.wares[i]
		prices[i] = ware.price if ware != null else 0
		signs[i] = "-" if cave.negative_prices else ""
	if cave.triforce_gate and range(1, 9).all(func(level: int) -> bool: return state.has_level_item(&"triforce", level)):
		phase = "gone"
		halting = false
		state.flags["shutters/" + String(room_id)] = true
		return
	if cave.remember and state.has_collected(room_id, TAKEN):
		phase = "gone"
		halting = false
		return
	if cave.money_game:
		choose_money_amounts(random)
	if cave.requires_letter and state.item_value(&"letter") < 2:
		phase = "letter"
		halting = false

## InitCave: a permutation chosen with rising probability, a random 10 or 40
## loss, a fixed 10 loss, and a random 20 or 50 win.
func choose_money_amounts(random: RefCounted) -> void:
	const PERMUTATIONS := [0, 1, 2, 1, 2, 0, 2, 0, 1, 0, 2, 1, 2, 1, 0, 1, 0, 2]
	const ENDS := [2, 5, 8, 11, 14, 17]
	var reference := 0xFF
	var index := 6
	while index > 0 and not reference < random.at(1):
		reference -= 0x2B
		index -= 1
	var last: int = ENDS[mini(index, 5)]
	var amounts := [40 if random.at(2) & 1 else 10, 10, 50 if random.at(2) & 2 else 20]
	money_amounts = PackedInt32Array([0, 0, 0])
	for i in range(3):
		money_amounts[i] = amounts[PERMUTATIONS[last - 2 + i]]

func person_visible() -> bool:
	return phase not in ["gone"]

func wares_visible() -> bool:
	return cave.show_items and phase not in ["gone", "letter"]

func ware_visible(index: int) -> bool:
	return wares_visible() and cave.wares[index] != null and not taken[index]

func blocks_player() -> bool:
	return halting

func visible_text() -> String:
	if phase in ["gone", "letter", "prices"]: return ""
	return text.substr(0, shown).replace(UNTIMED_SPACE, " ")

## State 4 skips drawing the person and wares every other frame.
func flicker_hidden(frame: int) -> bool:
	return phase in ["hide","feeding"] and frame % 2 != 0

func tick(world: Node) -> void:
	timer = maxi(0, timer - 1)
	match phase:
		"prices":
			timer = 10 if show_prices else 0
			phase = "text"
		"text", "hint_text":
			type_text(world)
		"waiting_bait":
			try_feed(world)
		"feeding":
			if timer==0:
				world.item_objects=world.item_objects.filter(func(o:RefCounted)->bool:return o.kind!="bait")
				world.state.slots[&"bait"]=0
				world.ensure_selected_item()
				phase="gone"
				halting=false
		"shop":
			shop(world)
		"wager":
			resolve_money_game(world)
		"hide":
			if timer == 0: phase = "gone"

func try_feed(world: Node) -> bool:
	if phase!="waiting_bait" or not world.item_objects.any(func(o:RefCounted)->bool:return o.active and o.kind=="bait"):return false
	world.state.collected[world.state.pickup_key(room_id,TAKEN)]=true
	world.audio.play(&"secret")
	phase="feeding"
	timer=cave.feeding_ticks
	text=""
	shown=0
	halting=true
	return true

func type_text(world: Node) -> void:
	if timer > 0: return
	timer = world.room.dialogue_character_ticks
	while shown < text.length() and text[shown] == UNTIMED_SPACE: shown += 1
	if shown < text.length() and text[shown] != "\n":
		world.audio.play(&"text")
	shown += 1
	while shown < text.length() and text[shown] in [UNTIMED_SPACE, "\n"]: shown += 1
	if shown >= text.length():
		halting = false
		phase = "waiting_bait" if cave.accepts_bait else "shop" if phase == "text" else "idle"

func shop(world: Node) -> void:
	var state: RefCounted = world.state
	if not cave.choose:
		phase = "idle"
		if cave.door_charge > 0:
			state.rupees_to_subtract += cave.door_charge
			state.collected[state.pickup_key(room_id, TAKEN)] = true
		return
	if state.rupees_to_subtract != 0: return
	var at: Vector2i = world.player.pixel_position()
	var index := -1
	for i in range(2, -1, -1):
		if cave.wares[i] != null and not taken[i] and at.x == WARE_X[i] and absi(at.y - WARE_Y) < 6:
			index = i
			break
	if index < 0: return
	chosen = index
	var ware: Resource = cave.wares[index]
	if cave.hint or cave.money_game or cave.gift_money:
		if cave.hint:
			if state.rupees < ware.price: return
			state.rupees_to_subtract += ware.price
			text = ware.hint if not ware.hint.is_empty() else text
			shown = 0
			show_prices = false
			phase = "hint_text"
		elif cave.gift_money:
			price_mark = ""
			show_prices = true
			world.audio.play(&"key")
			state.collected[state.pickup_key(room_id, TAKEN)] = true
			state.rupees_to_add += prices[1]
			phase = "idle"
		else:
			phase = "wager"
			resolve_money_game(world)
		return
	if cave.pay:
		if state.rupees < ware.price: return
		state.rupees_to_subtract += ware.price
	# The original posts the price before checking hearts; no paid cave needs hearts.
	if cave.heart_requirement > 0 and state.max_health / 2 < cave.heart_requirement: return
	state.collected[state.pickup_key(room_id, TAKEN)] = true
	taken[index] = true
	if cave.lifts_wares: world.take_cave_item(ware.item)
	else:
		state.take_item(ware.item)
		world.audio.play(&"key")
	show_prices = false
	text = ""
	shown = 0
	timer = 0x40
	phase = "hide"

## State 5 waits, with the choice made, until Link can cover a loss.
func resolve_money_game(world: Node) -> void:
	var state: RefCounted = world.state
	if state.rupees < 10: return
	world.audio.play(&"key")
	prices = money_amounts.duplicate()
	show_prices = true
	for i in range(3):
		signs[i] = "+" if prices[i] in [20, 50] else "-"
	if prices[chosen] in [20, 50]: state.rupees_to_add += prices[chosen]
	else: state.rupees_to_subtract += prices[chosen]
	phase = "idle"

## B button use of the letter: the potion shop opens.
func show_letter(world: Node) -> bool:
	if phase != "letter": return false
	world.state.slots[&"letter"] = 2
	world.audio.play(&"secret")
	if world.state.item_value(&"potion") == 0 or world.state.selected_item == &"letter":
		world.state.selected_item = &"potion"
	phase = "prices"
	return true

func price_text(index: int) -> String:
	if prices[index] == 0: return ""
	return signs[index] + str(prices[index])
