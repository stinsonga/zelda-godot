extends SceneTree
## Optional real-library integration: --screenshot /tmp/image.png.
## Preview snapshots stay ignored; no per-user saved overlay is changed.
const Pack = preload("../shared/room_pack.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Local art check timed out"); quit(1))
	call_deferred("run")
func run() -> void:
	var ui = preload("../ui/main.tscn").instantiate()
	root.add_child(ui)
	if not ui.asset_library.library.groups.has("rom/us_prg0/l1_stalfos"):
		print("Local art checks: SKIP (import the local ROM first)")
		ui.free();quit(0);return
	ui.replace_pack(Pack.sample(),"",false)
	var authored: Dictionary = ui.pack.duplicate(true)
	ui.select_room("hall")
	ui.asset_library.search.text = "l1 stalfos"
	ui.asset_library.populate()
	ui.asset_library.select_image(0)
	ui.asset_library.enemy_apply.pressed.emit()
	check(ui.appearance.enemy_sprites.crawler == "rom/us_prg0/l1_stalfos","Grouped real sprite selected through browser action")
	ui.asset_library.search.text = "level 1"
	ui.asset_library.category.select(2)
	ui.asset_library.populate()
	for i in range(ui.asset_library.shown.size()):
		if ui.asset_library.shown[i].id == "rom/us_prg0/levels/level_1": ui.asset_library.select_image(i);break
	ui.asset_library.preview.selected_tile = 73
	ui.asset_library.tile_apply.pressed.emit()
	var before: Dictionary = ui.pack.duplicate(true)
	var before_art: Dictionary = ui.appearance.duplicate(true)
	for y in range(11):
		for x in range(16):
			ui.art_brush.index = 9 if ui.current().tiles[y][x] == "#" else 73
			ui.paint(Vector2i(x,y),false)
	ui.commit(before,before_art)
	check(ui.pack == authored,"Real ROM selections do not change public pack")
	check(ui.canvas.visual_texture != null and ui.canvas.enemy_textures.has("crawler"),"Real atlas and sprite render together")
	var folder: String = ui.game_root.path_join("reference-inputs/editor-previews/appearance-demo")
	DirAccess.make_dir_recursive_absolute(folder)
	Pack.write(folder.path_join("pack.json"),ui.pack)
	Pack.write(folder.path_join("appearance.json"),ui.appearance)
	var args := OS.get_cmdline_user_args()
	if "--screenshot" in args:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[args.find("--screenshot")+1])
	ui.free()
	print("Local art checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
