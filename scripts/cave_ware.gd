class_name CaveWare
extends Resource
## One of up to three cave items, at original X $58, $78, or $98.
@export var item: Resource
@export var price: int = 0
## Shown after paying in a hint cave; empty keeps the greeting.
@export_multiline var hint: String = ""
