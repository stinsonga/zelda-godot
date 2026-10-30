extends SceneTree
const Fixture = preload("authored_art_fixture.gd")
const Importer = preload("../shared/authored_library.gd")
const Art = preload("../shared/appearance.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Rectangular art checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var folder := Fixture.create();var imported := Fixture.add_tall(folder)
	check(imported.errors.is_empty(),"Rectangular sprite imports: "+str(imported.errors))
	var library = Art.new();library.configure(folder)
	var id := "art/test_art/tall"
	var texture: Texture2D = library.enemy_texture(id,"left",1)
	check(texture.get_size()==Vector2(32,48),"Frame crops retain rectangular source size")
	check(texture.get_image().get_pixel(1,1)==Color.CYAN and texture.get_image().get_pixel(1,47)==Color.MAGENTA,"Direction and frame lookup crop entire tall frame")
	check(library.sprite_layout(id)==Rect2(-2,-8,16,24),"Logical geometry is independent of source dimensions")
	check(library.sprite_layout("art/test_art/beast")==Rect2(0,0,16,16),"Previous square defaults remain unchanged")
	var loaded := Importer.read(imported.manifest)
	for field in ["frame_size","draw_size","draw_offset"]:
		var invalid: Dictionary = loaded.library.duplicate(true)
		invalid.assets[-1][field] = {"frame_size":[0,48],"draw_size":[16,0],"draw_offset":[-129,0]}[field]
		check(not Importer.validate(invalid).is_empty(),"Reject invalid "+field)
	var odd: Dictionary = loaded.library.duplicate(true)
	odd.assets[-1].frame_size = [10,15];odd.assets[-1].width = 20;odd.assets[-1].height = 60
	check(Importer.validate(odd).is_empty(),"Frame dimensions need not be powers of two")
	var legacy: Dictionary = loaded.library.duplicate(true)
	for asset in legacy.assets:
		asset.erase("draw_size");asset.erase("draw_offset")
	check(Importer.validate(legacy).is_empty(),"Existing manifests without drawing geometry still validate")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.game_root = folder;ui.asset_library.load_catalog(folder)
	var pack := Fixture.pack();pack.appearance.enemy_sprites.crawler = id;pack.appearance.room_sprites.entry.secret = id
	ui.replace_pack(pack,"",false)
	check(ui.canvas.enemy_layouts.crawler==Rect2(-2,-8,16,24) and ui.canvas.room_sprite_layouts.secret==Rect2(-2,-8,16,24),"Canvas receives enemy and object layouts")
	check(ui.canvas.art_rect(Vector2(100,100),library.sprite_layout(id),Vector2(32,32))==Rect2(96,84,32,48),"Canvas scales offsets and size by zoom without changing anchor")
	var dialog = ui.asset_library.importer;dialog.game_root = folder
	dialog.kind.select(1);dialog.refresh_inputs()
	dialog.source.text = folder.path_join("tall_source.png");dialog.library_id.text = "test_art";dialog.asset_id.text = "gui_tall"
	dialog.frame_width.value = 32;dialog.frame_height.value = 48;dialog.draw_width.value = 16;dialog.draw_height.value = 24;dialog.offset_x.value = -2;dialog.offset_y.value = -8
	dialog.directions.text = "down,up,right,left";dialog.frames.value = 2;dialog.ticks.value = 7;dialog.import_asset()
	check(dialog.result_text.text.begins_with("Imported art/test_art/gui_tall"),"GUI imports rectangular geometry")
	check(ui.asset_library.library.sprite_layout("art/test_art/gui_tall")==Rect2(-2,-8,16,24),"Imported layout refreshes into browser")
	dialog.kind.select(0);dialog.refresh_inputs()
	check(not dialog.frame_width.editable and not dialog.offset_x.editable and not dialog.cell_size.disabled,"Tile import retains square grid and disables sprite geometry")
	ui.free();Fixture.remove(folder)
	print("Rectangular art editor checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
