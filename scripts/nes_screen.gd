class_name NesScreen
extends Node2D
## The picture as the PPU builds it, for screens the original draws directly in
## nametables and OAM (the title and story). Zelda mirrors horizontally, so the
## two nametables ($2000 and $2800) stack vertically and scroll into each
## other. Sprites are 8x16, background patterns sit at $1000 (PpuControl $30).
## Pattern tables come from an index atlas; the shader looks up the palette.
const SHADER = preload("res://scripts/nes_screen.gdshader")
const BLANK_TILE := 0x24
const HIDDEN_Y := 0xF8
## Index atlas: pattern table 0 in the top 128 rows, table 1 below.
var chr: Texture2D
## The 64 NES colors as RGB.
var colors: Array[Color] = []
## NT0 and NT2: 960 tiles, then 64 attribute bytes.
var tables: Array[PackedByteArray] = []
var palette := PackedByteArray()
## 0 shows NT0 first, 1 shows NT2 first (CurPpuControl bit 1).
var base_table := 0
var scroll_y := 0
var oam := PackedByteArray()
## False while the original turns all video off.
var video := true
## NT0's top rows left to the World, which draws its status bar there (the ending).
var hud_rows := 0

func _init() -> void:
	var shading := ShaderMaterial.new()
	shading.shader = SHADER
	material = shading
	palette.resize(32)
	oam.resize(256)
	clear_tables()
	hide_sprites()

func configure(atlas: Texture2D, rgb: Array) -> void:
	chr = atlas
	colors.clear()
	for hex in rgb: colors.append(Color(str(hex)))

## Z_07 TurnOffVideoAndClearArtifacts: tile $24 and zero attributes, scroll reset.
func clear_tables() -> void:
	tables.clear()
	for i in range(2):
		var table := PackedByteArray()
		table.resize(1024)
		table.fill(BLANK_TILE)
		for j in range(960, 1024): table[j] = 0
		tables.append(table)
	base_table = 0
	scroll_y = 0

func load_tables(source: Array) -> void:
	for i in range(2): tables[i] = PackedByteArray(source[i])

## Z_07 HideAllSprites.
func hide_sprites() -> void:
	for i in range(64): oam[i * 4] = HIDDEN_Y

func set_sprite(index: int, y: int, tile: int, attr: int, x: int) -> void:
	oam[index * 4] = y & 0xFF
	oam[index * 4 + 1] = tile & 0xFF
	oam[index * 4 + 2] = attr & 0xFF
	oam[index * 4 + 3] = x & 0xFF

## Writes from $3F00 on; $3F10, $3F14, $3F18, and $3F1C mirror the background's color 0s.
func write_palette(values: Array, start := 0) -> void:
	for i in range(values.size()):
		var index := (start + i) & 0x1F
		if index & 0x13 == 0x10: index &= 0x0F
		palette[index] = int(values[i]) & 0x3F

## A PPU address in $2000-$2FFF; $2400 and $2C00 mirror $2000 and $2800.
func write_vram(address: int, value: int) -> void:
	tables[1 if address & 0x0800 else 0][address & 0x3FF] = value & 0xFF

func _draw() -> void:
	if chr == null or colors.size() < 64: return
	var lookup := PackedColorArray()
	for i in range(32): lookup.append(colors[palette[i]])
	material.set_shader_parameter("colors", lookup)
	if not video:
		draw_rect(Rect2(0, 0, 256, 240), Color.BLACK)
		return
	if hud_rows == 0: draw_rect(Rect2(0, 0, 256, 240), Color(0, 1, 0))
	else:
		var top := -scroll_y if base_table == 0 else 240 - scroll_y
		var bottom := top + hud_rows * 8
		if top > 0: draw_rect(Rect2(0, 0, 256, mini(top, 240)), Color(0, 1, 0))
		if bottom < 240: draw_rect(Rect2(0, maxi(bottom, 0), 256, 240 - maxi(bottom, 0)), Color(0, 1, 0))
	draw_sprites(true)
	draw_background()
	draw_sprites(false)

func draw_background() -> void:
	var fine := scroll_y & 7
	for i in range(31):
		var row := (scroll_y >> 3) + i
		var table := base_table
		if row >= 30:
			row -= 30
			table ^= 1
		if table == 0 and row < hud_rows: continue
		var nametable: PackedByteArray = tables[table]
		for column in range(32):
			var tile: int = nametable[row * 32 + column]
			var attr: int = nametable[960 + (row >> 2) * 8 + (column >> 2)]
			var row_palette := (attr >> (((row & 2) << 1) | (column & 2))) & 3
			draw_texture_rect_region(chr, Rect2(column * 8, i * 8 - fine, 8, 8),
				Rect2((tile & 15) * 8, (16 + (tile >> 4)) * 8, 8, 8), Color(row_palette * 4 / 31.0, 0, 0))

## Lower OAM indices are in front, so draw from the end.
func draw_sprites(behind: bool) -> void:
	for index in range(63, -1, -1):
		var y: int = oam[index * 4]
		var attr: int = oam[index * 4 + 2]
		if y >= 0xEF or bool(attr & 0x20) != behind: continue
		var tile: int = oam[index * 4 + 1]
		var x: int = oam[index * 4 + 3]
		var flip := Vector2(-1 if attr & 0x40 else 1, -1 if attr & 0x80 else 1)
		var modulate_palette := Color((16 + (attr & 3) * 4) / 31.0, 0, 0)
		for half in range(2):
			var pattern := (tile & 0xFE) + (half ^ (1 if attr & 0x80 else 0))
			var bank := tile & 1
			draw_set_transform(Vector2(x + (8 if flip.x < 0 else 0), y + 1 + half * 8 + (8 if flip.y < 0 else 0)), 0, flip)
			draw_texture_rect_region(chr, Rect2(0, 0, 8, 8),
				Rect2((pattern & 15) * 8, (bank * 16 + (pattern >> 4)) * 8, 8, 8), modulate_palette)
	draw_set_transform(Vector2.ZERO)
