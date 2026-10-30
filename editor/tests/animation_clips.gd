extends SceneTree
const Fixture = preload("authored_art_fixture.gd")
const Importer = preload("../shared/authored_library.gd")
const Art = preload("../shared/appearance.gd")
const Playback = preload("../shared/sprite_animation.gd")
const Templates = preload("../shared/dungeon_templates.gd")
const Pack = preload("../shared/room_pack.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("Animation editor checks timed out");quit(1))
	call_deferred("run")
func run() -> void:
	var folder := Fixture.create();var imported := Fixture.add_clips(folder)
	check(imported.errors.is_empty(),"Named clip sheet imports")
	var library = Art.new();library.configure(folder)
	var id := "art/test_art/clips"
	check(library.animation_texture(id,"right","attack",0).get_image().get_pixel(1,1)==Color.YELLOW,"Attack begins on its first selected column")
	var final_frame: Texture2D = library.animation_texture(id,"right","attack",1000)
	check(final_frame.get_image().get_pixel(1,1)==Color.MAGENTA and final_frame.get_image().get_pixel(1,23)==Color.WHITE,"One-shot clip clamps while preserving direction and tall crop")
	check(library.animation_texture(id,"down","walk",4).get_image().get_pixel(1,1)==Color.BLUE and library.animation_texture(id,"down","walk",8).get_image().get_pixel(1,1)==Color.GREEN,"Walk uses its timing and loops selected columns")
	check(Playback.frame({"idle":Fixture.clips().idle},"attack",100,5,6)==0,"Missing attack falls back to idle")
	check(Playback.frame({},"idle",7,2,6)==1,"Legacy sheets retain their default frame timing")
	check(library.sprite_frames(id,"idle").size()==1 and library.clip_ticks(id,"idle")==9,"Room feature playback uses idle frames and timing")
	for bad in [{"idle":{"frames":[],"frame_ticks":1,"loop":true}},{"walk":{"frames":[5],"frame_ticks":4,"loop":true}},{"attack":{"frames":[0],"frame_ticks":0,"loop":false}},{"attack":{"frames":[0],"frame_ticks":1,"loop":true}},{"jump":{"frames":[0],"frame_ticks":1,"loop":true}}]:
		var errors := PackedStringArray();Importer.validate_clips(bad,5,errors);check(not errors.is_empty(),"Invalid clip metadata is rejected")
	var ui = preload("../ui/main.tscn").instantiate();root.add_child(ui)
	ui.game_root = folder;ui.asset_library.load_catalog(folder)
	var pack := Fixture.pack();pack.appearance.enemy_sprites.crawler = id
	ui.replace_pack(pack,"",false)
	ui.canvas.enemy_preview_clip = "attack";ui.canvas.art_clock = 10.0
	check(ui.canvas.enemy_art("crawler").get_image().get_pixel(1,1)==Color.MAGENTA,"Room preview uses named one-shot clip")
	ui.asset_library.search.text = "clips";ui.asset_library.populate();ui.asset_library.select_image(0)
	check(ui.asset_library.preview_clip.item_count==3,"Browser offers named clip previews")
	ui.shooting.button_pressed = true;ui.apply_enemy()
	check(ui.pack.enemy_types.crawler.shooting_enabled and Pack.validate(ui.pack).is_empty(),"Existing walker shooting is editable")
	ui.undo();check(not ui.pack.enemy_types.crawler.has("shooting_enabled"),"Shooting edit supports undo")
	var dialog = ui.asset_library.importer;dialog.game_root = folder;dialog.kind.select(1);dialog.refresh_inputs()
	dialog.source.text = folder.path_join("clips_source.png");dialog.library_id.text = "test_art";dialog.asset_id.text = "gui_clips"
	dialog.frame_width.value = 16;dialog.frame_height.value = 24;dialog.draw_width.value = 16;dialog.draw_height.value = 24;dialog.offset_y.value = -8
	dialog.frames.value = 5;dialog.directions.text = "down,right"
	for name in Fixture.clips():
		var controls: Dictionary = dialog.clip_controls[name];controls.enabled.button_pressed = true;controls.frames.text = ",".join(Fixture.clips()[name].frames.map(func(index): return str(index)));controls.ticks.value = Fixture.clips()[name].frame_ticks
	dialog.import_asset()
	check(dialog.result_text.text.begins_with("Imported art/test_art/gui_clips"),"GUI imports clip controls")
	check(Templates.canonical(ui.asset_library.library.groups["art/test_art/gui_clips"].clips)==Templates.canonical(Fixture.clips()),"GUI preserves clip metadata exactly")
	ui.replace_pack(Pack.sample(),"",false)
	ui.shooting.button_pressed = true;ui.apply_enemy()
	check(ui.pack.schema==2 and Pack.validate(ui.pack).is_empty(),"Enabling shooting upgrades legacy packs")
	ui.select_room("hall");ui.select_placement("enemies","guard_a")
	ui.placement_inspector.shooting.button_pressed = false;ui.placement_inspector.apply()
	check(not ui.pack.enemy_types[ui.selected_placement().type].get("shooting_enabled",false),"Per-placement edit can disable shooting")
	check(ui.pack.enemy_types.crawler.shooting_enabled and Pack.validate(ui.pack).is_empty(),"Per-placement shooting changes preserve other instances")
	ui.free();Fixture.remove(folder)
	print("Animation clip editor checks: ","PASS" if failures==0 else "FAIL");quit(0 if failures==0 else 1)
