extends Control
## A read-only schematic of the unit that will be captured, never ROM art.
const DIRS := {"up":Vector2.UP,"right":Vector2.RIGHT,"down":Vector2.DOWN,"left":Vector2.LEFT}
var rooms: Array = []
var ports: Array = []
## Ports on companion rooms, by room ID.
var companion_ports: Dictionary = {}
var primary := ""
var reward := ""
var error := ""
func _ready() -> void:
	custom_minimum_size = Vector2(260,190)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)
func set_unit(selected: Array, external_ports: Array, reward_id: String, problem: String = "", companions: Dictionary = {}) -> void:
	rooms = selected.duplicate(true);ports = external_ports.duplicate();companion_ports = companions.duplicate(true)
	primary = str(rooms[0].id) if not rooms.is_empty() else ""
	reward = reward_id;error = problem
	queue_redraw()
func cells() -> Dictionary:
	var result: Dictionary = {}
	if rooms.is_empty(): return result
	var low := Vector2(15,0);var high := Vector2(0,-15)
	for room in rooms:
		var at := Vector2(room.map_position[0],room.map_position[1]);low = low.min(at);high = high.max(at)
	var span := high-low+Vector2.ONE
	var step := minf(76,minf((size.x-72)/span.x,(size.y-62)/span.y))
	var origin := Vector2(size.x, size.y-26)*0.5-span*step*0.5
	for room in rooms:
		var at := Vector2(room.map_position[0],room.map_position[1])-low
		result[room.id] = Rect2(origin+at*step+Vector2.ONE*step*0.16,Vector2.ONE*step*0.68)
	return result
func _draw() -> void:
	draw_style_box(get_theme_stylebox("panel","Tree"),Rect2(Vector2.ZERO,size))
	var font := ThemeDB.fallback_font
	if not error.is_empty() or rooms.is_empty():
		draw_string(font,Vector2(12,28),"Selection unavailable — see capture message",HORIZONTAL_ALIGNMENT_LEFT,size.x-24,13,Color("efb678"));return
	var bounds := cells()
	for room in rooms:
		var from: Vector2 = bounds[room.id].get_center()
		for edge in room.connections:
			var link: Dictionary = room.connections[edge]
			if not bounds.has(link.target) or String(room.id)>String(link.target): continue
			var tint := Color("eead54") if link.kind=="key" else Color("e97c79") if link.kind=="bombable" else Color("8395a7")
			draw_line(from,bounds[link.target].get_center(),tint,3)
		for stair in room.get("stairs",[]):
			if not bounds.has(stair.target): continue
			var to: Vector2 = bounds[stair.target].get_center()
			draw_dashed_line(from,to,Color("b99be7"),2,5)
			var tip: Vector2 = from.lerp(to,0.65);var direction := from.direction_to(to)
			draw_line(tip,tip-direction.rotated(0.5)*7,Color("b99be7"),2)
			draw_line(tip,tip-direction.rotated(-0.5)*7,Color("b99be7"),2)
	var root: Rect2 = bounds[primary]
	for port in ports:
		var start: Vector2 = root.get_center()+DIRS[port]*root.size*0.5
		draw_line(start,start+DIRS[port]*14,Color("79d9ac"),3)
	for id in companion_ports:
		if not bounds.has(id): continue
		for port in companion_ports[id]:
			if not DIRS.has(port): continue
			var start: Vector2 = bounds[id].get_center()+DIRS[port]*bounds[id].size*0.5
			draw_line(start,start+DIRS[port]*14,Color("79d9ac"),3)
	for room in rooms:
		var box: Rect2 = bounds[room.id]
		var tint := Color("856b3c") if room.id==primary else Color("584675") if room.get("kind")=="cellar" else Color("35536c")
		draw_rect(box,tint);draw_rect(box,Color("79d9ac") if room.id==reward else Color("afbdca"),false,2)
		var label := ("P " if room.id==primary else "")+("* " if room.id==reward else "")+str(room.id)
		if box.size.x>=30: draw_string(font,box.position+Vector2(3,box.size.y/2+4),label,HORIZONTAL_ALIGNMENT_LEFT,box.size.x-6,11)
	draw_string(font,Vector2(10,size.y-9),"P primary   * reward   green: ports/reward   orange: key   red: bomb   dashed: stairs",HORIZONTAL_ALIGNMENT_LEFT,size.x-20,11,Color("c5cfda"))
func _get_tooltip(at: Vector2) -> String:
	var bounds := cells()
	for room in rooms:
		if bounds[room.id].has_point(at):
			var lines: PackedStringArray = [str(room.id)+( " (primary)" if room.id==primary else "" )]
			for edge in room.connections:
				var link: Dictionary = room.connections[edge]
				if bounds.has(link.target): lines.append(edge+" → "+str(link.target)+" ("+str(link.kind)+")")
			for stair in room.get("stairs",[]):
				if bounds.has(stair.target): lines.append("stairs → "+str(stair.target))
			if room.id==reward: lines.append("Generated reward room")
			return "\n".join(lines)
	return "Template footprint; hover over a room for its full ID and links."
