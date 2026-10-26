class_name GameAudio
extends Node

signal cue_played(cue: StringName)
signal music_changed(cue: StringName)
var bank = preload("res://scripts/audio_bank.gd").new()
var music: AudioStreamPlayer
var jingle: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var current_jingle: StringName
var current_music: StringName
var muted := false
var suspended := false
var history: Array[StringName] = []
var voice_cursor := 0
var sample: AudioStreamPlayer
var ambient: AudioStreamPlayer
var ambient_delay_ticks := 0
var current_ambient: StringName
const SAMPLE_CUES := [&"player_hurt", &"door", &"boss_hit", &"sword_beam", &"roar_aquamentus", &"roar_dodongo", &"roar_manhandla"]
var warning: AudioStreamPlayer
var warning_ticks := 0
var warning_period_ticks := 19
var warning_block_ticks := 0
const WARNING_PRIORITY_CUES := [&"enemy_hit", &"parry", &"heart", &"text", &"key", &"bomb_drop"]

func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -8
	add_child(music)
	jingle = AudioStreamPlayer.new()
	jingle.volume_db = -5
	add_child(jingle)
	jingle.finished.connect(finish_jingle)
	sample = AudioStreamPlayer.new()
	add_child(sample)
	sample.finished.connect(apply_pause)
	ambient = AudioStreamPlayer.new()
	add_child(ambient)
	warning = AudioStreamPlayer.new()
	add_child(warning)
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -5
		add_child(voice)
		voices.append(voice)

func configure(custom: Resource = null, imported: bool = false) -> void:
	bank.streams.clear()
	warning_period_ticks = 19
	warning_ticks = 0
	warning_block_ticks = 0
	if imported:
		var path := "res://imported/audio/manifest.json"
		if FileAccess.file_exists(path):
			var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
			if manifest is Dictionary and manifest.get("format") == 1:
				for cue in manifest.cues:
					var data: Dictionary = manifest.cues[cue]
					if cue == "low_health": warning_period_ticks = maxi(1, int(data.get("repeat_ticks", 19)))
					var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://imported/audio/" + data.file))
					if stream != null:
						if data.loop_end > 0:
							stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
							stream.loop_begin = int(data.loop_begin)
							stream.loop_end = int(data.loop_end)
						bank.streams[StringName(cue)] = stream
	# Original, generated placeholder tones keep source-only projects audible.
	for cue in ["attack", "player_hurt", "enemy_hit", "enemy_die", "heart", "rupee", "item", "parry", "secret", "item_fanfare", "overworld", "cave", "text", "key", "bomb_drop", "bomb_blow", "flame", "dungeon", "level_9", "arrow", "recorder", "magic", "door", "menu_select", "low_health", "boss_hit", "sword_beam", "roar_aquamentus", "roar_dodongo", "roar_manhandla", "ambient_roar_aquamentus", "ambient_roar_dodongo", "ambient_roar_manhandla", "ambient_boss_roar_aquamentus", "ambient_boss_roar_dodongo", "ambient_boss_roar_manhandla", "end_level", "ganon_song", "death"]:
		if not bank.streams.has(StringName(cue)):
			bank.streams[StringName(cue)] = placeholder(cue)
	if custom != null:
		for cue in custom.streams: bank.streams[cue] = custom.streams[cue]

func placeholder(cue: String) -> AudioStreamWAV:
	var track := cue in ["overworld", "cave", "dungeon", "level_9"] or cue.begins_with("ambient_roar_") or cue.begins_with("ambient_boss_roar_")
	var seconds := 4.0 if track else (0.6 if cue in ["secret", "item_fanfare"] else 0.12)
	var count := int(22050 * seconds)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var base := 180.0 + float(absi(cue.hash()) % 320)
	for i in range(count):
		var t := float(i) / 22050.0
		var note := int(t * 2) % 4
		var frequency: float = base * [1.0, 1.125, 1.5, 1.25][note] if track else base * (1.0 + t)
		var envelope := 0.15 * (1.0 - fmod(t, 0.5) * 2.0) if track else 0.25 * (1.0 - float(i) / count)
		bytes.encode_s16(i * 2, int(sin(TAU * frequency * t) * envelope * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = bytes
	if track:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = count
	return stream

func set_music(cue: StringName) -> void:
	if current_music == cue: return
	current_music = cue
	if current_jingle != &"end_level":
		jingle.stop()
		current_jingle = &""
	music.stop()
	music.stream = bank.streams.get(cue)
	if music.stream != null: music.play()
	apply_pause()
	music_changed.emit(cue)

## Room background samples use one looping voice; foreground DMC samples take
## precedence, resuming the background when the foreground recording finishes.
func set_ambient(cue: StringName) -> void:
	if current_ambient == cue: return
	current_ambient = cue
	ambient_delay_ticks = 0
	ambient.stop()
	ambient.stream = bank.streams.get(cue)
	if ambient.stream != null: ambient.play()
	apply_pause()

## The original only grants the warning Tune0 when no other Tune0 is active.
func tick_warning(enabled: bool) -> void:
	if ambient_delay_ticks > 0:
		ambient_delay_ticks -= 1
		if ambient_delay_ticks == 0: apply_pause()
	warning_block_ticks = maxi(0, warning_block_ticks - 1)
	if not enabled:
		warning_ticks = 0
		warning.stop()
		return
	warning_ticks = maxi(0, warning_ticks - 1)
	if warning_ticks == 0 and warning_block_ticks == 0:
		play(&"low_health")
		warning_ticks = warning_period_ticks

func play_sample(cue: StringName) -> void:
	play(cue, true)

func play(cue: StringName, sample_channel: bool = false) -> void:
	if not bank.streams.has(cue): return
	history.append(cue)
	if history.size() > 32: history.pop_front()
	cue_played.emit(cue)
	if cue in WARNING_PRIORITY_CUES:
		warning.stop()
		warning_block_ticks = maxi(1, ceili(bank.streams[cue].get_length() * 60))
	if sample_channel or cue in SAMPLE_CUES:
		if not current_ambient.is_empty():
			ambient_delay_ticks = 0xA0
			ambient.seek(0)
		sample.stream = bank.streams[cue]
		sample.play()
	elif cue == &"low_health":
		warning.stream = bank.streams[cue]
		warning.play()
	elif cue in [&"item_fanfare", &"end_level"]:
		current_jingle = cue
		jingle.stream = bank.streams[cue]
		jingle.play()
	else:
		var voice := voices[voice_cursor]
		voice_cursor = (voice_cursor + 1) % voices.size()
		voice.stream = bank.streams[cue]
		voice.play()
	apply_pause()

func finish_jingle() -> void:
	current_jingle = &""
	apply_pause()

func apply_pause() -> void:
	music.stream_paused = suspended or jingle.playing
	jingle.stream_paused = suspended
	music.volume_db = -80 if muted else -8
	jingle.volume_db = -80 if muted else -5
	sample.stream_paused = suspended
	ambient.stream_paused = suspended or sample.playing or ambient_delay_ticks > 0
	sample.volume_db = -80 if muted else -5
	ambient.volume_db = -80 if muted else -8
	warning.stream_paused = suspended
	warning.volume_db = -80 if muted else -5
	for voice in voices:
		voice.stream_paused = suspended
		voice.volume_db = -80 if muted else -5

func silence() -> void:
	current_music = &""
	current_jingle = &""
	music.stop()
	jingle.stop()
	for voice in voices: voice.stop()
	warning.stop()
	sample.stop()
	ambient.stop()
	current_ambient = &""
	ambient_delay_ticks = 0
	warning_ticks = 0
	warning_block_ticks = 0

func _exit_tree() -> void:
	suspended = false
	jingle.stream_paused = false
	warning.stream_paused = false
	sample.stream_paused = false
	ambient.stream_paused = false
	music.stream_paused = false
	for voice in voices: voice.stream_paused = false
	silence()
	music.stream = null
	jingle.stream = null
	warning.stream = null
	sample.stream = null
	ambient.stream = null
	for voice in voices: voice.stream = null
