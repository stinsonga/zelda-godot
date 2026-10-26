extends SceneTree
## The title and story (Z_02 mode 0). Needs a local import; skips without one.
const Title = preload("res://scripts/title_demo.gd")
var failures := 0

class FakeAudio:
	extends Node
	var songs: Array[StringName] = []
	var silenced := 0
	func silence() -> void: silenced += 1
	func set_music(cue: StringName) -> void: songs.append(cue)

func _initialize() -> void:
	create_timer(120).timeout.connect(func() -> void: push_error("Title suite timed out"); quit(1))
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var data: Dictionary = Title.load_data()
	if data.is_empty():
		print("Title checks: SKIP (no local import)")
		quit(0)
		return
	check_cycle(data)
	check_start(data)
	print("Title checks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)

func stage(demo: RefCounted) -> String:
	return "%d/%s" % [demo.phase, str(demo.subphase) if demo.updating else "init"]

func check_cycle(data: Dictionary) -> void:
	var screen := NesScreen.new()
	var audio := FakeAudio.new()
	var demo = Title.new(data, screen, audio)
	# Run one whole cycle and time each stage.
	var stages: Array = []
	var lengths: Array = []
	var glow: Array = []
	var sprites_match := true
	for i in range(6000):
		var before := stage(demo)
		if stages.is_empty() or stages.back() != before:
			stages.append(before)
			lengths.append(0)
		lengths[lengths.size() - 1] += 1
		demo.tick(false)
		if before == "0/0" and stage(demo) == "0/0":
			glow.append(screen.palette[6])
			for j in range(112): sprites_match = sprites_match and screen.oam[j] == int(data.title_sprites[j])
		if before == "0/init" and stages.size() > 3: break
	var expected := ["0/init", "0/0", "0/1", "1/init", "1/0", "1/1", "1/2", "1/3", "1/4", "0/init"]
	check(stages == expected, "The demo runs title, fade, and the story's five stages, then starts over (%s)" % [stages])
	if stages != expected: return
	var fade_frames := 1
	for k in range(13): fade_frames += int(data.fade_delays[k])
	check(lengths[0] == 3 and lengths[3] == 3, "Each phase initializes over three frames")
	check(absi(lengths[1] - 512) <= 1, "The title shows for about 512 frames (%d)" % lengths[1])
	check(lengths[2] == fade_frames, "The fade follows its delay table (%d, %d)" % [lengths[2], fade_frames])
	check(absi(lengths[4] - 464) <= 1, "The prologue scrolls 232 lines at one every other frame (%d)" % lengths[4])
	check(lengths[5] == 256 and lengths[7] == 256 and lengths[8] == 0x39, "The pauses last 256, then 256 and $39 frames")
	check(absi(lengths[6] - 2816) <= 1, "The item list scrolls five and a half screens (%d)" % lengths[6])
	check(demo.item_row == data.left_items.size() and demo.text_index == data.text_lines.size() and demo.line_index == 175, "Every item row and text line was shown")
	check(sprites_match, "The title sprites are rewritten every frame")
	# The glow holds each color six frames, the last $10, then cycles again.
	var colors: Array = data.glow_colors
	var expected_glow: Array = []
	for step in range(8): for j in range(0x10 if step == 7 else 6): expected_glow.append(int(colors[step]))
	expected_glow.append(int(colors[0]))
	check(glow.slice(0, expected_glow.size()) == expected_glow, "The Triforce glows through its colors (%s)" % [glow.slice(0, 20)])
	demo.tick(false)
	demo.tick(false)
	check(audio.songs.count(&"title") == 2, "The title song starts again with each cycle")
	audio.free()
	screen.free()

func check_start(data: Dictionary) -> void:
	var screen := NesScreen.new()
	var audio := FakeAudio.new()
	var demo = Title.new(data, screen, audio)
	check(not demo.tick(true), "Start is ignored while the title initializes")
	for i in range(1500): demo.tick(false)
	check(demo.phase == 1, "By then the story is under way")
	check(demo.tick(true) and audio.silenced > 1, "Start leaves the story for the files, silencing it")
	audio.free()
	screen.free()
