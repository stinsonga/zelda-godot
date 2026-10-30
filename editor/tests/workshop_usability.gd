extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	check(ui.feature_panels.values().all(func(panel): return not panel.visible),"Optional feature forms start collapsed")
	var source: Dictionary = ui.pack.duplicate(true)
	ui.set_tool("Block")
	check(ui.block_inspector.visible and not ui.stairs_inspector.visible,"Secret brush reveals its settings")
	ui.set_tool("Stairs")
	check(ui.stairs_inspector.visible and not ui.block_inspector.visible,"Stairs brush reveals only its settings")
	ui.set_tool("Pickup")
	check(ui.feature_panels.values().all(func(panel): return not panel.visible),"Basic brush returns to compact inspector")
	ui.feature_buttons.Resident.button_pressed = true
	check(ui.resident_inspector.visible and not ui.block_inspector.visible,"Resident form remains reachable without a resident already placed")
	ui.feature_buttons.Secret.button_pressed = true
	check(ui.block_inspector.visible and not ui.resident_inspector.visible and not ui.feature_buttons.Resident.button_pressed,"Feature buttons are mutually exclusive")
	ui.feature_buttons.Secret.button_pressed = false
	check(not ui.block_inspector.visible,"Feature form can be collapsed")
	ui.inspect_resident();await process_frame;await process_frame
	check(ui.resident_inspector.visible,"Selecting a resident opens its form")
	check(ui.pack==source and not ui.dirty(),"Changing inspector views leaves document/history unchanged")
	ui.set_tool("Pickup");await process_frame;await process_frame
	var scroll: ScrollContainer = ui.item_type.get_parent().get_parent()
	check(scroll.scroll_vertical>0 and ui.item_type.position.y>=scroll.scroll_vertical and ui.item_type.position.y<scroll.scroll_vertical+scroll.size.y,"Pickup brush brings its item selector into view")
	ui.set_tool("Floor");await process_frame
	check(scroll.scroll_vertical==0,"Terrain brush restores the top of the compact inspector")
	ui.free()
	print("Workshop usability checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
