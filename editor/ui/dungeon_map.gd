extends Control
## Spatial room overview. Layout changes do not silently rewrite traversal links.
signal room_selected(id: String)
signal room_activated(id: String)
signal room_moved(id: String, cell: Vector2i)
signal empty_cell_selected(cell: Vector2i)
const Contract = preload("../shared/room_pack.gd")
const DIRECTIONS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
const DOOR_COLORS := {"open":Color("86d1ad"),"key":Color("e5c46a"),"bombable":Color("ec7967"),"shutter":Color("b49bdb"),"false":Color("74b8d4"),"wall":Color("657180")}
var pack: Dictionary = {}
var selected_id := ""
var cell_size := Vector2(150,110)
var origin := Vector2(60,220)
var hover := Vector2i(-1,1)
var dragging := ""
var drag_cell := Vector2i.ZERO
var panning := false
var fitted := false
func _ready() -> void:
	custom_minimum_size = Vector2(450,330)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(func():
		if not fitted: fit_to_rooms()
		queue_redraw())
func update_pack(value: Dictionary, selected: String) -> void:
	pack = value
	selected_id = selected
	queue_redraw()
func fit_to_rooms() -> void:
	if pack.is_empty() or size.x < 1 or size.y < 1: return
	var low := Vector2(16,1)
	var high := Vector2(0,-15)
	for room in pack.rooms:
		var at := Vector2(room.map_position[0],room.map_position[1])
		low = low.min(at)
		high = high.max(at)
	var span := (high-low+Vector2.ONE).max(Vector2(3,3))
	var width := clampf(minf((size.x-100)/span.x,(size.y-80)/span.y*1.4),32,200)
	cell_size = Vector2(width,width/1.4)
	origin = size/2-(low+high+Vector2.ONE)/2*cell_size
	fitted = true
	queue_redraw()
func zoom_at(at: Vector2, factor: float) -> void:
	var before := (at-origin)/cell_size
	var width := clampf(cell_size.x*factor,24,300)
	cell_size = Vector2(width,width/1.4)
	origin = at-before*cell_size
	queue_redraw()
func cell_at(at: Vector2) -> Vector2i: return Vector2i(((at-origin)/cell_size).floor())
func valid_cell(cell: Vector2i) -> bool: return cell.x >= 0 and cell.x < 16 and cell.y >= -15 and cell.y <= 0
func room_at(cell: Vector2i) -> String:
	if pack.is_empty(): return ""
	for room in pack.rooms:
		if int(room.map_position[0]) == cell.x and int(room.map_position[1]) == cell.y: return room.id
	return ""
func center(room: Dictionary) -> Vector2:
	var at := Vector2(room.map_position[0],room.map_position[1])
	if room.id == dragging: at = Vector2(drag_cell)
	return origin+(at+Vector2(0.5,0.5))*cell_size
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position,1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15)
			accept_event()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed
			accept_event()
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var cell := cell_at(event.position)
			var id := room_at(cell)
			if not id.is_empty():
				room_selected.emit(id)
				if event.double_click: room_activated.emit(id)
				else: dragging = id; drag_cell = cell
			elif valid_cell(cell): empty_cell_selected.emit(cell)
			accept_event()
	if event is InputEventMouseMotion:
		hover = cell_at(event.position)
		if panning: origin += event.relative
		if not dragging.is_empty(): drag_cell = hover
		queue_redraw()
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.pressed: return
	if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
	if event.button_index == MOUSE_BUTTON_LEFT and not dragging.is_empty():
		var id := dragging
		dragging = ""
		room_moved.emit(id,drag_cell)
		queue_redraw()
func text(value: String, at: Vector2, color: Color, font_size: int = 14, width: float = -1) -> void:
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,width,font_size,color)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("111b26"))
	if pack.is_empty(): return
	var grid_color := Color("263643")
	for x in range(17): draw_line(origin+Vector2(x,-15)*cell_size,origin+Vector2(x,1)*cell_size,grid_color)
	for y in range(-15,2): draw_line(origin+Vector2(0,y)*cell_size,origin+Vector2(16,y)*cell_size,grid_color)
	var lookup: Dictionary = {}
	for room in pack.rooms: lookup[room.id] = room
	for room in pack.rooms:
		for edge in room.connections:
			var link: Dictionary = room.connections[edge]
			if not lookup.has(link.target) or String(room.id) > String(link.target): continue
			var target: Dictionary = lookup[link.target]
			var direction: Vector2 = Vector2(DIRECTIONS[edge])
			var a := center(room)+direction*cell_size*0.36
			var b := center(target)-direction*cell_size*0.36
			var aligned: bool = Vector2i(int(target.map_position[0])-int(room.map_position[0]),int(target.map_position[1])-int(room.map_position[1])) == DIRECTIONS[edge]
			var color: Color = DOOR_COLORS[link.kind] if aligned else Color("ed8eaa")
			if aligned: draw_line(a,b,color,3,true)
			else: draw_dashed_line(a,b,color,2,7,true)
			var middle := (a+b)/2
			if cell_size.x >= 65:
				var label := String(link.kind) + (" +item" if not link.get("requires",[]).is_empty() else "") + (" !" if not aligned else "")
				var extent := ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12)
				draw_rect(Rect2(middle-extent/2-Vector2(4,6),extent+Vector2(8,8)),Color("111b26"))
				text(label,middle-extent/2+Vector2(0,7),color,12)
	for room in pack.rooms:
		var at := center(room)
		var rect := Rect2(at-cell_size*0.36,cell_size*0.72)
		var color := Color("86d1ad") if room.id == selected_id else Color("8496a8")
		if room.id == dragging and (not valid_cell(drag_cell) or room_at(drag_cell) not in ["",dragging]): color = Color("ec7967")
		draw_rect(rect,Color("273a48"))
		draw_rect(rect,color,false,3 if room.id == selected_id else 1)
		if cell_size.x >= 65:
			var caption := ("★ " if room.id == pack.start_room else "") + String(room.title)
			var available: float = rect.size.x-12
			while caption.length() > 1 and ThemeDB.fallback_font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > available: caption = caption.left(caption.length()-2) + "…"
			text(caption,rect.position+Vector2(6,20),Color("e4edf2"),14,available)
			text("%d enemies / %d items" % [room.enemies.size(),room.pickups.size()],rect.position+Vector2(6,38),Color("a4b5c3"),11,available)
			if room.has("role") and rect.size.y>60: text(String(room.role).to_upper(),rect.position+Vector2(6,54),Color("86d1ad"),10,available)
		if room.id == selected_id:
			for direction in DIRECTIONS.values(): draw_circle(at+Vector2(direction)*cell_size*0.36,3,Color("86d1ad"))
	if dragging.is_empty() and valid_cell(hover) and room_at(hover).is_empty():
		draw_rect(Rect2(origin+Vector2(hover)*cell_size,cell_size),Color("8496a8"),false,1)
