extends AcceptDialog
signal library_changed
signal progress_changed(message: String)
var game_root := ""
var pid := -1
var busy := false
var job := ""
var last_state: Dictionary = {}
var python: LineEdit
var rom: LineEdit
var progress: ProgressBar
var message: Label
var logs: TextEdit
var validate_button: Button
var import_button: Button
var browse_button: Button
var rom_dialog: FileDialog
var poll_elapsed := 0.0
var content: VBoxContainer
func _ready() -> void:
	title = "Import original ROM assets"
	wrap_controls = false
	min_size = Vector2i(740,600)
	size = Vector2i(760,630)
	get_ok_button().text = "Close"
	var body := VBoxContainer.new()
	content = body
	add_child(body)
	var explanation := Label.new()
	explanation.text = "Select your US PRG0 .nes file. The ROM stays untouched.\nImport replaces only the generated library in imported/; the previous library is kept as a backup.\nAuthored packs are unchanged. Python 3.9+ is required."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(explanation)
	var python_row := HBoxContainer.new()
	body.add_child(python_row)
	var caption := Label.new()
	caption.text = "Python executable"
	python_row.add_child(caption)
	python = LineEdit.new()
	python.text = "python3"
	python.placeholder_text = "python3 or an absolute executable path"
	python.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	python_row.add_child(python)
	var config := ConfigFile.new()
	if config.load("user://import-settings.cfg") == OK: python.text = str(config.get_value("import","python","python3"))
	var rom_row := HBoxContainer.new()
	body.add_child(rom_row)
	rom = LineEdit.new()
	rom.placeholder_text = "Path to your .nes ROM"
	rom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rom_row.add_child(rom)
	browse_button = Button.new()
	browse_button.text = "Browse…"
	browse_button.pressed.connect(func(): rom_dialog.popup_centered_ratio(0.7))
	rom_row.add_child(browse_button)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	validate_button = Button.new()
	validate_button.text = "Validate ROM"
	validate_button.pressed.connect(func(): start(true))
	actions.add_child(validate_button)
	import_button = Button.new()
	import_button.text = "Import / replace generated library"
	import_button.pressed.connect(func(): start(false))
	actions.add_child(import_button)
	progress = ProgressBar.new()
	body.add_child(progress)
	message = Label.new()
	message.text = "Ready. Validate checks the header and payload hash without changing any assets."
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.max_lines_visible = 4
	body.add_child(message)
	logs = TextEdit.new()
	logs.editable = false
	logs.custom_minimum_size = Vector2(710,200)
	logs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(logs)
	rom_dialog = FileDialog.new()
	rom_dialog.access = FileDialog.ACCESS_FILESYSTEM
	rom_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	rom_dialog.filters = PackedStringArray(["*.nes ; NES ROM"])
	rom_dialog.file_selected.connect(func(path): rom.text = path)
	add_child(rom_dialog)
	size_changed.connect(func(): call_deferred("layout_content"))
	visibility_changed.connect(func(): call_deferred("layout_content"))
	call_deferred("layout_content")
func layout_content() -> void:
	content.position = Vector2(8,8)
	content.size = Vector2(size.x-16,size.y-56)
func set_busy(value: bool) -> void:
	busy = value
	for button in [validate_button,import_button,browse_button]: button.disabled = value
	python.editable = not value
	rom.editable = not value
func start(validate_only: bool) -> void:
	if busy: return
	if not FileAccess.file_exists(rom.text): message.text = "Select an existing .nes file."; return
	if python.text.strip_edges().is_empty(): message.text = "Enter a Python executable (python3 or an absolute path)."; return
	if not FileAccess.file_exists(game_root.path_join("tools/import_assets.py")): message.text = "Import tool missing. Keep editor/ inside the game repository."; return
	job = game_root.path_join("reference-inputs/import-jobs/editor-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	var error := DirAccess.make_dir_recursive_absolute(job)
	if error != OK: message.text = "Cannot create ignored job folder: " + error_string(error); return
	var args := PackedStringArray(["-u",game_root.path_join("tools/import_assets.py"),rom.text,"--project",game_root,"--job-dir",job])
	if validate_only: args.append("--validate-only")
	else: args.append_array(PackedStringArray(["--godot",OS.get_executable_path()]))
	last_state.clear()
	progress.value = 0
	logs.text = ""
	message.text = "Starting Python…"
	pid = OS.create_process(python.text.strip_edges(),args)
	if pid < 0:
		message.text = "Could not start Python. Install Python 3.9+ or enter its absolute executable path."
		return
	var config := ConfigFile.new()
	config.set_value("import","python",python.text.strip_edges())
	config.save("user://import-settings.cfg")
	set_busy(true)
func _process(delta: float) -> void:
	if not busy: return
	poll_elapsed += delta
	if poll_elapsed < 0.25: return
	poll_elapsed = 0.0
	var filename := job.path_join("status.json")
	if FileAccess.file_exists(filename):
		var state = JSON.parse_string(FileAccess.get_file_as_string(filename))
		if state is Dictionary and state != last_state:
			last_state = state
			progress.value = float(state.get("progress",0))
			message.text = str(state.get("message","Working…"))
			progress_changed.emit(message.text)
	var logfile := job.path_join("import.log")
	if FileAccess.file_exists(logfile):
		var file := FileAccess.open(logfile,FileAccess.READ)
		if file != null:
			file.seek(maxi(0,file.get_length()-18000))
			var text := file.get_as_text()
			if text != logs.text:
				logs.text = text
				logs.set_v_scroll(logs.get_v_scroll_bar().max_value)
	if OS.is_process_running(pid): return
	set_busy(false)
	var state: String = str(last_state.get("state",""))
	if state == "complete":
		message.text += "\n" + "\n".join(last_state.get("warnings",[])) + "\nBackup/logs: " + job
		library_changed.emit()
	elif state == "validated": message.text += "\nNo assets changed."
	elif state == "failed": message.text = "Import failed: " + str(last_state.get("message","Unknown error")) + "\nLog: " + logfile
	else: message.text = "Importer exited before completion. Check Python 3.9+, the executable path, and logs in " + job + ". A stale lock may need recovery; see IMPORTING.md."
	progress_changed.emit(message.text)
