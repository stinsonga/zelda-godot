extends RefCounted
## Runtime adapter: the editor's data contract builds the existing game resources.
const Appearance = preload("res://editor/shared/appearance.gd")
const Contract = preload("res://editor/shared/room_pack.gd")
const Room = preload("res://scripts/room_definition.gd")
const World = preload("res://scripts/world_definition.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Door = preload("res://scripts/door_definition.gd")
const Cave = preload("res://scripts/cave_definition.gd")
const Ware = preload("res://scripts/cave_ware.gd")
const Portal = preload("res://scripts/portal_definition.gd")
const Secret = preload("res://scripts/secret_definition.gd")
const Pickup = preload("res://scripts/pickup_definition.gd")
const DIRECTIONS := {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}
static func compile(pack: Dictionary, appearance: Dictionary = {}, library_root: String = "") -> Dictionary:
	var errors := Contract.validate(pack)
	if not errors.is_empty(): return {"errors":errors}
	var library = Appearance.new()
	var art_errors := Appearance.validate(appearance,pack) if not appearance.is_empty() else PackedStringArray()
	if not art_errors.is_empty(): appearance = {}
	appearance = Appearance.effective(pack,appearance)
	if Appearance.has_choices(appearance): library.configure(library_root if not library_root.is_empty() else ProjectSettings.globalize_path("res://"))
	var world = World.new()
	world.id = StringName("authored/" + pack.id)
	world.title = pack.title
	world.start_room = StringName(pack.start_room)
	for item in pack.get("starting_items",["wooden_sword"]): world.starting_items.append(load("res://content/items/"+item+".tres"))
	for goal in pack.get("goals",[]): world.completion_goals.append(goal.duplicate(true))
	world.visual_theme = load("res://content/themes/default.tres").duplicate(true)
	var definitions: Dictionary = {}
	for id in pack.enemy_types:
		var source: Dictionary = pack.enemy_types[id]
		var enemy = Enemy.new()
		enemy.id = StringName("custom_" + pack.id + "_" + id)
		enemy.title = source.title
		enemy.behavior = source.behavior
		enemy.health = int(source.health)
		enemy.speed_subpixels = int(source.speed_subpixels)
		enemy.contact_damage = int(source.contact_damage)
		enemy.shooting_enabled = source.get("shooting_enabled",false)
		enemy.fallback_color = Color("ec7967")
		if appearance.get("enemy_sprites",{}).has(id):
			var group: String = appearance.enemy_sprites[id]
			if library.enemy_texture(group) != null:
				enemy.sprite = StringName("__editor_" + id)
				enemy.sprite_style = "directional"
				var visual: Dictionary = library.groups[group]
				if visual.get("authored",false):
					enemy.authored_frame_count = int(visual.frame_count)
					enemy.authored_clips = visual.get("clips",{}).duplicate(true)
					var layout := library.sprite_layout(group)
					enemy.authored_draw_size = layout.size;enemy.authored_draw_offset = layout.position
					enemy.animation_frame_ticks = int(visual.frame_ticks)
				for direction in ["down","up","right","left"]:
					for pose in range(maxi(2,enemy.authored_frame_count)): world.visual_theme.sprites[StringName("%s_%s_%d" % [enemy.sprite,direction,pose])] = library.enemy_texture(group,direction,pose)
				for pose in range(8): world.visual_theme.sprites[StringName("%s_%d" % [enemy.sprite,pose])] = library.enemy_texture(group,"down",pose)
		definitions[id] = enemy
	for source in pack.rooms:
		var room = Room.new()
		room.id = StringName(source.id)
		room.title = source.title
		room.tiles = "\n".join(source.tiles)
		room.spawn = Vector2i(int(source.spawn[0]),int(source.spawn[1]))
		room.grid_origin = Vector2i(0,5)
		room.movement_bounds = Rect2i(0,-3,241,161)
		room.dungeon_level = 10
		room.map_room_id = (15+int(source.map_position[1]))*16+int(source.map_position[0])
		room.shutter_trigger = int(source.shutter_trigger)
		room.enemy_persistence = "reset"
		room.music = &""
		if source.has("secret"):
			var secret = Secret.new()
			secret.trigger = Contract.secret_trigger(source.secret)
			secret.cell = Vector2i(int(source.secret.cell[0]),int(source.secret.cell[1]))
			secret.reveal_cell = secret.cell
			secret.block_direction = DIRECTIONS[source.secret.direction] if secret.trigger == "block" else Vector2i.ZERO
			secret.reveal_kind = source.secret.reveal
			secret.persistent = secret.trigger != "block"
			secret.authored_object = secret.trigger != "block"
			room.secret = secret
		room.tile_atlas = library.room_texture(source,appearance)
		var cell := library.room_cell_size(source,appearance)
		room.atlas_cell_size = Vector2i(cell,cell)
		for slot in appearance.get("room_sprites",{}).get(source.id,{}):
			var id: String = appearance.room_sprites[source.id][slot]
			var frames := library.sprite_frames(id,"idle")
			if not frames.is_empty():
				room.authored_sprites[slot] = frames
				room.authored_sprite_layouts[slot] = library.sprite_layout(id)
				room.authored_frame_ticks[slot] = library.clip_ticks(id,"idle")
		if room.tile_atlas != null:
			for index in range(176): room.tile_indices.append(index)
		for edge in source.connections:
			var link: Dictionary = source.connections[edge]
			room.exits[edge] = link.target
			var door = Door.new()
			door.direction = DIRECTIONS[edge]
			door.kind = link.kind
			for item in link.get("requires",[]): door.required_items[StringName(Contract.ITEM_SLOTS[item])] = 1
			room.doors.append(door)
		if source.has("resident"):
			var data: Dictionary = source.resident
			var cave = Cave.new()
			cave.id = StringName(String(source.id)+"_resident")
			cave.person_sprite = &"__authored_resident"
			cave.text = data.text
			cave.choose = data.mode != "hint"
			cave.show_items = cave.choose
			cave.pay = data.mode == "shop"
			cave.show_prices = cave.pay
			cave.negative_prices = cave.pay
			cave.remember = data.mode == "gift"
			for i in range(3):
				if data.wares[i] == null: continue
				var ware = Ware.new()
				ware.item = load("res://content/items/"+String(data.wares[i].item)+".tres")
				ware.price = int(data.wares[i].price)
				cave.wares[i] = ware
			room.cave = cave
		for stair in source.get("stairs",[]):
			var portal = Portal.new()
			portal.area = Rect2i(Contract.stair_position(stair),Vector2i.ONE)
			portal.target_room = StringName(stair.target)
			portal.target_position = Vector2i(int(stair.target_position[0]),int(stair.target_position[1]))
			portal.requires_secret = stair.get("requires_secret",false)
			portal.show_stairs = true
			room.portals.append(portal)
		for placement in source.enemies:
			var spawn = Spawn.new()
			spawn.id = StringName(placement.id)
			spawn.enemy = definitions[placement.type]
			spawn.position = Vector2i(int(placement.position[0]),int(placement.position[1]))
			room.enemies.append(spawn)
		for placement in source.pickups:
			var pickup = Pickup.new()
			pickup.id = StringName(placement.id)
			pickup.item = load("res://content/items/" + placement.item + ".tres")
			pickup.position = Vector2i(int(placement.position[0]),int(placement.position[1]))
			pickup.tolerance = Vector2i(8,8)
			pickup.lift_ticks = 0
			pickup.requires_clear = placement.get("requires_clear",false)
			pickup.requires_secret = placement.get("requires_secret",false)
			room.pickups.append(pickup)
		errors.append_array(room.validation_errors())
		world.rooms.append(room)
	art_errors.append_array(library.warnings)
	return {"errors":errors,"world":world,"appearance_warnings":art_errors}
