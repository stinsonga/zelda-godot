extends SceneTree
## Optional integration test: --rom /local/file.nes [--import-local-art].
## The explicit import flag rebuilds the local ignored library and keeps a backup.
var failures := 0
func _initialize() -> void:
	create_timer(600).timeout.connect(func(): push_error("Import integration timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func wait_for_job(importer: Node) -> void:
	while importer.busy: await create_timer(0.25).timeout
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--rom" in args: print("Import integration: SKIP (supply --rom)"); quit(0); return
	var rom_path: String = args[args.find("--rom")+1]
	var ui = preload("../ui/main.tscn").instantiate()
	root.add_child(ui)
	var original: Dictionary = ui.pack.duplicate(true)
	var importer = ui.importer
	var bad_path := "/tmp/zelda-editor-bad-input.nes"
	var file := FileAccess.open(bad_path,FileAccess.WRITE)
	file.store_string("not a ROM");file.close()
	var manifest_path: String = ui.game_root.path_join("imported/manifest.json")
	var before := FileAccess.get_file_as_string(manifest_path) if FileAccess.file_exists(manifest_path) else ""
	importer.rom.text = bad_path
	importer.start(true)
	check(importer.busy,"Invalid ROM validation starts background worker")
	await wait_for_job(importer)
	check(importer.last_state.get("state") == "failed","Invalid ROM has a clear failed status")
	check(importer.message.text.contains("header"),"Invalid-ROM error is surfaced in GUI")
	check((FileAccess.get_file_as_string(manifest_path) if FileAccess.file_exists(manifest_path) else "") == before,"Invalid ROM does not modify library")
	importer.rom.text = rom_path
	importer.start(true)
	await wait_for_job(importer)
	check(importer.last_state.get("state") == "validated","Valid local ROM verified through actual GUI worker")
	if "--import-local-art" in args:
		importer.start(false)
		await wait_for_job(importer)
		check(importer.last_state.get("state") == "complete","Full import completes through GUI")
		check(ui.asset_library.entries.size() > 0 and ui.views.current_tab == 2,"Import automatically refreshes image browser")
		ui.asset_library.search.text = "stalfos"
		ui.asset_library.populate()
		check(ui.asset_library.shown.size() > 0,"Imported monsters can be searched")
		if not ui.asset_library.shown.is_empty():
			ui.asset_library.select_image(0)
			check(ui.asset_library.preview.texture != null,"Imported PNG previews without editor texture import")
		check(not importer.last_state.get("backup","").is_empty(),"Previous local import retained as backup")
	check(ui.pack == original and ui.undo_stack.is_empty(),"Import never changes authored pack or undo history")
	ui.free()
	print("Import workflow checks: ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
