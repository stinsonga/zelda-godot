class_name GameAudio
extends Node

signal cue_played(cue: StringName)
signal music_changed(cue: StringName)
var bank = preload("res://scripts/audio_bank.gd").new()
var music: AudioStreamPlayer
var jingle: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var current_music: StringName
var muted := false
var suspended := false
var history: Array[StringName] = []
var voice_cursor := 0

func _ready() -> void:
	music = AudioStreamPlayer.new()
	music.volume_db = -8
	add_child(music)
	jingle = AudioStreamPlayer.new()
	jingle.volume_db = -5
	add_child(jingle)
	jingle.finished.connect(finish_jingle)
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -5
		add_child(voice)
		voices.append(voice)

func configure(custom: Resource = null, imported: bool = false) -> void:
	bank.streams.clear()
	if imported:
		var path := "res://imported/audio/manifest.json"
		if FileAccess.file_exists(path):
			var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
			if manifest is Dictionary and manifest.get("format") == 1:
				for cue in manifest.cues:
					var data: Dictionary = manifest.cues[cue]
					var stream := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://imported/audio/" + data.file))
					if stream != null:
						if data.loop_end > 0:
							stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
							stream.loop_begin = int(data.loop_begin)
							stream.loop_end = int(data.loop_end)
						bank.streams[StringName(cue)] = stream
	# Original, generated placeholder tones keep source-only projects audible.
	for cue in ["attack", "player_hurt", "enemy_hit", "enemy_die", "heart", "rupee", "item", "parry", "secret", "item_fanfare", "overworld", "cave", "text", "key", "bomb_drop", "bomb_blow", "flame", "dungeon", "level_9", "arrow", "recorder"]:
		if not bank.streams.has(StringName(cue)):
			bank.streams[StringName(cue)] = placeholder(cue)
	if custom != null:
		for cue in custom.streams: bank.streams[cue] = custom.streams[cue]

func placeholder(cue: String) -> AudioStreamWAV:
	var track := cue in ["overworld", "cave", "dungeon", "level_9"]
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
	jingle.stop()
	music.stop()
	music.stream = bank.streams.get(cue)
	if music.stream != null: music.play()
	apply_pause()
	music_changed.emit(cue)

func play(cue: StringName) -> void:
	if not bank.streams.has(cue): return
	history.append(cue)
	if history.size() > 32: history.pop_front()
	cue_played.emit(cue)
	if cue == &"item_fanfare":
		jingle.stream = bank.streams[cue]
		jingle.play()
	else:
		var voice := voices[voice_cursor]
		voice_cursor = (voice_cursor + 1) % voices.size()
		voice.stream = bank.streams[cue]
		voice.play()
	apply_pause()

func finish_jingle() -> void:
	apply_pause()

func apply_pause() -> void:
	music.stream_paused = suspended or jingle.playing
	jingle.stream_paused = suspended
	music.volume_db = -80 if muted else -8
	jingle.volume_db = -80 if muted else -5
	for voice in voices:
		voice.stream_paused = suspended
		voice.volume_db = -80 if muted else -5

func silence() -> void:
	current_music = &""
	music.stop()
	jingle.stop()
	for voice in voices: voice.stop()

func _exit_tree() -> void:
	suspended = false
	jingle.stream_paused = false
	music.stream_paused = false
	for voice in voices: voice.stream_paused = false
	silence()
	music.stream = null
	jingle.stream = null
	for voice in voices: voice.stream = null
