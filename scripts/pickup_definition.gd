class_name PickupDefinition
extends Resource

@export var id: StringName
@export var item: Resource
@export var position: Vector2i
@export var tolerance: Vector2i = Vector2i(0, 5)
@export var lift_ticks: int = 128
## Appears only once the room is clear (original secret triggers 3 and 7).
@export var requires_clear: bool = false
## A monster spawn slot (1 for the first) whose monster carries this item; it
## stays where the carrier died (Z_07 MoveAndDrawRoomItem). 0 places it normally.
@export var carrier_slot: int = 0
## Shown only once the room's secret is revealed (the Armos-hidden bracelet).
@export var requires_secret: bool = false
