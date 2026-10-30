extends RefCounted
const Pack = preload("../shared/room_pack.gd")
const Importer = preload("../shared/authored_library.gd")
const Bindings = preload("../shared/art_bindings.gd")
const Cleanup = preload("appearance_fixture.gd")
static func create() -> String:
	var folder := OS.get_temp_dir().path_join("zelda-appearance-fixture-authored-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder)
	var atlas := Image.create(64,32,false,Image.FORMAT_RGBA8)
	atlas.fill(Color.RED);atlas.fill_rect(Rect2i(32,0,32,32),Color.BLUE)
	atlas.save_png(folder.path_join("source.png"))
	Importer.import_png(folder,folder.path_join("source.png"),"test_art","tiles","tiles",32)
	var sprite := Image.create(64,128,false,Image.FORMAT_RGBA8)
	for row in range(4):
		for frame in range(2): sprite.fill_rect(Rect2i(frame*32,row*32,32,32),Color.RED if frame == 0 else [Color.BLUE,Color.GREEN,Color.YELLOW,Color.CYAN][row])
	sprite.save_png(folder.path_join("sprite.png"))
	Importer.import_png(folder,folder.path_join("sprite.png"),"test_art","beast","sprite",32,["down","up","right","left"],2,9)
	return folder
static func pack() -> Dictionary:
	var value := Pack.sample();Pack.upgrade(value)
	value.rooms[0].secret = {"cell":[5,4],"direction":"right","reveal":"item"}
	value.rooms[0].stairs = [{"id":"to_vault","cell":[10,7],"target":"vault","target_position":[120,125]}]
	value.rooms[2].resident = Pack.resident()
	value.appearance = Bindings.fresh()
	value.appearance.enemy_sprites.crawler = "art/test_art/beast"
	var indices: Array = [];indices.resize(176);indices.fill(-1);indices[51] = 1
	value.appearance.room_tiles.entry = {"atlas":"art/test_art/tiles","indices":indices}
	value.appearance.room_sprites = {"entry":{"secret":"art/test_art/beast","stairs":"art/test_art/beast"},"vault":{"resident":"art/test_art/beast"}}
	return value
static func remove(folder: String) -> void: Cleanup.remove(folder)

static func add_tall(folder: String) -> Dictionary:
	var sprite := Image.create(64,192,false,Image.FORMAT_RGBA8)
	for row in range(4):
		for frame in range(2):
			sprite.fill_rect(Rect2i(frame*32,row*48,32,48),[Color.RED,Color.GREEN,Color.YELLOW,Color.CYAN][row])
			sprite.fill_rect(Rect2i(frame*32,row*48+32,32,16),Color.BLUE if frame==0 else Color.MAGENTA)
	sprite.save_png(folder.path_join("tall_source.png"))
	return Importer.import_png(folder,folder.path_join("tall_source.png"),"test_art","tall","sprite",16,["down","up","right","left"],2,7,[32,48],[16,24],[-2,-8])
static func clips() -> Dictionary:
	return {"idle":{"frames":[0],"frame_ticks":9,"loop":true},"walk":{"frames":[1,2],"frame_ticks":4,"loop":true},"attack":{"frames":[3,4],"frame_ticks":3,"loop":false}}
static func add_clips(folder: String) -> Dictionary:
	var image := Image.create(80,48,false,Image.FORMAT_RGBA8)
	var colors := [Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW,Color.MAGENTA]
	for row in range(2):
		for frame in range(5):
			image.fill_rect(Rect2i(frame*16,row*24,16,24),colors[frame])
			image.fill_rect(Rect2i(frame*16,row*24+22,16,2),Color.WHITE if row==1 else Color.BLACK)
	image.save_png(folder.path_join("clips_source.png"))
	return Importer.import_png(folder,folder.path_join("clips_source.png"),"test_art","clips","sprite",16,["down","right"],5,6,[16,24],[16,24],[0,-8],clips())
