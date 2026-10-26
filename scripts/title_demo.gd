class_name TitleDemo
extends RefCounted
## Z_02 mode 0: the title screen, its fade, and the story scroll, looping until
## Start. Phase 0 is the title (InitDemo_RunTasks, AnimateDemoPhase0*), phase 1
## the story (AnimateDemoPhase1*). Data comes from imported/title/title.json;
## this replays the per-frame rules on a NesScreen.
const DATA_PATH := "res://imported/title/title.json"
const CHR_PATH := "res://imported/title/chr.png"
## UpdateWaterfallAnimation: starting heights, the range waves cycle through,
## and the heights where they widen; the crest sits still.
const WAVE_STARTS := [0xB6, 0xC8, 0xD8]
const WAVE_TOP := 0xB2
const WAVE_BOTTOM := 0xE3
const CREST_Y := 0xA8
## OAM byte offset of the crest sprites.
const CREST_OFFSET := 0xF0
## Glow: frames per color, and the longer pause after each cycle.
const GLOW_STEP := 6
const GLOW_REST := 0x10
## AnimateDemoPhase1Subphase2: the story stops after five screens and $80 lines.
const STORY_SCREENS := 5
const STORY_LINES := 0x80
## Phase 1 subphase 1 points new lines at NT2 row 8 and its attributes at $2BE0.
const FIRST_LINE := 0x2900
const FIRST_ATTRS := 0x2BE0
const ITEM_START_Y := 0xEF
const FALLEN_Y := 0xF0
const LINK_X := 0x68
const TRIFORCE_ID := 0x1B
const TRIFORCE_X := 0x78
const FAIRY_ID := 0x23
const FINAL_IDS := 0x30
const FINAL_DELAY := 0x39
const DISABLED := 0xFF

var data: Dictionary
var screen: NesScreen
var audio: Node
## DemoPhase, DemoSubphase, and IsUpdatingMode (false while initializing).
var phase := 0
var subphase := 0
var updating := false
## FrameCounter: its low bits pace the scroll, the timer, and the animations.
var frame := 0
var timer := 0
var glow_timer := 0
var glow_cycle := 0
var waterfall_ready := false
var waves := [0, 0, 0]
var fade_cycle := 0
var fade_timer := 0
var lines_scrolled := 0
var screens_scrolled := 0
var line_index := 0
var text_index := 0
var item_row := 0
var line_address := FIRST_LINE
var attr_address := FIRST_ATTRS
## Objects 1-10 (slot 0 is never drawn): state 0 shown, $FF disabled.
var objects: Array = []

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(DATA_PATH) or not ResourceLoader.exists(CHR_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return parsed if parsed is Dictionary and parsed.get("format") == 1 else {}

func _init(title_data: Dictionary, target: NesScreen, sound: Node = null) -> void:
	data = title_data
	screen = target
	audio = sound
	screen.configure(load(CHR_PATH), data.colors)
	for i in range(11): objects.append({"state": DISABLED, "x": 0, "y": 0, "item": 0})

## One frame. Returns true when Start leaves for the file menu (UpdateMode0Demo_Sub0).
func tick(start: bool) -> bool:
	var leaving := false
	if not updating: initialize()
	else:
		screen.video = true
		animate()
		if updating and start:
			if audio != null: audio.silence()
			leaving = true
	frame = (frame + 1) & 0xFF
	return leaving

## InitDemo_RunTasks: three frames with video off.
func initialize() -> void:
	screen.video = false
	match subphase:
		0:
			screen.hide_sprites()
			screen.clear_tables()
		1:
			if phase == 0:
				screen.write_palette(data.title_palette)
				text_index = 0
				item_row = 0
				for i in range(1, 11): objects[i].state = DISABLED
			else:
				screen.write_palette(data.story_palette)
				for i in range(11): objects[i].item = 0
			reset_vars()
		2:
			if phase == 0:
				if audio != null:
					audio.silence()
					audio.set_music(&"title")
				screen.load_tables(data.title_tables)
			else:
				screen.base_table ^= 1
				screen.scroll_y = 0x10
				screen.load_tables(data.story_tables)
			subphase = -1
			updating = true
	subphase += 1

## The variables cleared with TriforceGlowTimer, InitializedWaterfallAnimation,
## and DemoPhase0Subphase1Cycle.
func reset_vars() -> void:
	glow_timer = 0
	glow_cycle = 0
	screens_scrolled = 0
	line_index = 0
	timer = 0
	lines_scrolled = 0
	waterfall_ready = false
	waves = [0, 0, 0]
	fade_cycle = 0
	fade_timer = 0

func animate() -> void:
	if phase == 0:
		if subphase == 0: animate_title()
		else: animate_fade()
		return
	match subphase:
		0: animate_story_intro()
		1:
			timer = (timer + 1) & 0xFF
			if timer == 0: subphase += 1
			line_address = FIRST_LINE
			attr_address = FIRST_ATTRS
		2: animate_story_items()
		3:
			timer = (timer + 1) & 0xFF
			if timer == 0: subphase += 1
			else: draw_objects()
		4:
			timer = (timer + 1) & 0xFF
			if timer == FINAL_DELAY:
				updating = false
				timer = 0
				phase = 0
				subphase = 0
			else: draw_objects()

## AnimateDemoPhase0Subphase0: about 512 frames of title.
func animate_title() -> void:
	if frame & 1:
		timer = (timer + 1) & 0xFF
		if timer == 0:
			subphase = 1
			return
	var sprites: Array = data.title_sprites
	for i in range(sprites.size()): screen.oam[i] = int(sprites[i])
	update_waterfall()
	if glow_timer == 0:
		var record: Array = data.glow_record.duplicate()
		record[2] = data.glow_colors[glow_cycle]
		screen.write_palette(record, int(data.glow_address) - 0x3F00)
		glow_timer = GLOW_STEP
		glow_cycle += 1
		if glow_cycle == 8:
			glow_timer = GLOW_REST
			glow_cycle = 0
	glow_timer -= 1

## AnimateDemoPhase0Subphase1: the title fades through 14 palettes.
func animate_fade() -> void:
	if fade_timer == 0:
		screen.write_palette(data.fade_palettes[fade_cycle])
		fade_cycle += 1
		fade_timer = int(data.fade_delays[fade_cycle - 1])
		if fade_cycle >= 14:
			phase = 1
			subphase = 0
			updating = false
	fade_timer = (fade_timer - 1) & 0xFF
	update_waterfall()

func update_waterfall() -> void:
	if not waterfall_ready:
		waves = WAVE_STARTS.duplicate()
		waterfall_ready = true
	for wave in range(2, -1, -1):
		waves[wave] += 2
		if waves[wave] >= WAVE_BOTTOM: waves[wave] = WAVE_TOP
		var y: int = waves[wave]
		var offset := 0x10 if y >= 0xC2 else 8 if y >= 0xB9 else 0
		var base: int = int(data.wave_offsets[wave]) / 4
		for i in range(3, -1, -1):
			screen.set_sprite(base + 3 - i, y, int(data.wave_tiles[i]) + offset, 0, int(data.waterfall_xs[i]))
	for i in range(3, -1, -1):
		screen.set_sprite(CREST_OFFSET / 4 + 3 - i, CREST_Y, (frame & 8) + int(data.crest_tiles[i]), 0, int(data.waterfall_xs[i]))

## AnimateDemoPhase1Subphase0: the prologue scrolls up from below, a line every
## other frame, until NT0 sits 8 lines up.
func animate_story_intro() -> void:
	if frame & 1:
		screen.scroll_y += 1
		if screen.scroll_y == 0xF0:
			screens_scrolled += 1
			screen.scroll_y = 0
			screen.base_table ^= 1
	if screen.scroll_y == 8 and screens_scrolled != 0:
		screens_scrolled = 0
		subphase += 1

## AnimateDemoPhase1Subphase2: the item list. Every eighth line writes a new
## nametable row, with its text, attributes, and items.
func animate_story_items() -> void:
	disable_fallen()
	draw_objects()
	if frame & 1 == 0: return
	for i in range(1, 11): objects[i].y = (objects[i].y - 1) & 0xFF
	lines_scrolled = (lines_scrolled + 1) & 0xFF
	if lines_scrolled == 0: screens_scrolled += 1
	if screens_scrolled == STORY_SCREENS and lines_scrolled == STORY_LINES:
		subphase += 1
		return
	screen.scroll_y += 1
	if screen.scroll_y == 0xF0:
		screen.base_table ^= 1
		screen.scroll_y = 0
	if lines_scrolled & 7: return
	add_line_items()
	var line: Array = []
	line.resize(32)
	line.fill(NesScreen.BLANK_TILE)
	var attrs: int = int(data.line_attrs[line_index]) if line_index < data.line_attrs.size() else 0
	if attrs & 0x80:
		var text: Array = data.text_lines[text_index]
		for i in range(1, text.size()): line[int(text[0]) + i - 1] = int(text[i])
		text_index += 1
	for i in range(32): screen.write_vram(line_address + i, line[i])
	line_address += 0x20
	if line_address & 0xFF == 0xC0:
		if line_address >> 8 == 0x2B: line_address = 0x2000
		elif line_address >> 8 == 0x23: line_address = 0x2800
	if attrs & 0x40:
		for i in range(8): screen.write_vram(attr_address + i, 0)
		# Only the low byte advances; at $00 it moves to the other table's attributes.
		var low := (attr_address + 8) & 0xFF
		attr_address = (attr_address & 0xFF00) | low
		if low == 0: attr_address = 0x2BC0 if attr_address >> 8 == 0x23 else 0x23C0
	line_index += 1

## ProcessDemoLineItems: a row of two items (or one centered picture row).
func add_line_items() -> void:
	if line_index >= data.line_attrs.size() or not int(data.line_attrs[line_index]) & 0x20: return
	var slot := 10
	while objects[slot].state == 0: slot -= 1
	var left: int = int(data.left_items[item_row])
	objects[slot] = {"state": 0, "x": int(data.column_xs[0]), "y": ITEM_START_Y, "item": left}
	if left >= FINAL_IDS:
		objects[slot].x = LINK_X
	else:
		objects[slot - 1] = {"state": 0, "x": int(data.column_xs[1]), "y": ITEM_START_Y, "item": int(data.right_items[item_row])}
		if left == TRIFORCE_ID:
			objects[slot].x = TRIFORCE_X
			objects[slot - 1].x = TRIFORCE_X
	item_row += 1

## DisableFallenObjects.
func disable_fallen() -> void:
	for i in range(1, 11):
		if objects[i].y == FALLEN_Y: objects[i].state = DISABLED

## Demo_AnimateObjects, after HideAllSprites.
func draw_objects() -> void:
	screen.hide_sprites()
	var next := 0
	for i in range(10, 0, -1):
		var object: Dictionary = objects[i]
		if object.state != 0: continue
		var item: int = object.item
		if item >= FINAL_IDS:
			# AnimateDemoStoryFinalItems: six sprites a row from the picture tables.
			var row := (item & 0x0F) * 6
			for part in range(6):
				var tile: int = int(data.final_tiles[row + part])
				if tile == 0: continue
				screen.set_sprite(next, object.y, tile, int(data.final_attrs[row + part]), object.x + part * 8)
				next += 1
			continue
		var entry: Dictionary = data.items.get(str(item), {})
		if entry.is_empty(): continue
		var frames: Array = entry.frames
		# AnimateStationaryFairy switches frames every 4; flashing items switch palette every 8.
		var sprites: Array = frames[(frame >> 2) & 1] if item == FAIRY_ID else frames[0]
		for sprite in sprites:
			var attr: int = int(sprite[2])
			if entry.flash: attr = (attr & 0xFC) | (1 + ((frame & 8) >> 3))
			screen.set_sprite(next, object.y, int(sprite[1]), attr, object.x + int(sprite[0]))
			next += 1
