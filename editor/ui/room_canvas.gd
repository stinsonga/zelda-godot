extends Control
signal resident_chosen
signal stair_chosen(id: String)
signal secret_chosen
signal entity_chosen(kind: String, id: String)
signal entity_moved(room_id: String, position: Array)
signal entity_delete
signal entity_duplicate
var select_mode := true
var selection: Dictionary = {}
var dragging := false
var drag_start := Vector2.ZERO
var drag_origin := Vector2.ZERO
var drag_position := Vector2.ZERO
const Pack = preload("../shared/room_pack.gd")
signal stroke_started
signal cell_clicked(cell: Vector2i, erase: bool)
signal stroke_finished
var room: Dictionary = {}
var visual_texture: Texture2D
var enemy_textures: Dictionary = {}
var enemy_sprite_frames: Dictionary = {}
var enemy_sprite_ticks: Dictionary = {}
var room_sprite_frames: Dictionary = {}
var room_sprite_ticks: Dictionary = {}
var art_clock := 0.0
func _process(delta: float) -> void:
	art_clock+=delta
	if not room_sprite_frames.is_empty() or not enemy_sprite_frames.is_empty(): queue_redraw()
func artwork(slot: String) -> Texture2D:
	var frames: Array = room_sprite_frames.get(slot,[])
	if frames.is_empty(): return null
	return frames[int(art_clock*60/maxi(1,int(room_sprite_ticks.get(slot,6))))%frames.size()]
func enemy_art(id: String) -> Texture2D:
	var frames: Array = enemy_sprite_frames.get(id,[])
	if frames.is_empty(): return enemy_textures.get(id)
	return frames[int(art_clock*60/maxi(1,int(enemy_sprite_ticks.get(id,6))))%frames.size()]
var show_collision := false
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
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hover = Vector2i(-1,-1); queue_redraw())
func _gui_input(event: InputEvent) -> void:
	if select_mode:
		select_input(event)
		return
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
	if dragging and event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = false
		entity_moved.emit(room.id,[int(drag_position.x),int(drag_position.y)])
		queue_redraw()
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
	if visual_texture != null: draw_texture_rect(visual_texture,rect,false)
	for y in range(11):
		for x in range(16):
			var cell := Rect2(rect.position+Vector2(x,y)*step,step)
			if visual_texture == null: draw_rect(cell,COLORS.get(room.tiles[y][x],Color.MAGENTA))
			if show_collision and room.tiles[y][x] in ["#","~"]:
				draw_rect(cell,Color(1,0.15,0.1,0.28))
				draw_line(cell.position,cell.end,Color(1,0.3,0.2,0.7),1)
			draw_rect(cell,Color("172633"),false,1)
	for edge in room.connections:
		if visual_texture != null: continue
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
		if enemy_textures.has(enemy.type):
			var top := rect.position + Vector2(enemy.position[0],enemy.position[1])/16.0*step
			draw_texture_rect(enemy_art(enemy.type),Rect2(top,step),false)
		else:
			draw_circle(at,minf(step.x,step.y)*0.32,Color("ec7967"))
			label_at("E",at+Vector2(-5,5),Color("1d2128"))
	for pickup in room.pickups:
		var at := rect.position + (Vector2(pickup.position[0],pickup.position[1]+3)+Vector2(8,8))/16.0*step
		draw_rect(Rect2(at-step*0.23,step*0.46),Color("e5c46a"))
		label_at(String(pickup.item).left(1).to_upper(),at+Vector2(-4,4),Color("1d2128"),12)
	var spawn := rect.position+(Vector2(room.spawn[0],room.spawn[1]+3)+Vector2(8,8))/16.0*step
	draw_circle(spawn,minf(step.x,step.y)*0.38,Color("86d1ad"),false,3)
	label_at("S",spawn+Vector2(-5,5),Color("86d1ad"))
	if room.has("resident"):
		var top := rect.position+Vector2(120,64)/16.0*step
		if artwork("resident") != null: draw_texture_rect(artwork("resident"),Rect2(top,step),false)
		else: draw_rect(Rect2(top,step),Color("e0a060"));label_at("N",top+step*0.5+Vector2(-5,5),Color("18232e"))
		for i in range(3):
			if room.resident.wares[i] == null: continue
			var ware_top := rect.position+Vector2(88+i*32,88)/16.0*step
			draw_rect(Rect2(ware_top+step*0.2,step*0.6),Color("e5c46a"))
			label_at(String(room.resident.wares[i].item).left(1).to_upper(),ware_top+step*0.5+Vector2(-4,4),Color("18232e"),12)
	for stair in room.get("stairs",[]):
		var top := rect.position+Vector2(stair.cell[0],stair.cell[1])*step
		var color := Color("7ecad5") if not stair.get("requires_secret",false) else Color("c2a5ee")
		if artwork("stairs") != null: draw_texture_rect(artwork("stairs"),Rect2(top,step),false);continue
		draw_rect(Rect2(top,step),Color("111b26"));draw_rect(Rect2(top,step),color,false,2)
		for i in range(4): draw_line(top+Vector2(i*0.12,0.18+i*0.2)*step,top+Vector2(0.9,0.18+i*0.2)*step,color,2)
	if room.has("secret"):
		var cell := Vector2(room.secret.cell[0],room.secret.cell[1])
		var direction: Vector2 = {"up":Vector2.UP,"right":Vector2.RIGHT,"down":Vector2.DOWN,"left":Vector2.LEFT}[room.secret.direction]
		var block := Rect2(rect.position+cell*step,step)
		var kind := Pack.secret_trigger(room.secret)
		var color := Color("a78bd4") if kind == "block" else Color("969faa") if kind == "bomb" else Color("e99052")
		if artwork("secret") != null: draw_texture_rect(artwork("secret"),block,false)
		else: draw_rect(block,color)
		draw_rect(block,Color("e4d7fa"),false,2)
		if artwork("secret") == null: label_at("B" if kind == "block" else "X" if kind == "bomb" else "F",block.get_center()+Vector2(-5,5),Color("18232e"))
		var target := block.get_center()+direction*step if kind == "block" else rect.position+(Vector2(Pack.secret_approach(room.secret))+Vector2(8,11))/16.0*step
		draw_rect(Rect2(target-step*0.5,step),Color("c2a5ee"),false,2)
		draw_line(block.get_center(),target,Color("e4d7fa"),2)
		draw_circle(target,3,Color("e4d7fa"))
	draw_selection()
	if hover.x >= 0 and not select_mode: draw_rect(Rect2(rect.position+Vector2(hover)*step,step),Color("e4edf2"),false,2)

func placement() -> Dictionary:
	if selection.get("room") != room.get("id"): return {}
	if selection.get("kind") == "spawn": return {"position":room.spawn}
	for entry in room.get(selection.get("kind",""),[]):
		if entry.id == selection.get("id"): return entry
	return {}
func room_pixel(at: Vector2) -> Vector2:
	var rect := geometry()
	return (at-rect.position)/rect.size*Vector2(256,176)
func select_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		var at := room_pixel(event.position)
		if room.has("resident") and Rect2(Vector2(120,64),Vector2(16,16)).has_point(at) and not event.alt_pressed:
			dragging = false;resident_chosen.emit();accept_event();return
		if room.has("secret") and Rect2(Vector2(room.secret.cell[0],room.secret.cell[1])*16,Vector2(16,16)).has_point(at) and not event.alt_pressed:
			dragging = false;secret_chosen.emit();accept_event();return
		if not event.alt_pressed:
			for stair in room.get("stairs",[]):
				if Rect2(Vector2(stair.cell[0],stair.cell[1])*16,Vector2(16,16)).has_point(at):
					dragging = false;stair_chosen.emit(stair.id);accept_event();return
		var hits: Array = []
		for kind in ["enemies","pickups","spawn"]:
			var entries: Array = [{"id":"","position":room.spawn}] if kind == "spawn" else room[kind]
			for entry in entries:
				if Rect2(Vector2(entry.position[0],entry.position[1]),Vector2(16,19)).has_point(at): hits.push_front({"kind":kind,"id":entry.id})
		if hits.is_empty(): entity_chosen.emit("","")
		else:
			var index := 0
			for i in hits.size():
				if hits[i].kind == selection.get("kind") and hits[i].id == selection.get("id"): index = (i+1)%hits.size() if event.alt_pressed else i;break
			entity_chosen.emit(hits[index].kind,hits[index].id)
			var data := placement()
			if not data.is_empty():
				dragging = true;drag_start = at;drag_origin = Vector2(data.position[0],data.position[1]);drag_position = drag_origin
		accept_event();queue_redraw()
	if event is InputEventMouseMotion and dragging:
		drag_position = drag_origin+((room_pixel(event.position)-drag_start)/8.0).round()*8.0
		queue_redraw()
	if event is InputEventKey and event.pressed and not event.echo:
		var data := placement()
		if event.keycode == KEY_ESCAPE: dragging = false;entity_chosen.emit("","");accept_event();queue_redraw();return
		if data.is_empty(): return
		var delta := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT: delta.x = -1
			KEY_RIGHT: delta.x = 1
			KEY_UP: delta.y = -1
			KEY_DOWN: delta.y = 1
			KEY_DELETE, KEY_BACKSPACE: entity_delete.emit();accept_event()
			KEY_D:
				if event.ctrl_pressed or event.meta_pressed: entity_duplicate.emit();accept_event()
		if delta != Vector2i.ZERO:
			var step := 1 if event.shift_pressed else 8
			entity_moved.emit(room.id,[int(data.position[0])+delta.x*step,int(data.position[1])+delta.y*step]);accept_event()
func draw_selection() -> void:
	if not select_mode: return
	var data := placement()
	if data.is_empty(): return
	var rect := geometry()
	var scale := rect.size/Vector2(256,176)
	var at := Vector2(data.position[0],data.position[1])
	draw_rect(Rect2(rect.position+at*scale,Vector2(16,19)*scale),Color("86d1ad"),false,2)
	if dragging:
		var pos := [int(drag_position.x),int(drag_position.y)]
		var valid := Pack.point(pos,0,240,0,157) and Pack.walkable(room.tiles,pos)
		draw_rect(Rect2(rect.position+drag_position*scale,Vector2(16,19)*scale),Color(0.4,1,0.6,0.5) if valid else Color(1,0.2,0.2,0.5))
