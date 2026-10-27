extends Control
signal stroke_started
signal cell_clicked(cell: Vector2i, erase: bool)
signal stroke_finished
var room: Dictionary = {}
var painting := false
var last_cell := Vector2i(-1,-1)
var hover := Vector2i(-1,-1)
const COLORS := {".":Color("273a48"),"#":Color("596879"),"~":Color("285d80")}
func geometry() -> Rect2:
	var scale := minf((size.x-24)/256.0,(size.y-24)/176.0)
	var extent := Vector2(256,176)*maxf(scale,0.1)
	return Rect2((size-extent)/2,extent)
func cell_at(at: Vector2) -> Vector2i:
	var rect := geometry()
	if not rect.has_point(at): return Vector2i(-1,-1)
	return Vector2i((at-rect.position)/(rect.size/Vector2(16,11)))
func _ready() -> void:
	custom_minimum_size = Vector2(450,330)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover = Vector2i(-1,-1); queue_redraw())
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			painting = true
			last_cell = Vector2i(-1,-1)
			stroke_started.emit()
			paint_at(event.position,event.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()
	if event is InputEventMouseMotion:
		hover = cell_at(event.position)
		if painting: paint_at(event.position,(event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0)
		queue_redraw()
func _input(event: InputEvent) -> void:
	if painting and event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		painting = false
		stroke_finished.emit()
func paint_at(at: Vector2, erase: bool) -> void:
	var cell := cell_at(at)
	if cell.x < 0 or cell == last_cell: return
	if last_cell.x >= 0:
		var delta := cell-last_cell
		var steps := maxi(absi(delta.x),absi(delta.y))
		for i in range(1,steps):
			cell_clicked.emit(Vector2i(Vector2(last_cell).lerp(Vector2(cell),float(i)/steps).round()),erase)
	last_cell = cell
	cell_clicked.emit(cell,erase)
func label_at(text: String, at: Vector2, color: Color, font_size: int = 15) -> void:
	draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("111b26"))
	if room.is_empty(): return
	var rect := geometry()
	var step := rect.size/Vector2(16,11)
	for y in range(11):
		for x in range(16):
			var cell := Rect2(rect.position+Vector2(x,y)*step,step)
			draw_rect(cell,COLORS.get(room.tiles[y][x],Color.MAGENTA))
			draw_rect(cell,Color("172633"),false,1)
	for edge in room.connections:
		var p := Vector2(7.5,0.5)
		match edge:
			"down": p = Vector2(7.5,10.5)
			"left": p = Vector2(0.5,5.0)
			"right": p = Vector2(15.0,5.0)
		var at := rect.position + p*step
		draw_rect(Rect2(at-step*Vector2(0.5,0.35),step*Vector2(1,0.7)),Color("c39a61"))
		label_at(String(room.connections[edge].kind).left(1).to_upper(),at+Vector2(-5,5),Color("111b26"))
	for enemy in room.enemies:
		var at := rect.position + (Vector2(enemy.position[0],enemy.position[1]+3)+Vector2(8,8))/16.0*step
		draw_circle(at,minf(step.x,step.y)*0.32,Color("ec7967"))
		label_at("E",at+Vector2(-5,5),Color("1d2128"))
	for pickup in room.pickups:
		var at := rect.position + (Vector2(pickup.position[0],pickup.position[1]+3)+Vector2(8,8))/16.0*step
		draw_rect(Rect2(at-step*0.23,step*0.46),Color("e5c46a"))
		label_at(String(pickup.item).left(1).to_upper(),at+Vector2(-4,4),Color("1d2128"),12)
	var spawn := rect.position+(Vector2(room.spawn[0],room.spawn[1]+3)+Vector2(8,8))/16.0*step
	draw_circle(spawn,minf(step.x,step.y)*0.38,Color("86d1ad"),false,3)
	label_at("S",spawn+Vector2(-5,5),Color("86d1ad"))
	if hover.x >= 0: draw_rect(Rect2(rect.position+Vector2(hover)*step,step),Color("e4edf2"),false,2)
