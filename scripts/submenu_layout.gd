class_name SubmenuLayout
extends Resource
## Original submenu data the runtime needs (generated into imported/): the 24
## Triforce tile slots of UpdateMenuStartOW, three per level 1-8, as
## menu-local pixels with their empty and owned tiles; and each level's sheet
## map rotation and column masks (LevelInfo_SubmenuMapRotation/Mask).
@export var triforce_positions: PackedVector2Array = PackedVector2Array()
@export var triforce_empty: PackedByteArray = PackedByteArray()
@export var triforce_full: PackedByteArray = PackedByteArray()
## Levels 1-9 in order; masks hold 16 bytes per level.
@export var map_rotations: PackedByteArray = PackedByteArray()
@export var map_masks: PackedByteArray = PackedByteArray()
