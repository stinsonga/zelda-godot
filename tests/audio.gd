extends SceneTree
var failures := 0
func _initialize() -> void:
	create_timer(10).timeout.connect(func() -> void: push_error("Audio suite timed out"); quit(1))
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var world = preload("res://scenes/combat_lab.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.combat.enemies.clear()
	var audio = world.audio
	check(audio.bank.streams.size() == 21, "Source-only audio must include all cues")
	var track: AudioStream = audio.music.stream
	audio.set_music(&"overworld")
	check(audio.music.stream == track, "Same music selection must retain the current stream")
	audio.set_music(&"cave")
	check(audio.current_music == &"cave" and audio.music.stream != track, "Cave selection must change the music stream")
	audio.set_music(&"")
	check(audio.music.stream == null and not audio.music.playing, "Empty room music must select silence")
	audio.set_music(&"overworld")
	audio.play(&"item_fanfare")
	check(audio.music.stream_paused and audio.jingle.playing, "Item fanfare must pause background music")
	audio.jingle.stop()
	audio.finish_jingle()
	check(not audio.music.stream_paused, "Finishing the fanfare must resume music")
	audio.suspended = true
	audio.apply_pause()
	check(audio.music.stream_paused, "Focus suspension must pause audio")
	audio.suspended = false
	audio.apply_pause()
	world.state.equipped_weapon = preload("res://content/items/wooden_sword.tres")
	audio.history.clear()
	world.simulate_tick(Vector2i.ZERO, true)
	check(audio.history.count(&"attack") == 1, "Starting a sword attack must emit one attack cue")
	world.simulate_tick(Vector2i.ZERO, true)
	check(audio.history.count(&"attack") == 1, "Holding an active attack must not restart the cue")
	world.combat.player_invulnerability = 0
	check(world.combat.hurt_player(world, 1, Vector2i.ZERO), "Damage fixture must hit")
	check(audio.history.back() == &"player_hurt", "Accepted damage must emit the hurt cue")
	var size: int = audio.history.size()
	check(not world.combat.hurt_player(world, 1, Vector2i.ZERO), "Invulnerability must reject repeat damage")
	check(audio.history.size() == size, "Rejected damage must stay silent")
	world.combat.shove_remaining = 0
	world.sword.phase = -1
	var drop = preload("res://scripts/dropped_reward.gd").new()
	drop.definition = preload("res://content/items/heart.tres")
	drop.age = 31
	drop.position = world.player.pixel_position()
	world.combat.rewards.append(drop)
	world.combat.tick(world)
	check(audio.history.back() == &"heart" and drop.collected, "Heart collection must emit the heart cue")
	size = audio.history.size()
	world.combat.tick(world)
	check(audio.history.size() == size, "Collected drops must not replay audio")
	check(world.reveal_secret("audio_fixture") and audio.history.back() == &"secret", "New secrets must play the secret cue")
	size = audio.history.size()
	check(not world.reveal_secret("audio_fixture") and audio.history.size() == size, "Persistent secrets must sound only once")
	world.player.place(Vector2i(80, 77))
	world.player.facing = Vector2i.RIGHT
	world.sword.phase = -1
	world.combat.player_invulnerability = 0
	var rock = preload("res://scripts/rock_projectile.gd").new()
	rock.source_rules = true
	rock.speed_subpixels = 768
	rock.subposition = Vector2i(96, 77) * 256
	rock.direction = Vector2i.LEFT
	for tick in range(3): world.combat.tick_source_rock(world, rock)
	check(audio.history.back() == &"parry", "Successful shield parry must emit its cue")
	var spawn = preload("res://scripts/enemy_spawn.gd").new()
	spawn.id = &"audio_enemy"
	spawn.enemy = preload("res://content/enemies/red_octorok.tres")
	spawn.position = Vector2i(96, 77)
	spawn.spawn_ticks = 0
	var enemy = preload("res://scripts/enemy_actor.gd").new()
	enemy.setup(spawn)
	world.combat.enemies.append(enemy)
	world.sword.phase = 1
	world.sword.direction = Vector2i.RIGHT
	world.sword.weapon = world.state.equipped_weapon
	world.sword.beam_attempted = true
	audio.history.clear()
	world.combat.tick(world)
	check(audio.history.has(&"enemy_hit") and audio.history.has(&"enemy_die"), "Lethal sword damage must emit hurt and death cues")
	size = audio.history.size()
	world.combat.tick(world)
	check(audio.history.size() == size, "A dying enemy must not replay damage sounds")
	world.state.health = 1
	world.combat.player_invulnerability = 0
	world.combat.hurt_player(world, 1, Vector2i.ZERO)
	check(not audio.music.playing and audio.history.back() == &"player_hurt", "Death must stop music and retain final damage audio")
	world.enter_room(world.room, world.room.spawn, Vector2i.UP)
	check(audio.current_music == &"overworld", "Retry/load room selection must restore room music")
	world.free()
	if ResourceLoader.exists("res://imported/world.tres"):
		world = preload("res://scenes/main.tscn").instantiate()
		root.add_child(world)
		world.set_physics_process(false)
		if FileAccess.file_exists("res://imported/audio/manifest.json"):
			check(world.audio.music.stream.loop_begin > 0, "Imported overworld music must preserve intro and repeat the source phrase loop")
		world.enter_room(world.rooms[&"cave_77"], Vector2i(120, 125), Vector2i.UP)
		check(world.audio.current_music == &"cave", "Imported cave must select its configured music")
		world.free()
	await create_timer(0.1).timeout
	print("Audio checks: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
