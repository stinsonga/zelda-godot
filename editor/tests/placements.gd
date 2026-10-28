extends SceneTree
const Pack = preload("../shared/room_pack.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1;push_error(text)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ui = preload("../ui/main.tscn").instantiate()
	root.add_child(ui)
	ui.replace_pack(JSON.parse_string(JSON.stringify(Pack.sample())),"",false)
	ui.select_room("hall")
	ui.select_placement("enemies","guard_a")
	check(not ui.dirty() and ui.undo_stack.is_empty(),"Selection must not alter document")
	ui.placement_inspector.apply()
	check(ui.undo_stack.is_empty(),"Applying unchanged JSON-loaded stats must be a no-op")
	ui.placement_inspector.health.value = 7
	ui.placement_inspector.apply()
	var type: String = ui.selected_placement().type
	check(type != "crawler" and ui.pack.enemy_types[type].health == 7,"Shared stats get an individual variant")
	check(ui.current().enemies[1].type == "crawler" and ui.pack.enemy_types.crawler.health == 2,"Other enemy retains original stats")
	ui.undo()
	check(ui.selected_placement().type == "crawler" and ui.pack.enemy_types.size() == 1,"Undo restores variant assignment and definitions")
	ui.canvas.size = Vector2(600,450)
	var rect: Rect2 = ui.canvas.geometry()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT;press.pressed = true
	press.position = rect.position+Vector2(88,69)/Vector2(256,176)*rect.size
	ui.canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position+Vector2(16,0)/Vector2(256,176)*rect.size
	ui.canvas._gui_input(motion)
	check(ui.same_position(ui.selected_placement().position,[80,61]),"Drag preview must not mutate content")
	var release := InputEventMouseButton.new();release.button_index = MOUSE_BUTTON_LEFT
	ui.canvas._input(release)
	check(ui.same_position(ui.selected_placement().position,[96,61]) and ui.undo_stack.size() == 1,"One drag commits one move")
	ui.undo()
	ui.move_placement("hall",[0,0])
	check(ui.same_position(ui.selected_placement().position,[80,61]) and ui.undo_stack.is_empty(),"Solid destination rejected without history")
	ui.move_placement("entry",[96,61])
	check(ui.same_position(ui.selected_placement().position,[80,61]),"Stale room movement rejected")
	var key := InputEventKey.new();key.pressed = true;key.keycode = KEY_RIGHT;key.shift_pressed = true
	ui.canvas._gui_input(key)
	check(ui.same_position(ui.selected_placement().position,[81,61]),"Shift arrow moves one pixel")
	ui.undo()
	ui.duplicate_placement()
	check(ui.current().enemies.size() == 3 and ui.selected_placement().id != "guard_a","Duplicate has fresh stable ID")
	check(Pack.validate(ui.pack).is_empty(),"Duplicate is valid authored content")
	ui.undo()
	ui.select_room("entry");ui.select_placement("pickups","entry_key")
	ui.placement_inspector.objective.button_pressed = true
	ui.placement_inspector.clear_reward.button_pressed = true
	ui.placement_inspector.apply()
	check(ui.pack.schema == 2 and ui.pack.goals.size() == 1 and ui.selected_placement().requires_clear,"Pickup controls upgrade schema")
	ui.move_placement("entry",[80,77])
	check(ui.pack.goals[0].pickup == "entry_key","Movement preserves objective ID")
	ui.duplicate_placement()
	check(ui.pack.goals.size() == 1,"Duplicate does not inherit objective membership")
	ui.undo();ui.select_placement("pickups","entry_key");ui.delete_placement()
	check(ui.pack.goals.is_empty() and ui.current().pickups.is_empty(),"Delete cleans objective reference")
	ui.undo()
	check(ui.pack.goals.size() == 1 and ui.selected_placement().id == "entry_key","Undo restores objective and selection")
	ui.select_placement("spawn","");var count: int = ui.undo_stack.size()
	ui.delete_placement();ui.duplicate_placement()
	check(ui.undo_stack.size() == count,"Spawn cannot be deleted or duplicated")
	check(Pack.validate(ui.pack).is_empty(),"Edited content validates")
	ui.queue_free();await process_frame
	if failures == 0: print("Placement checks: PASS (selection, drag, stats isolation, objectives, undo)")
	quit(1 if failures else 0)
