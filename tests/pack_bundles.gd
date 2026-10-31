extends SceneTree
## Standalone bundles: the editor exports a pack with its shared art, and the
## game plays it from the bundle alone, with its own files.
const Fixture = preload("res://editor/tests/authored_art_fixture.gd")
const Bundle = preload("res://editor/shared/pack_bundle.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
var failures := 0
func check(value: bool, text: String) -> void:
	if not value: failures += 1; push_error(text)
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("Pack bundle test timed out"); quit(1))
	call_deferred("run")
func run() -> void:
	var source := Fixture.create()
	var pack := Fixture.pack()
	check(Bundle.libraries(pack) == PackedStringArray(["test_art"]), "Bundle collects the libraries the pack names")
	var packs := source.path_join("packs")
	var folder := packs.path_join(pack.id)
	var errors := Bundle.write_bundle(pack, source, folder)
	check(errors.is_empty(), "Bundle exports: " + str(errors))
	check(FileAccess.file_exists(folder.path_join("pack.json")) and FileAccess.file_exists(folder.path_join("content/art/test_art/library.json")), "Bundle holds the pack and its library")
	check(not Bundle.write_bundle(pack, source, folder).is_empty(), "Export refuses a folder in use")
	check(Bundle.find([packs, source.path_join("missing")]) == PackedStringArray([folder]), "Bundles are found by folder")
	# The source art goes away: the bundle must stand alone.
	DirAccess.rename_absolute(source.path_join("content"), source.path_join("moved"))
	var loaded := Bundle.read(folder)
	check(loaded.errors.is_empty() and loaded.root == folder, "Bundle reads back")
	var result := Adapter.compile(loaded.pack, {}, loaded.root)
	check(result.errors.is_empty(), "Bundle compiles: " + str(result.errors))
	check(result.world.visual_theme.sprites.has(&"__editor_crawler_down_0"), "Shared art loads from the bundle")
	var front: Node = preload("res://scenes/front_end.tscn").instantiate()
	front.pack_world = result.world
	front.files_directory = "user://test_pack_files"
	root.add_child(front)
	check(front.mode == "files", "A bundle skips the original title")
	check(front.world.world_id == "authored/" + pack.id, "The front end plays the bundle's world")
	front.use_quest(2)
	check(front.world.world_id == "authored/" + pack.id, "Second-quest files keep the bundle's world")
	front.free()
	Fixture.remove(source)
	print("Pack bundle checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
