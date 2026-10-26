class_name Submenu
extends RefCounted
## The pause submenu (Z_05 UpdateMenu). Start sets it up over a few frames,
## then the inventory scrolls down 3 pixels a frame, pushing the status bar and
## play area down; the game waits meanwhile. Left and right move the cursor
## through the B items (UpdateSubmenuSelection); Start scrolls it away again.
## `offset` is how far the play area is pushed down: 0 closed, 176 open.
const HEIGHT := 176
const SCROLL_SPEED := 3
## UpdateMenuOW/UW_JumpTable: frames before scrolling (the overworld also
## prepares its Triforce rows first), then MenuState 2's one-pixel step.
const SETUP_FRAMES_OVERWORLD := 6
const SETUP_FRAMES_UNDERWORLD := 5
## Item slots $00-$08 (SelectedItemSlot): slot 0 stands for either boomerang,
## slot 3 is the bow and is never selected, slot 7 holds the potion or letter.
const SLOT_ITEMS: Array[StringName] = [&"boomerang", &"bombs", &"arrows", &"", &"candle", &"recorder", &"bait", &"potion", &"rod"]
## SubmenuItemXs for slots 0-$0F, SubmenuCursorXs for 0-8; rows sit at Y $36,
## $46 (selectable) and $1E (owned equipment).
const ITEM_X: Array[int] = [0x80, 0x98, 0xAC, 0xB4, 0xC8, 0x80, 0x98, 0xB0, 0xC8, 0x80, 0x94, 0xA0, 0xB0, 0xC0, 0xCC, 0xB0]
const CURSOR_X: Array[int] = [0x80, 0x98, 0xB0, 0xB0, 0xC8, 0x80, 0x98, 0xB0, 0xC8]
const EQUIPMENT: Array[StringName] = [&"raft", &"book", &"ring", &"ladder", &"magic_key", &"bracelet"]
const SELECTED_BOX := Vector2i(0x40, 0x36)
var phase := "closed"
var setup := 0
var offset := 0
var slot := 0
## [EF]: the last input direction, so holding a direction moves only once.
var last_input := 0
## Set on frames where the selection moved, for the "selection changed" tune.
var moved := false

func is_open() -> bool:
	return phase != "closed"

func active() -> bool:
	return phase == "active"

func open(underworld: bool, state: RefCounted) -> void:
	phase = "opening"
	setup = SETUP_FRAMES_UNDERWORLD if underworld else SETUP_FRAMES_OVERWORLD
	offset = 0
	slot = slot_for(state.selected_item)
	last_input = 0

## One frame. `start` is a fresh Start press; `direction` is the held direction.
func tick(state: RefCounted, start: bool, direction: Vector2i) -> void:
	moved = false
	match phase:
		"opening":
			if setup > 0:
				setup -= 1
				# UpdateMenuCommon1 moves the view a pixel before scrolling starts.
				if setup == 0: offset = 2
				return
			offset = mini(HEIGHT, offset + SCROLL_SPEED)
			if offset == HEIGHT: phase = "active"
		"active":
			select(state, direction)
			if start: phase = "closing"
		"closing":
			offset -= SCROLL_SPEED
			if offset <= 0:
				offset = 0
				phase = "closed"

## Z_05 UpdateSubmenuSelection: right steps forward, left back, each only when
## the input changes; any other input just keeps an occupied slot selected.
func select(state: RefCounted, direction: Vector2i) -> void:
	var input := 1 if direction == Vector2i.RIGHT else 2 if direction == Vector2i.LEFT else 4 if direction == Vector2i.DOWN else 8 if direction == Vector2i.UP else 0
	if input == last_input:
		state.selected_item = item_at(state, slot)
		return
	last_input = input
	var before := slot
	slot = find_occupied(state, slot, input & 3)
	moved = slot != before and item_at(state, slot) != &""
	state.selected_item = item_at(state, slot)

## Z_05 FindAndSelectOccupiedItemSlot and Cycle9InDirection: check nine slots in
## the given direction (1 forward, 2 back, 0 the current one again), skipping
## the bow; with nothing found, slot 0 is selected.
static func find_occupied(state: RefCounted, start: int, way: int) -> int:
	var index := start
	for i in range(9):
		if way == 1: index = (index + 1) % 9
		elif way == 2: index = (index + 8) % 9
		if index != 3 and item_at(state, index) != &"": return index
	return 0

## What a slot holds now: arrows need the bow; slot 7 falls back to the letter.
static func item_at(state: RefCounted, index: int) -> StringName:
	match index:
		2: return &"arrows" if state.item_value(&"arrows") > 0 and state.item_value(&"bow") > 0 else &""
		3: return &""
		7:
			if state.item_value(&"potion") > 0: return &"potion"
			return &"letter" if state.item_value(&"letter") > 0 else &""
	var name: StringName = SLOT_ITEMS[index]
	return name if state.item_value(name) > 0 else &""

static func slot_for(item: StringName) -> int:
	if item == &"letter": return 7
	if item == &"": return 0
	return maxi(0, SLOT_ITEMS.find(item))

## Menu-local position of a selectable slot's item sprite (sprite Y + 2, since
## the backdrop starts a pixel above NT2 row 8 and sprites draw a line low).
static func item_position(index: int) -> Vector2i:
	return Vector2i(ITEM_X[index], (0x36 if index < 5 else 0x46) + 2)

static func cursor_position(index: int) -> Vector2i:
	return Vector2i(CURSOR_X[index], (0x36 if index < 5 else 0x46) + 2)

static func equipment_position(index: int) -> Vector2i:
	return Vector2i(ITEM_X[9 + index], 0x1E + 2)
