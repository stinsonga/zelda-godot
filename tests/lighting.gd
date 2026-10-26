extends SceneTree
var failures:=0
func _initialize()->void:
	create_timer(30).timeout.connect(func()->void:push_error("Lighting suite timed out");quit(1))
	call_deferred("run")
func check(value:bool,message:String)->void:
	if not value:
		failures+=1
		push_error(message)
func run()->void:
	var world=preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var dark:Resource=world.room.duplicate()
	dark.id=&"lighting_dark"
	dark.dark_room=true
	dark.dungeon_level=10
	dark.enemies.clear()
	world.enter_room(dark,Vector2i(120,125),Vector2i.UP)
	var at:Vector2i=world.player.pixel_position()
	var stages:Array[int]=[]
	for tick in range(31):
		world.simulate_tick(Vector2i.LEFT,true,true)
		stages.append(world.lighting.stage)
	check(stages[0]==0 and stages[9]==0 and stages[10]==1 and stages[20]==2 and stages[30]==3,"Dark entry must write four palette steps ten ticks apart")
	check(world.player.pixel_position()==at and not world.lighting.fading(),"Entry fade must hold Link until complete")
	world.state.take_item(preload("res://content/items/blue_candle.tres"))
	world.state.selected_item=&"candle"
	check(world.use_item(),"Candle must be usable in the dark")
	for tick in range(31):world.simulate_tick(Vector2i.ZERO)
	check(world.lighting.stage==3 and not world.lighting.fading(),"Moving candle fire must not light the room early")
	world.simulate_tick(Vector2i.ZERO)
	check(world.lighting.fading(),"Standing fire must begin the room brightening cycle")
	at=world.player.pixel_position()
	stages.clear()
	for tick in range(31):
		world.simulate_tick(Vector2i.LEFT)
		stages.append(world.lighting.stage)
	check(stages[0]==3 and stages[10]==2 and stages[20]==1 and stages[30]==0,"Candle must reverse the same four palette steps")
	check(world.player.pixel_position()==at and not world.lighting.fading(),"Candle brightening must hold gameplay")
	check(world.item_objects[0].timer<=32,"Standing fire's hardware timer must keep counting during the fade")
	check(not world.use_item(),"Lighting must preserve the blue candle once-per-room limit")
	for tick in range(80):world.simulate_tick(Vector2i.ZERO)
	check(world.lighting.stage==0 and world.item_objects.is_empty(),"Room light must persist after candle fire expires")
	var custom:Resource=dark.duplicate()
	custom.light_step_ticks=3
	var custom_lighting=preload("res://scripts/room_lighting.gd").new()
	custom_lighting.enter(custom,false,0,true,false)
	custom_lighting.candle(custom)
	for tick in range(10):custom_lighting.tick()
	check(custom_lighting.stage==0 and not custom_lighting.fading(),"Authored lighting must honor its editable step interval")
	world.enter_room(dark,Vector2i(120,125),Vector2i.UP)
	check(world.lighting.fading(),"A lit dark room must become dark again when revisited")
	for tick in range(31):world.simulate_tick(Vector2i.ZERO)
	world.enter_room(dark,Vector2i(120,125),Vector2i.UP)
	check(world.lighting.stage==3 and not world.lighting.fading(),"Dark-to-dark entry must retain darkness without another fade")
	var light:Resource=dark.duplicate()
	light.id=&"lighting_light"
	light.dark_room=false
	world.enter_room(light,Vector2i(120,125),Vector2i.UP)
	check(world.lighting.fading() and world.lighting.stage==3,"Leaving an unlit room must brighten the next light room")
	for tick in range(31):world.simulate_tick(Vector2i.ZERO)
	check(world.lighting.stage==0,"Light room must finish with its normal palette")
	world.enter_room(dark,Vector2i(120,125),Vector2i.UP,0,true)
	check(world.lighting.stage==3 and not world.lighting.fading() and not world.candle_used,"Checkpoint rebuild must reset temporary candle light")
	var invalid:Resource=dark.duplicate()
	invalid.dark_tile_atlases.assign([null])
	check(not invalid.validation_errors().is_empty(),"Malformed lighting assets must fail room validation")
	# Scrolling uses one global palette: darken before entering, brighten after leaving.
	for candidate in [dark,light]:
		candidate.collision_tiles.resize(704)
		candidate.collision_tiles.fill(0)
		world.rooms[candidate.id]=candidate
	light.exits["right"]=String(dark.id)
	dark.exits["left"]=String(light.id)
	world.enter_room(light,Vector2i(240,77),Vector2i.RIGHT,0,true)
	world.try_exit(Vector2i.RIGHT)
	check(world.transition!=null and world.lighting.fading(),"Lit-to-dark scrolling must darken before the scroll")
	for tick in range(31):world.simulate_tick(Vector2i.ZERO)
	check(world.transition.distance==0 and world.lighting.stage==3,"Scroll must remain held through the four darkening steps")
	for tick in range(64):world.simulate_tick(Vector2i.ZERO)
	check(world.room==dark and not world.lighting.fading(),"Dark arrival must not run a second fade")
	world.try_exit(Vector2i.LEFT)
	for tick in range(64):world.simulate_tick(Vector2i.ZERO)
	check(world.room==light and world.lighting.fading() and world.lighting.stage==3,"Dark-to-lit scrolling must brighten on arrival")
	for tick in range(31):world.simulate_tick(Vector2i.ZERO)
	check(world.lighting.stage==0,"Return room must finish brightening")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world=preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		var count:=0
		for candidate in world.room_resources:
			if candidate.dark_room:
				check(candidate.dark_tile_atlases.size()==3,"Every imported dark room must provide three palette atlases")
				count+=1
		check(count==35,"Dark-room flags must import from dungeon attribute E")
		var ganon_room:Resource
		for candidate in world.room_resources:
			if candidate.enemies.any(func(s:Resource)->bool:return s.enemy.behavior=="ganon"):ganon_room=candidate;break
		check(ganon_room!=null,"Ganon room must be imported")
		if ganon_room!=null:
			world.enter_room(ganon_room,ganon_room.spawn,Vector2i.UP)
			check(world.lighting_stage()==3 and not world.lighting.fading(),"Ganon must own the initial dark palette without a second fade")
			var fight=world.combat.enemies.filter(func(a:RefCounted)->bool:return a.definition.behavior=="ganon")[0].family.ganon
			for i in range(4):
				fight.darkness=i
				check(world.terrain_atlas(ganon_room)==(ganon_room.tile_atlas if i==0 else ganon_room.dark_tile_atlases[i-1]),"Ganon's intro must select the corresponding source palette")
			fight.darkness=0
			check(world.lighting_stage()==0,"Ganon's fully lit room must remain bright")
		world.free()
	print("Lighting checks: ","PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
