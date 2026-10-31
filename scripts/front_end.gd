extends Node2D
## The original's front end around the game (Z_02 modes 0, 1, $E, and $F): the
## title and story, the file menu, name registration, and elimination. The
## World plays a chosen file and reports death and its Continue/Save/Retry
## choice back here.
## Keys: arrows; Enter is Start, Tab is Select, Z is A, X is B.
const Files = preload("res://scripts/save_files.gd")
const Title = preload("res://scripts/title_demo.gd")
## The imported second quest; without it, second-quest files play the first.
const SECOND_QUEST_PATH := "res://imported/world_q2.tres"
## Z_02 Mode1CursorSpriteYs: three files, then REGISTER and ELIMINATION.
const FILE_CURSOR_YS := [0x5C, 0x74, 0x8C, 0xA8, 0xB8]
## Z_02 ModeEandFSlotCursorYs: three files, then END.
const SLOT_CURSOR_YS := [0x2F, 0x47, 0x5F, 0x77]
## Z_02 ModeE_CharMap: the character board, eleven to a row.
const CHAR_MAP := [0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14,
	0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
	0x20, 0x21, 0x22, 0x23, 0x62, 0x63, 0x28, 0x29, 0x2A, 0x2B, 0x2C,
	0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x24]
## Ring colors for each file's Link (Z_02 LinkColors): none, blue, red.
const RING_TINTS := [Color.WHITE, Color("8fb4ff"), Color("ff8a70")]
const TILE_CHARS := {0x24: " ", 0x28: ",", 0x29: "!", 0x2A: "'", 0x2B: "&", 0x2C: ".", 0x62: "-", 0x63: "."}

@export var files_directory := "user://files"
## An authored world (from a game bundle) to play instead of the original;
## it skips the title and keeps to its own files.
var pack_world: Resource
var files: RefCounted
var world: Node
## The title and story, when imported; without them the game opens on the files.
var title: RefCounted
var screen: NesScreen
## "title", "files", "register", "eliminate", or "playing".
var mode := "files"
var cursor := 0
var playing_slot := -1
## Registration: names being typed, the board cursor, and the name cursor.
var names: Array = []
var board := 0
var name_cursor := 0
var repeat_direction := Vector2i.ZERO
var repeat_timer := 0
var repeat_count := 0
var frame := 0
var held: Array[Vector2i] = []
var pressed := {"start": false, "select": false, "a": false, "b": false}

func _ready() -> void:
	files = Files.new(files_directory)
	make_world(pack_world)
	screen = NesScreen.new()
	add_child(screen)
	var title_data: Dictionary = Title.load_data() if pack_world == null else {}
	if title_data.is_empty(): show_files()
	else:
		title = Title.new(title_data, screen, world.audio)
		show_title()

func _input(event: InputEvent) -> void:
	if mode == "playing" or not event is InputEventKey or event.echo: return
	var direction := Vector2i.ZERO
	match event.physical_keycode:
		KEY_UP, KEY_W: direction = Vector2i.UP
		KEY_DOWN, KEY_S: direction = Vector2i.DOWN
		KEY_LEFT, KEY_A: direction = Vector2i.LEFT
		KEY_RIGHT, KEY_D: direction = Vector2i.RIGHT
		KEY_ENTER: if event.pressed: pressed.start = true
		KEY_TAB: if event.pressed: pressed.select = true
		KEY_Z, KEY_SPACE: if event.pressed: pressed.a = true
		KEY_X, KEY_SHIFT: if event.pressed: pressed.b = true
	if direction != Vector2i.ZERO:
		held.erase(direction)
		if event.pressed: held.append(direction)

func _physics_process(_delta: float) -> void:
	if mode == "playing": return
	tick(Vector2i.ZERO if held.is_empty() else held.back(), pressed.start, pressed.select, pressed.a, pressed.b)
	for key in pressed: pressed[key] = false
	queue_redraw()
	screen.queue_redraw()

## One frame of the menus; tests drive this directly.
func tick(direction: Vector2i, start: bool, select: bool, a: bool = false, b: bool = false) -> void:
	frame += 1
	match mode:
		"title": if title.tick(start): show_files()
		"files": tick_files(start, select)
		"register": tick_register(direction, start, select, a, b)
		"eliminate": tick_eliminate(start, select)

func make_world(definition: Resource) -> void:
	world = preload("res://scenes/main.tscn").instantiate()
	world.world_definition = definition
	world.menus_enabled = true
	add_child(world)
	world.visible = false
	world.set_physics_process(false)
	world.menu_choice.connect(_on_menu_choice)
	world.died.connect(func() -> void: files.add_death(playing_slot))

## Z_06 InitMode2_Sub0 picks the level blocks by the file's quest: here, the world.
func use_quest(quest: int) -> void:
	if pack_world != null: return
	var wanted := quest if quest == 2 and ResourceLoader.exists(SECOND_QUEST_PATH) else 1
	if world.quest == wanted: return
	world.free()
	make_world(load(SECOND_QUEST_PATH) if wanted == 2 else null)
	move_child(screen, -1)

func show_title() -> void:
	mode = "title"
	screen.visible = true
	world.visible = false
	world.set_physics_process(false)

func show_files() -> void:
	mode = "files"
	screen.visible = false
	world.visible = false
	world.set_physics_process(false)
	world.audio.silence()
	# InitMode1_Sub6: the cursor starts at the first file in use.
	cursor = 3
	for slot in range(Files.COUNT):
		if files.active(slot):
			cursor = slot
			break

## Z_02 UpdateMode1Menu: Select moves to the next file in use (or the two
## options), Start opens it.
func tick_files(start: bool, select: bool) -> void:
	if select:
		for step in range(5):
			cursor = (cursor + 1) % 5
			if cursor >= 3 or files.active(cursor): break
		world.audio.play(&"rupee")
	if not start: return
	match cursor:
		3: show_names("register")
		4: show_names("eliminate")
		_: play(cursor)

func play(slot: int) -> void:
	if not files.active(slot): return
	playing_slot = slot
	use_quest(files.meta[slot].quest)
	world.file_info = {"quest": files.meta[slot].quest, "name": files.meta[slot].name, "deaths": files.meta[slot].deaths}
	if not world.begin_file(files.read_state(slot, world.world_id, world.previous_world_ids)): return
	mode = "playing"
	world.visible = true
	world.set_physics_process(true)

func _on_menu_choice(choice: String) -> void:
	if choice == "save": files.write_state(playing_slot, world.snapshot(), world.world_id)
	# SwitchProfileToSecondQuest, then mode $D saves: three hearts and nothing
	# else, which a new second-quest game starts with anyway.
	if choice == "second_quest":
		files.erase_state(playing_slot)
		files.meta[playing_slot].merge({"quest": 2, "max_health": 6, "health": 6, "ring": 0}, true)
		files.save_meta()
	show_files()

func show_names(next_mode: String) -> void:
	mode = next_mode
	names = []
	for slot in range(Files.COUNT):
		names.append(files.meta[slot].name.duplicate() if files.active(slot) else filled(Files.BLANK, Files.NAME_LENGTH))
	board = 0
	name_cursor = 0
	repeat_timer = 0
	repeat_direction = Vector2i.ZERO
	cursor = 0
	if mode == "register":
		# InitModeEandF_Full: start at the first free file, else END.
		cursor = 3
		for slot in range(Files.COUNT):
			if not files.active(slot):
				cursor = slot
				break

## Z_02 UpdateModeERegister: Select moves among free files and END; arrows
## move the board cursor (again after $10 frames, then every 8); A writes the
## character and B skips ahead; Start on END creates the named files.
func tick_register(direction: Vector2i, start: bool, select: bool, a: bool, b: bool) -> void:
	if start and cursor == 3:
		for slot in range(Files.COUNT):
			if not files.active(slot) and names[slot].any(func(code: int) -> bool: return code != Files.BLANK):
				files.create(slot, names[slot])
		show_files()
		return
	if select:
		for step in range(4):
			cursor = (cursor + 1) % 4
			if cursor == 3 or not files.active(cursor): break
		name_cursor = 0
		world.audio.play(&"rupee")
	if cursor == 3: return
	move_board(direction)
	if a:
		names[cursor][name_cursor] = CHAR_MAP[board]
		world.audio.play(&"bomb_drop")
	if a or b: name_cursor = (name_cursor + 1) % Files.NAME_LENGTH

func move_board(direction: Vector2i) -> void:
	if direction == Vector2i.ZERO or direction != repeat_direction:
		repeat_direction = direction
		repeat_timer = 0
		repeat_count = 0
		if direction == Vector2i.ZERO: return
	if repeat_timer > 0:
		repeat_timer -= 1
		return
	repeat_timer = 0x10 if repeat_count == 0 else 8
	repeat_count += 1
	board = posmod(board + direction.x + direction.y * 11, CHAR_MAP.size())

## Z_02 UpdateModeFElimination: Start erases the file under the cursor, or on
## END moves on to registration.
func tick_eliminate(start: bool, select: bool) -> void:
	if select:
		cursor = (cursor + 1) % 4
		world.audio.play(&"rupee")
	if not start: return
	if cursor == 3:
		show_names("register")
		return
	if files.active(cursor):
		files.erase(cursor)
		names[cursor] = filled(Files.BLANK, Files.NAME_LENGTH)
		world.audio.play(&"player_hurt")

func _draw() -> void:
	if mode == "playing" or mode == "title": return
	draw_rect(Rect2(0, 0, 256, 240), Color.BLACK)
	if mode == "files": draw_files()
	else: draw_names()

## Z_06 Mode1TileTransferBuf and Z_02 Mode1SlotLineTransferBuf.
func draw_files() -> void:
	draw_codes([0x62, 0x24, 0x1C, 0x24, 0x0E, 0x24, 0x15, 0x24, 0x0E, 0x24, 0x0C, 0x24, 0x1D, 0x24, 0x62], 8, 5)
	draw_box(3, 8, 28, 25)
	draw_codes([0x24, 0x17, 0x0A, 0x16, 0x0E, 0x24], 10, 8)
	draw_codes([0x24, 0x15, 0x12, 0x0F, 0x0E, 0x24], 19, 8)
	draw_codes(text_codes("REGISTER YOUR NAME"), 6, 21)
	draw_codes(text_codes("ELIMINATION MODE"), 6, 23)
	for slot in range(Files.COUNT):
		if not files.active(slot): continue
		var entry: Dictionary = files.meta[slot]
		draw_codes(entry.name, 9, 11 + slot * 3)
		draw_text_codes(str(entry.deaths).lpad(3), 9, 12 + slot * 3)
		draw_hearts(entry.max_health / 2, entry.health, 18, 11 + slot * 3)
		draw_link(Vector2(0x30, 0x58 + slot * 0x18 + 1), RING_TINTS[entry.ring])
		# Mode1_WriteLinkSprites: a sword $C right of and 3 above a second-quest Link.
		if entry.quest == 2: draw_quest_sword(Vector2(0x30 + 0x0C, 0x58 + slot * 0x18 + 1 - 3))
	draw_heart_cursor(Vector2(0x28, FILE_CURSOR_YS[cursor] + 1))

## Z_02 ModeFTitleTransferBuf, ModeFSaveSlotTemplateTransferBuf, and Z_06
## ModeFCharsTransferBuf.
func draw_names() -> void:
	var title := "REGISTER YOUR NAME" if mode == "register" else "ELIMINATION  MODE"
	var codes: Array = [0x6A, 0x6A, 0x6A, 0x6A] + text_codes(title)
	while codes.size() < 25: codes.append(0x6A)
	draw_codes(codes, 4, 3)
	for slot in range(Files.COUNT):
		draw_codes(names[slot], 14, 6 + slot * 3)
		if files.active(slot) or mode == "register": draw_link(Vector2(0x50, 0x30 + slot * 0x18 + 1), RING_TINTS[files.meta[slot].ring] if files.active(slot) else Color.WHITE)
	draw_codes(text_codes("REGISTER    END" if mode == "register" else "ELIMINATION END"), 10, 15)
	draw_box(5, 16, 27, 24)
	for i in range(CHAR_MAP.size()):
		draw_codes([CHAR_MAP[i]], 6 + (i % 11) * 2, 17 + (i / 11) * 2)
	draw_heart_cursor(Vector2(0x43, SLOT_CURSOR_YS[cursor] + 1))
	if mode == "register" and cursor < 3 and (frame / 8) % 2 == 0:
		# The flashing block cursors on the name and the board.
		draw_rect(Rect2(112 + name_cursor * 8, (6 + cursor * 3) * 8, 8, 8), Color(1, 1, 1, 0.5))
		draw_rect(Rect2(0x30 + (board % 11) * 16, 0x88 + (board / 11) * 16, 8, 8), Color(1, 1, 1, 0.5))

static func filled(code: int, count: int) -> Array:
	var codes: Array = []
	codes.resize(count)
	codes.fill(code)
	return codes

func text_codes(text: String) -> Array:
	var codes: Array = []
	for character in text:
		var code := character.unicode_at(0)
		if code >= 48 and code <= 57: codes.append(code - 48)
		elif code >= 65 and code <= 90: codes.append(code - 55)
		else: codes.append(0x24)
	return codes

func draw_text_codes(text: String, column: int, row: int) -> void:
	draw_codes(text_codes(text), column, row)

## Background tiles from the imported HUD sheet, or plain characters without it.
func draw_codes(codes: Array, column: int, row: int, color := Color.WHITE) -> void:
	var sheet: Texture2D = world.visual_theme.hud_tiles
	for i in range(codes.size()):
		var code: int = codes[i]
		var at := Vector2((column + i) * 8, row * 8)
		# Background tiles are opaque: each replaces whatever the nametable held there.
		draw_rect(Rect2(at, Vector2(8, 8)), Color.BLACK)
		if code == 0x24: continue
		if sheet != null:
			draw_texture_rect_region(sheet, Rect2(at, Vector2(8, 8)), Rect2((code % 16) * 8, (code / 16) * 8, 8, 8), color)
		elif code < 10: draw_string(world.font, at + Vector2(0, 8), str(code), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
		elif code < 0x24: draw_string(world.font, at + Vector2(0, 8), char(code + 55), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
		elif code in [0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E]: draw_rect(Rect2(at + Vector2(3, 3), Vector2(2, 2)), Color("5c94fc"))
		elif TILE_CHARS.has(code): draw_string(world.font, at + Vector2(0, 8), TILE_CHARS[code], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)

func draw_box(left: int, top: int, right: int, bottom: int) -> void:
	draw_codes([0x69] + filled(0x6A, right - left - 1) + [0x6B], left, top)
	draw_codes([0x6E] + filled(0x6A, right - left - 1) + [0x6D], left, bottom)
	for row in range(top + 1, bottom):
		draw_codes([0x6C], left, row)
		draw_codes([0x6C], right, row)

## FormatHeartsInTextBuf: hearts 1-8 on the first row, the rest below.
func draw_hearts(containers: int, health: int, column: int, row: int) -> void:
	var sheet: Texture2D = world.visual_theme.hud_hearts
	for i in range(containers):
		var frame_index := 0 if health >= (i + 1) * 2 else 1 if health == i * 2 + 1 else 2
		var at := Vector2((column + i % 8) * 8, (row + i / 8) * 8)
		if sheet != null: draw_texture_rect_region(sheet, Rect2(at, Vector2(8, 8)), Rect2(frame_index * sheet.get_width() / 3.0, 0, sheet.get_width() / 3.0, sheet.get_height()))
		else: draw_rect(Rect2(at + Vector2(1, 1), Vector2(6, 6)), Color("d82800") if frame_index == 0 else Color("5a1a10"))

func draw_heart_cursor(at: Vector2) -> void:
	var sheet: Texture2D = world.visual_theme.hud_hearts
	if sheet != null: draw_texture_rect_region(sheet, Rect2(at, Vector2(8, 8)), Rect2(0, 0, sheet.get_width() / 3.0, sheet.get_height()))
	else: draw_rect(Rect2(at + Vector2(1, 1), Vector2(6, 6)), Color("d82800"))

## The sword tile ($20); the white sword's image stands in for menu palette 7.
func draw_quest_sword(at: Vector2) -> void:
	var sprite: Texture2D = world.visual_theme.sprites.get(&"white_sword_up") if world.visual_theme != null else null
	if sprite != null: draw_texture_rect(sprite, Rect2(at - Vector2(4, 0), Vector2(16, 16)), false)
	else: draw_rect(Rect2(at + Vector2(3, 1), Vector2(2, 14)), Color.WHITE)

## Mode1_WriteLinkSprites: Link facing down, in his file's ring color.
func draw_link(at: Vector2, tint: Color) -> void:
	var sheet: Texture2D = world.visual_theme.player_sheet
	if sheet != null:
		var width := sheet.get_width() / 8.0
		draw_texture_rect_region(sheet, Rect2(at, Vector2(16, 16)), Rect2(4 * width, 0, width, sheet.get_height()), tint)
	else: draw_rect(Rect2(at + Vector2(3, 2), Vector2(10, 13)), Color("81c454") * tint)
