class_name VisualTheme
extends Resource
## Presentation only. Textures are drawn into logical rectangles regardless of resolution.
@export var floor_color: Color = Color("d6bd85")
@export var wall_color: Color = Color("687b3d")
@export var player_color: Color = Color("81c454")
@export var accent_color: Color = Color("f1dfb0")
@export var floor_texture: Texture2D
@export var wall_texture: Texture2D
@export var player_texture: Texture2D

## Optional directional sheet: right, left, down, up; two 16x16 poses each.
@export var player_sheet: Texture2D
@export var hud_tiles: Texture2D

## Named sprites for room decorations, weapons, and item poses.
@export var sprites: Dictionary[StringName, Texture2D] = {}
