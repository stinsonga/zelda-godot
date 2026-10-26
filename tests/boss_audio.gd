extends SceneTree
const Actor = preload("res://scripts/enemy_actor.gd")
const Spawn = preload("res://scripts/enemy_spawn.gd")
const Enemy = preload("res://scripts/enemy_definition.gd")
var failures := 0
var world: Node
func _initialize() -> void:
	create_timer(60).timeout.connect(func() -> void: push_error("Boss audio suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.combat.enemies.clear()
	check_samples()
	check_ambience()
	check_songs()
	check_imports()
	world.free()
	print("Boss audio checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
func check_samples() -> void:
	var actor = Actor.new()
	actor.definition = Enemy.new()
	for family in ["aquamentus","gleeok","dodongo","gohma","digdogger","manhandla","patra"]:
		actor.definition.behavior = family
		actor.definition.size = Vector2i(32,32)
		var expected: StringName = &"roar_aquamentus" if family in ["aquamentus","gleeok"] else &"roar_dodongo" if family in ["dodongo","gohma"] else &"roar_manhandla"
		check(actor.appearance_sound() == expected, "Source spawn sample " + family)
	actor.definition.appearance_sample = &"custom_roar"
	check(actor.appearance_sound() == &"custom_roar", "Custom enemy can override its appearance sample")
	actor.definition.hurt_sample = &"custom_hit"
	actor.definition.death_sample = &"custom_death"
	check(actor.hurt_sound() == &"custom_hit" and actor.death_sound() == &"custom_death", "Custom enemy can override hit and death samples")
	var audio = world.audio
	audio.set_ambient(&"ambient_roar_aquamentus")
	check(audio.ambient.playing, "Room ambient loop starts")
	var stream: AudioStream = audio.ambient.stream
	audio.set_ambient(&"ambient_roar_aquamentus")
	check(audio.ambient.stream == stream, "Repeated ambient selection retains stream")
	audio.play(&"boss_hit")
	check(audio.sample.playing and audio.ambient.stream_paused, "Foreground sample takes priority over ambient roar")
	audio.sample.stop()
	audio.apply_pause()
	check(audio.ambient.stream_paused, "Ambient roar waits for source sample counter after foreground finishes")
	for i in range(159): audio.tick_warning(false)
	check(audio.ambient.stream_paused, "Ambient sample waits the full A0 ticks")
	audio.tick_warning(false)
	check(not audio.ambient.stream_paused, "Ambient roar resumes on the source 160-frame cycle")
	audio.play(&"boss_hit")
	audio.suspended = true
	audio.apply_pause()
	check(audio.sample.stream_paused and audio.ambient.stream_paused, "Sample and ambient voices respect focus pause")
	audio.suspended = false
	audio.warning_block_ticks = 0
	audio.play(&"player_hurt")
	audio.tick_warning(true)
	check(audio.warning.playing and audio.sample.playing, "DMC player hurt does not occupy Tune0 warning channel")
	audio.bank.streams[&"custom_cry"] = audio.placeholder("custom_cry")
	audio.play_sample(&"custom_cry")
	check(audio.sample.stream == audio.bank.streams[&"custom_cry"], "Custom sample uses foreground sample channel")
	audio.silence()
	check(not audio.sample.playing and not audio.ambient.playing, "Silence stops both sample voices")
func check_ambience() -> void:
	world.room = world.room.duplicate(true)
	world.room.ambient_sample = &"ambient_roar_dodongo"
	world.room.ambient_boss_room = &"boss_watch"
	world.update_ambient_audio()
	check(world.audio.current_ambient == &"ambient_roar_dodongo", "Nearby room hears living boss")
	world.state.room_records["boss_watch"] = {"kills":1,"cleared":true}
	world.update_ambient_audio()
	check(world.audio.current_ambient.is_empty(), "Defeated boss stops roar in nearby rooms")
	world.room.ambient_boss_room = world.room.id
	world.combat.enemies.clear()
	world.update_ambient_audio()
	check(world.audio.current_ambient.is_empty(), "Cleared current boss room is quiet immediately")
	world.room.ambient_sample = &""
	world.room.ambient_boss_room = &""
	var actor = Actor.new()
	actor.definition = Enemy.new()
	actor.definition.behavior = "aquamentus"
	world.combat.enemies.assign([actor])
	world.update_ambient_audio()
	check(world.audio.current_ambient == &"ambient_boss_roar_aquamentus", "Living boss latches background roar even without room sound flags")
	actor.health = 0
	world.update_ambient_audio()
	check(world.audio.current_ambient.is_empty(), "Boss death clears initializer background roar")
	world.combat.enemies.clear()

func check_songs() -> void:
	world.audio.history.clear()
	var pickup = preload("res://scripts/pickup_definition.gd").new()
	pickup.id = &"audio_triforce"
	pickup.item = preload("res://content/items/triforce.tres")
	pickup.position = world.player.pixel_position()
	world.room.pickups.assign([pickup])
	world.state.current_level = 1
	world.audio.set_music(&"dungeon")
	world.try_pickups()
	check(world.audio.history.count(&"end_level") == 1 and not world.audio.history.has(&"item_fanfare"), "Triforce piece requests end-level song exactly once")
	world.audio.set_music(&"overworld")
	check(world.audio.jingle.playing and world.audio.music.stream_paused, "Overworld transition preserves full end-level fanfare")
	world.level_exit_remaining = 0
	world.lift_remaining = 0
	world.audio.silence()
	world.state.health = 0
	world.phase_step = ""
	for i in range(33): world.tick_death()
	check(world.audio.history.has(&"death"), "Death sequence requests its own early tune")
	world.state.health = world.state.max_health
	world.game_phase = "play"
	var spawn = Spawn.new()
	spawn.id = &"ganon_audio"
	spawn.enemy = preload("res://content/enemies/ganon.tres")
	var ganon = Actor.new()
	ganon.setup(spawn)
	ganon.family.ganon = preload("res://scripts/ganon.gd").new()
	ganon.family.ganon.cues.assign([&"ganon_song"])
	world.combat.apply_ganon_cues(world,ganon)
	check(world.audio.current_music == &"ganon_song", "Ganon scene requests its own source song")
	ganon.family.ganon.cues.assign([&"level_music"])
	world.combat.apply_ganon_cues(world,ganon)
	check(world.audio.current_music == world.room.music, "Ganon fight restores level song")
func check_imports() -> void:
	if not ResourceLoader.exists("res://imported/world.tres"): return
	for catalog in ["res://imported/world.tres","res://imported/world_q2.tres"]:
		if not ResourceLoader.exists(catalog): continue
		var definition: Resource = load(catalog)
		var found := 0
		for room in definition.rooms:
			if room.ambient_sample.is_empty(): continue
			found += 1
			check(not room.ambient_boss_room.is_empty(), "Imported ambient room tracks its level boss")
		check(found > 0, "Quest imports ambient boss rooms " + catalog)
