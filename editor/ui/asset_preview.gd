extends Control
signal tile_selected(index: int)
var texture: Texture2D:
	set(value): texture = value; queue_redraw()
var tile_mode := false
var selected_tile := 0
func _ready() -> void:
	custom_minimum_size = Vector2(200,210)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
func image_rect() -> Rect2:
	if texture == null: return Rect2()
	var extent := texture.get_size()
	var factor := minf((size.x-12)/extent.x,(size.y-12)/extent.y)
	extent *= maxf(factor,0.01)
	return Rect2((size-extent)/2,extent)
func _gui_input(event: InputEvent) -> void:
	if texture == null or not tile_mode or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	var rect := image_rect()
	if not rect.has_point(event.position): return
	var at: Vector2 = (event.position-rect.position)/rect.size*texture.get_size()
	selected_tile = int(at.y/16)*(texture.get_width()/16)+int(at.x/16)
	tile_selected.emit(selected_tile)
	queue_redraw()
	accept_event()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("111b26"))
	if texture == null: return
	var rect := image_rect()
	draw_texture_rect(texture,rect,false)
	if not tile_mode: return
	var columns := texture.get_width()/16
	var step := rect.size/texture.get_size()*16
	var at := rect.position+Vector2(selected_tile%columns,selected_tile/columns)*step
	draw_rect(Rect2(at,step),Color.WHITE,false,2)
