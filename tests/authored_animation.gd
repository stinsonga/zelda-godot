extends SceneTree
const Fixture = preload("res://editor/tests/authored_art_fixture.gd")
const Templates = preload("res://editor/shared/dungeon_templates.gd")
const Adapter = preload("res://scripts/authored_pack.gd")
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1;push_error(message)
func actor(enemy: Resource) -> RefCounted:
	var spawn = Spawn.new();spawn.id = &"test";spawn.enemy = enemy;spawn.position = Vector2i(80,77);spawn.facing = Vector2i.RIGHT
	var value = Actor.new();value.setup(spawn);value.spawn_remaining = 0;value.cloud_started = true;value.source.input_direction = Vector2i.RIGHT
	return value
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var folder := Fixture.create();Fixture.add_clips(folder)
	var pack := Fixture.pack();pack.enemy_types.crawler.shooting_enabled = true;pack.appearance.enemy_sprites.crawler = "art/test_art/clips"
	pack.appearance.room_sprites.entry.secret = "art/test_art/clips"
	var compiled := Adapter.compile(pack,{},folder)
	check(compiled.errors.is_empty() and compiled.appearance_warnings.is_empty(),"Named clips compile into native enemy")
	var enemy: Resource = compiled.world.rooms[1].enemies[0].enemy
	check(Templates.canonical(enemy.authored_clips)==Templates.canonical(Fixture.clips()) and enemy.shooting_enabled,"Native variant retains clips and existing shooting option")
	check(compiled.world.rooms[0].authored_sprites.secret.size()==1 and compiled.world.rooms[0].authored_frame_ticks.secret==9,"Room feature uses idle clip instead of cycling attack columns")
	var legacy: Resource = enemy.duplicate(true);legacy.authored_clips = {}
	var animated := actor(enemy);var reference := actor(legacy)
	var saw_attack := false;var shots := 0;var saw_walk := false
	for i in range(256):
		animated.source_random = 255;reference.source_random = 255;animated.source_next_random = 0;reference.source_next_random = 0
		var shot_a: bool = animated.tick(Vector2i(160,77),func(_at): return true)
		var shot_b: bool = reference.tick(Vector2i(160,77),func(_at): return true)
		check(shot_a==shot_b and animated.subposition==reference.subposition and animated.facing==reference.facing and animated.source.shoot_timer==reference.source.shoot_timer,"Clip playback leaves attack and movement trace unchanged at tick "+str(i))
		if shot_a: shots+=1
		if animated.authored_state=="attack":
			saw_attack = true
			check(animated.authored_frame() in [3,4],"Attack selects only attack columns")
			if animated.authored_state_ticks>=6: check(animated.authored_frame()==4,"Attack holds final frame while native attack timer runs")
		if animated.authored_state=="walk": saw_walk = true;check(animated.authored_frame() in [1,2],"Movement selects walking clip")
	check(saw_attack and shots>0 and saw_walk,"Live walker moves, winds up and shoots with named clips")
	var idle := actor(enemy);idle.definition = enemy.duplicate(true);idle.definition.shooting_enabled = false
	idle.tick(Vector2i(160,77),func(_at): return false)
	check(idle.authored_state=="idle" and idle.authored_frame()==0,"Blocked actor uses idle clip")
	var moving := actor(enemy);moving.definition = enemy.duplicate(true);moving.definition.shooting_enabled = false
	moving.tick(Vector2i(160,77),func(_at): return true)
	var frozen_state: String = moving.authored_state;var frozen_tick: int = moving.authored_state_ticks
	moving.tick(Vector2i(160,77),func(_at): return true,Callable(),true,{"clock":true})
	check(moving.authored_state==frozen_state and moving.authored_state_ticks==frozen_tick,"Clock freezes visual state and timing")
	moving.stun_ticks = 2;moving.tick(Vector2i(160,77),func(_at): return true)
	check(moving.authored_state_ticks==frozen_tick,"Stun freezes visual animation")
	var native: Resource = enemy.duplicate(true);native.behavior = "native";native.shoot_windup = 2
	var instant := actor(native);instant.windup = 1
	check(instant.tick(Vector2i(160,77),func(_at): return false),"Native attack release still occurs on its original tick")
	check(instant.authored_state=="attack" and instant.authored_frame()==3,"Instant release starts one-shot attack at frame zero")
	for i in range(5): instant.tick(Vector2i(160,77),func(_at): return false)
	check(instant.authored_state=="attack" and instant.authored_frame()==4,"Instant release displays complete visual clip")
	instant.tick(Vector2i(160,77),func(_at): return false)
	check(instant.authored_state=="idle","One-shot visual completes without extending gameplay attack")
	instant.windup = 1;instant.tick(Vector2i(160,77),func(_at): return false)
	check(instant.authored_frame()==3,"Next attack restarts clip")
	Fixture.remove(folder)
	print("Authored animation runtime checks: ","PASS" if failures==0 else "FAIL");call_deferred("finish")
func finish() -> void: quit(0 if failures==0 else 1)
