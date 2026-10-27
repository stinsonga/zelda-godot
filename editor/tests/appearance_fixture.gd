extends RefCounted
const Pack = preload("../shared/room_pack.gd")
const Art = preload("../shared/appearance.gd")
static func create() -> String:
	var root := OS.get_temp_dir().path_join("zelda-appearance-fixture-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	populate(root)
	return root
static func populate(root: String) -> void:
	DirAccess.make_dir_recursive_absolute(root.path_join("imported/levels"))
	var entries: Array = []
	for direction in ["up","down","left","right"]:
		for pose in range(2):
			var name := "test_beast_%s_%d" % [direction,pose]
			var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
			image.fill(Color.RED if pose == 0 else Color.BLUE)
			image.save_png(root.path_join("imported/" + name + ".png"))
			entries.append({"id":"rom/us_prg0/" + name,"name":name,"path":name + ".png","category":"sprites","width":16,"height":16})
	var atlas := Image.create(32,16,false,Image.FORMAT_RGBA8)
	atlas.fill(Color.RED)
	atlas.fill_rect(Rect2i(16,0,16,16),Color.BLUE)
	atlas.save_png(root.path_join("imported/levels/test.png"))
	entries.append({"id":"rom/us_prg0/levels/test","name":"Test atlas","path":"levels/test.png","category":"tiles","width":32,"height":16})
	Pack.write(root.path_join("imported/editor_catalog.json"),{"format_version":1,"source":{"prg_sha1":Art.SHA1},"entries":entries})
static func remove(root: String) -> void:
	if "zelda-appearance-fixture-" not in root: return
	for filename in DirAccess.get_files_at(root): DirAccess.remove_absolute(root.path_join(filename))
	for folder in DirAccess.get_directories_at(root): remove(root.path_join(folder))
	DirAccess.remove_absolute(root)
