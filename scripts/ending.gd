class_name EndingSequence
extends RefCounted
## Z_02 mode $13 after Zelda's rescue (InitMode13_Full, UpdateMode13WinGame).
## Once her fanfare ends, the room furls away from both edges; Zelda thanks
## Link; both hold up the Triforce while the backdrop flashes; "FINALLY, PEACE
## RETURNS TO HYRULE" types out; the credits scroll by between brick walls; and
## the Triforce over Ganon's ashes waits for Start. The play area and credits
## are nametable data on a NesScreen; the World draws the status bar and sprites.
const DATA_PATH := "res://imported/title/ending.json"
## UpdateWorldCurtainEffect: columns $1F down and 0 up, every 5 frames, until
## the decreasing index is under $11.
const FURL_START_LEFT := 0x20
const FURL_START_RIGHT := 1
const FURL_STEP := 5
const FURL_END := 0x11
const THANKS_STEP := 6
const THANKS_HOLD := 0x50
const SPECIAL_SPACE := 0x25
const FLASH_START := 0x40
const FLASH_END := 0xC0
const PEACE_DELAY := 0x40
const PEACE_LONG := 0x40
## Characters stop at long timer $10; Link and Zelda stay until it is 4.
const PEOPLE_UNTIL := 4
const PEACE_BLANK := 0x24
const CREDITS_DELAY := 0x40
## DrawCredits: brick tile $FA; row 1 and $2E are horizontal walls, the rows
## between have side walls (tile columns 3 and 28).
const WALL_TILE := 0xFA
const WALL_TOP := 1
const WALL_BOTTOM := 0x2E
const LAST_CREDIT := 0x17
const FIRST_QUEST_LAST := 0x10
const SECOND_QUEST_SKIP := [0x0C, 0x10]
const NAME_LINE := 0x11
const NAME_COLUMN := 9
const DEATHS_COLUMN := 19
## Long timers count down once every ten frames.
const LONG_PERIOD := 10

var data: Dictionary
var screen: NesScreen
## The file being played: quest 1 or 2, name tile codes, and death count.
var quest := 1
var file_name: Array = []
var deaths := 0
## False through InitMode13's submodes, then UpdateMode13WinGame's.
var updating := false
var submode := 0
var frame := 0
## Frames since Zelda's fanfare began: the furl waits for the song to end.
var song_frames := 0
## ObjTimer for Link (slot 0) and Zelda (slot 1), and EndingFlashLongTimer.
var timer := 0
var zelda_timer := 0
var long_timer := 0
var long_cycle := LONG_PERIOD - 1
var furl_left := FURL_START_LEFT
var furl_right := FURL_START_RIGHT
var text_address := 0
var text_index := 0
var thanks_done := false
var lift_timer := 0
var peace_counter := 0
var peace_index := 0
var tile_offset := 0
var fraction := 0
var screens := 0
var credits_row := 0
var credits_page := 0
var credits_line := 0
var credits_index := 0
## Credits have reached NT0's status bar rows; the World stops drawing it.
var status_bar_overwritten := false
## Requests for the World this frame: a song (or &"" to silence) and sounds.
var song_request = null
var sounds: Array[StringName] = []
var finished := false

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH) or not ResourceLoader.exists(TitleDemo.CHR_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if parsed is Dictionary and parsed.get("format") == 1 else {}

func _init(ending_data: Dictionary, colors: Array, target: NesScreen, elapsed_song_frames: int) -> void:
	data = ending_data
	screen = target
	song_frames = elapsed_song_frames
	screen.configure(load(TitleDemo.CHR_PATH), colors)
	screen.clear_tables()
	screen.hide_sprites()
	screen.write_palette(data.level_palette)
	screen.hud_rows = 8

## Columns erased from each side by the furl.
func furled() -> int:
	return FURL_START_LEFT - furl_left

## Whether the NES picture has replaced the room (after the furl).
func on_screen() -> bool:
	return updating or submode > 0

## Link and Zelda as left by the rescue, during the thanks.
func shows_people() -> bool:
	return not updating

## Link and Zelda holding up the Triforce, during the flash and the peace text.
func shows_triforces() -> bool:
	return updating and (submode == 0 or (submode in [1, 2] and long_timer >= PEOPLE_UNTIL))

func shows_final() -> bool:
	return updating and submode == 4

## Screen Y of NT0's top row.
func status_bar_top() -> int:
	return -screen.scroll_y if screen.base_table == 0 else 240 - screen.scroll_y

func tick(start: bool) -> void:
	song_request = null
	sounds.clear()
	song_frames += 1
	if not updating: initialize()
	else: update(start)
	frame = (frame + 1) & 0xFF
	timer = maxi(0, timer - 1)
	zelda_timer = maxi(0, zelda_timer - 1)
	long_cycle -= 1
	if long_cycle < 0:
		long_cycle = LONG_PERIOD - 1
		long_timer = maxi(0, long_timer - 1)

func initialize() -> void:
	match submode:
		0:
			# UpdateEndGameCurtainEffect.
			if timer != 0 or song_frames < int(data.zelda_song_frames): return
			timer = FURL_STEP
			furl_left -= 1
			furl_right += 1
			if furl_left < FURL_END:
				timer = 0x80
				submode = 1
		1:
			var attrs: Array = data.play_area_attrs
			for i in range(int(attrs[1])): screen.write_vram(int(attrs[0]) + i, int(attrs[2]))
			text_address = int(data.thanks_start)
			text_index = 0
			thanks_done = false
			submode = 2
		2:
			update_thanks()
			if thanks_done:
				zelda_timer = THANKS_HOLD
				submode = 3
		3:
			if zelda_timer == 0:
				song_request = &""
				submode = 4
		4:
			tile_offset = 8
			updating = true
			submode = 0
			peace_counter = 0
			peace_index = 0

## UpdateZeldaTextbox: a character every six frames; the top bits of a
## character move to the second line ($80), the third ($40), or end ($C0).
func update_thanks() -> void:
	if zelda_timer != 0: return
	zelda_timer = THANKS_STEP
	var text: Array = data.thanks_text
	var value: int
	while true:
		value = int(text[text_index])
		var address := text_address
		text_address = (text_address & 0xFF00) | ((text_address + 1) & 0xFF)
		text_index += 1
		if value & 0x3F != SPECIAL_SPACE:
			screen.write_vram(address, value & 0x3F)
			break
	sounds.append(&"text")
	if value & 0xC0 == 0: return
	var line := 2 if value & 0xC0 == 0xC0 else 1 if value & 0xC0 == 0x40 else 0
	text_address = (int(data.thanks_start) & 0xFF00) | int(data.thanks_lines[line])
	if line == 2: thanks_done = true

func update(start: bool) -> void:
	match submode:
		0:
			lift_timer += 1
			if lift_timer == FLASH_END:
				song_request = &"ending"
				timer = PEACE_DELAY
				long_timer = PEACE_LONG
				submode = 1
			flash_palette()
		1, 2:
			if long_timer == 0:
				for record in data.ending_palette: screen.write_palette(record[1], int(record[0]))
				submode = 3
			elif submode == 1 and long_timer >= PEOPLE_UNTIL and timer == 0:
				update_peace()
		3: scroll_credits()
		4:
			if timer == 0 and start: finished = true

## From $40 frames on, the level palette is rewritten each frame with the
## backdrop cycling through EndingFlashColors.
func flash_palette() -> void:
	if lift_timer < FLASH_START: return
	screen.write_palette(data.level_palette)
	screen.write_palette([int(data.flash_colors[lift_timer & 3])], 0x10)

## UpdatePeaceTextbox: a character every eight frames; spaces are silent.
func update_peace() -> void:
	peace_counter = (peace_counter + 1) & 0xFF
	if peace_counter & 7 != 4: return
	var value: int = int(data.peace_text[peace_index])
	if value == 0xFF:
		submode = 2
		return
	if value != PEACE_BLANK: sounds.append(&"text")
	var low: int = int(data.peace_addrs[peace_index])
	peace_index += 1
	# Past $FF the high byte moves on to the next page.
	var high: int = int(data.peace_high) if low >= 0xA0 else int(data.peace_high) + 1
	screen.write_vram(high << 8 | low, value)

## UpdateMode13WinGame_Sub3: half a line a frame; a new row every eight lines.
func scroll_credits() -> void:
	if tile_offset >= 8:
		tile_offset -= 8
		draw_credits()
	fraction += 0x80
	var carry := 1 if fraction >= 0x100 else 0
	fraction &= 0xFF
	tile_offset += carry
	screen.scroll_y += carry
	if screen.scroll_y >= 0xF0:
		screen.scroll_y = 0
		screens += 1
		screen.base_table ^= 1
	var index := 0 if quest == 1 else 1
	if screens >= int(data.last_screens[index]) and screen.scroll_y >= int(data.last_scrolls[index]):
		submode = 4
		timer = CREDITS_DELAY

## DrawCredits: one nametable row of walls and text, and every fourth row its
## attributes. Pages $28-$2B then $20-$23 hold 8, 8, 8, and 6 rows.
func draw_credits() -> void:
	var line: Array = []
	line.resize(32)
	line.fill(NesScreen.BLANK_TILE)
	if credits_row == WALL_TOP or credits_row == WALL_BOTTOM:
		for i in range(3, 29): line[i] = WALL_TILE
	elif credits_row > WALL_TOP and credits_row < WALL_BOTTOM:
		line[3] = WALL_TILE
		line[28] = WALL_TILE
	var high: int = int(data.credits_pages[credits_page])
	var address := high << 8 | credits_line << 5
	if (int(data.credits_masks[credits_page]) << credits_line) & 0x80 and credits_index < LAST_CREDIT:
		var skip := (quest == 1 and credits_index >= FIRST_QUEST_LAST) or (quest != 1 and credits_index >= SECOND_QUEST_SKIP[0] and credits_index < SECOND_QUEST_SKIP[1])
		if not skip:
			var text: Array = data.credits_lines[credits_index]
			for i in range(1, text.size()): line[int(text[0]) + i - 1] = int(text[i])
			if credits_index == NAME_LINE:
				for i in range(mini(8, file_name.size())): line[NAME_COLUMN + i] = int(file_name[i])
				var digits := str(clampi(deaths, 0, 255)).lpad(3)
				for i in range(3): line[DEATHS_COLUMN + i] = NesScreen.BLANK_TILE if digits[i] == " " else int(digits[i])
		credits_index += 1
	for i in range(32): screen.write_vram(address + i, line[i])
	if address < 0x2100: status_bar_overwritten = true
	credits_line += 1
	if credits_line == (6 if credits_page & 3 == 3 else 8):
		credits_line = 0
		credits_page = (credits_page + 1) % 12
	if credits_row & 3 == 0:
		var value: int = int(data.credits_attrs[credits_row >> 2]) if credits_row >> 2 < data.credits_attrs.size() else 0
		var attr_address := (0x2BC0 if high & 0x08 else 0x23C0) + (credits_row & 0x1F) * 2
		for i in range(8): screen.write_vram(attr_address + i, 0 if i == 0 or i == 7 else value)
	credits_row += 1
	if credits_row & 0x1F >= 0x1E: credits_row += 2
