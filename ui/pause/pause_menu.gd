class_name PauseMenu
extends CanvasLayer
## Pause and training settings: pick characters, make each player a human or a
## CPU (level 1-9) and player 2 a training dummy (and how it behaves), toggle
## the debug views, and compare the two fighters' stats side by side. Built in
## code because its options come from the roster. Slot settings are saved.

signal opened
signal closed

## Control options: label, slot kind, CPU mode. P1 offers the first two.
const _CONTROL_OPTIONS: Array[Array] = [
	["Human", PlayerSlot.Kind.HUMAN, CpuController.Mode.FIGHT],
	["CPU", PlayerSlot.Kind.CPU, CpuController.Mode.FIGHT],
	["Dummy: stand", PlayerSlot.Kind.CPU, CpuController.Mode.STAND],
	["Dummy: shield", PlayerSlot.Kind.CPU, CpuController.Mode.SHIELD],
	["Dummy: jump", PlayerSlot.Kind.CPU, CpuController.Mode.JUMP],
	["CPU: walk", PlayerSlot.Kind.CPU, CpuController.Mode.WALK],
	["CPU: run away", PlayerSlot.Kind.CPU, CpuController.Mode.EVADE],
]
const _DI_OPTIONS: Array[String] = ["None", "Survival DI", "Combo DI"]
const _TAP_JUMP_OPTIONS: Array[String] = ["Auto (off on keyboard)", "On", "Off"]

var _match: Match
var _character_selects: Array[OptionButton] = [OptionButton.new(), OptionButton.new()]
var _control_selects: Array[OptionButton] = [OptionButton.new(), OptionButton.new()]
var _level_rows: Array[HBoxContainer] = []
var _level_labels: Array[Label] = []
var _level_row_labels: Array[Label] = []
var _di_select := OptionButton.new()
var _di_label: Label
var _tap_jump_select := OptionButton.new()
var _hitboxes_toggle := CheckButton.new()
var _info_toggle := CheckButton.new()
var _ai_debug_toggle := CheckButton.new()
var _stats_grid := GridContainer.new()
var _resume_button := Button.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	visible = false
	_build()


func setup(match_node: Match) -> void:
	_match = match_node
	for select in _character_selects:
		select.clear()
		for data in _match.roster:
			select.add_item(data.display_name)


func open() -> void:
	if visible:
		return
	_refresh_slots()
	_tap_jump_select.select(int(GameInput.tap_jump))
	_hitboxes_toggle.button_pressed = DebugSettings.show_hitboxes
	_info_toggle.button_pressed = DebugSettings.show_training_info
	_ai_debug_toggle.button_pressed = DebugSettings.show_ai_debug
	_refresh_stats()
	visible = true
	get_tree().paused = true
	_resume_button.grab_focus.call_deferred()
	opened.emit()


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dim.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.16, 0.96)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24.0)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 32)
	panel.add_child(columns)

	var settings := VBoxContainer.new()
	settings.add_theme_constant_override(&"separation", 10)
	columns.add_child(settings)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override(&"font_size", 34)
	settings.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 8)
	settings.add_child(grid)
	for i in 2:
		var options: Array[String] = []
		for j in (2 if i == 0 else _CONTROL_OPTIONS.size()):
			options.append(_CONTROL_OPTIONS[j][0])
		_add_row(grid, "Player %d" % (i + 1), _character_selects[i])
		_add_row(grid, "Player %d control" % (i + 1), _control_selects[i], options)
		_level_row_labels.append(_add_row(grid, "Player %d CPU level" % (i + 1), _build_level_row(i)))
		_character_selects[i].item_selected.connect(_on_fighter_selected.bind(i))
		_control_selects[i].item_selected.connect(_on_control_selected.bind(i))
	_di_label = _add_row(grid, "Dummy DI", _di_select, _DI_OPTIONS)
	_add_row(grid, "Tap jump", _tap_jump_select, _TAP_JUMP_OPTIONS)
	_add_row(grid, "Hitboxes (F1)", _hitboxes_toggle)
	_add_row(grid, "Training info (F2)", _info_toggle)
	_add_row(grid, "AI debug (F3)", _ai_debug_toggle)

	_di_select.item_selected.connect(func(index: int) -> void:
		_match.slots[1].dummy_di = index as AiDi.Mode
		_apply_slots())
	_tap_jump_select.item_selected.connect(func(index: int) -> void: GameInput.tap_jump = index as GameInput.TapJump)
	_hitboxes_toggle.toggled.connect(func(on: bool) -> void: DebugSettings.show_hitboxes = on)
	_info_toggle.toggled.connect(func(on: bool) -> void: DebugSettings.show_training_info = on)
	_ai_debug_toggle.toggled.connect(func(on: bool) -> void:
		DebugSettings.show_ai_debug = on
		if on:
			DebugSettings.show_training_info = true
			_info_toggle.button_pressed = true)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	settings.add_child(buttons)
	_resume_button.text = "Resume"
	_resume_button.pressed.connect(close)
	buttons.add_child(_resume_button)
	_add_button(buttons, "Reset (F5)", func() -> void:
		_match.reset()
		close())
	if OS.has_feature("web") or OS.has_feature("mobile"):
		_add_button(buttons, "Fullscreen", _toggle_fullscreen)

	var stats_column := VBoxContainer.new()
	columns.add_child(stats_column)
	var stats_title := Label.new()
	stats_title.text = "Stats (Ultimate units)"
	stats_title.add_theme_font_size_override(&"font_size", 24)
	stats_column.add_child(stats_title)
	_stats_grid.columns = 3
	_stats_grid.add_theme_constant_override(&"h_separation", 20)
	stats_column.add_child(_stats_grid)


func _add_row(grid: GridContainer, text: String, control: Control, options: Array[String] = []) -> Label:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var select := control as OptionButton
	if select:
		for option in options:
			select.add_item(option)
	control.custom_minimum_size = Vector2(240.0, 48.0)
	grid.add_child(control)
	return label


## "−  Lv 3  +" with big touch targets; the number takes the level's colour.
func _build_level_row(slot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var minus := Button.new()
	minus.text = "−"
	var plus := Button.new()
	plus.text = "+"
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 6)
	for button: Button in [minus, plus]:
		button.custom_minimum_size = Vector2(56.0, 48.0)
	minus.pressed.connect(_on_level_step.bind(slot, -1))
	plus.pressed.connect(_on_level_step.bind(slot, 1))
	row.add_child(minus)
	row.add_child(label)
	row.add_child(plus)
	_level_rows.append(row)
	_level_labels.append(label)
	return row


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.pressed.connect(action)
	parent.add_child(button)


func _on_fighter_selected(index: int, slot: int) -> void:
	_match.slots[slot].character = index
	_match.start()
	_refresh_stats()


func _on_control_selected(index: int, slot: int) -> void:
	var option: Array = _CONTROL_OPTIONS[index]
	_match.slots[slot].kind = option[1]
	_match.slots[slot].cpu_mode = option[2]
	_apply_slots()


func _on_level_step(slot: int, step: int) -> void:
	# The frame-perfect debug level is only offered in debug builds.
	var top := CpuController.DEBUG_LEVEL if OS.is_debug_build() else CpuController.MAX_LEVEL
	var data := _match.slots[slot]
	data.cpu_level = clampi(data.cpu_level + step, 1, top)
	_apply_slots()


func _apply_slots() -> void:
	_match.apply_controllers()
	_match.save_settings()
	_refresh_slots()


func _refresh_slots() -> void:
	for i in 2:
		var data := _match.slots[i]
		_character_selects[i].select(data.character)
		var control := 0
		for j in _CONTROL_OPTIONS.size():
			if _CONTROL_OPTIONS[j][1] == data.kind and (data.kind == PlayerSlot.Kind.HUMAN or _CONTROL_OPTIONS[j][2] == data.cpu_mode):
				control = j
		_control_selects[i].select(mini(control, _control_selects[i].item_count - 1))
		var shows_level := data.kind == PlayerSlot.Kind.CPU
		_level_rows[i].visible = shows_level
		_level_row_labels[i].visible = shows_level
		var level := data.cpu_level
		_level_labels[i].text = "Lv %d%s" % [level, " (frame-perfect)" if level == CpuController.DEBUG_LEVEL else ""]
		_level_labels[i].add_theme_color_override(&"font_color", PlayerSlot.level_color(level).lightened(0.25))
	_di_select.select(int(_match.slots[1].dummy_di))
	# DI is a setting of the training dummy modes only.
	var p2 := _match.slots[1]
	var dummy := p2.kind == PlayerSlot.Kind.CPU and p2.cpu_mode in [CpuController.Mode.STAND,
			CpuController.Mode.SHIELD, CpuController.Mode.JUMP]
	_di_select.visible = dummy
	_di_label.visible = dummy


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _refresh_stats() -> void:
	for child in _stats_grid.get_children():
		child.queue_free()
	var a := _match.roster[_match.slots[0].character]
	var b := _match.roster[_match.slots[1].character]
	_add_stat_row("", a.display_name, b.display_name, true)
	for row in _stat_rows():
		var getter: Callable = row[1]
		_add_stat_row(row[0], getter.call(a.stats), getter.call(b.stats))


func _add_stat_row(stat: String, left: String, right: String, header: bool = false) -> void:
	for text: String in [stat, left, right]:
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override(&"font_size", 20 if header else 17)
		if text != stat:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stats_grid.add_child(label)


func _stat_rows() -> Array:
	return [
		["Weight", func(s: FighterStats) -> String: return "%.0f" % s.weight],
		["Walk speed", func(s: FighterStats) -> String: return "%.3f" % s.walk_speed],
		["Initial dash", func(s: FighterStats) -> String: return "%.3f" % s.initial_dash_speed],
		["Dash frames", func(s: FighterStats) -> String: return "%d" % s.dash_frames],
		["Run speed", func(s: FighterStats) -> String: return "%.3f" % s.run_speed],
		["Traction", func(s: FighterStats) -> String: return "%.3f" % s.traction],
		["Full / short hop", func(s: FighterStats) -> String: return "%.1f / %.1f" % [s.full_hop_height, s.short_hop_height]],
		["Air jump × count", func(s: FighterStats) -> String: return "%.1f × %d" % [s.air_jump_height, s.jump_count - 1]],
		["Air speed", func(s: FighterStats) -> String: return "%.3f" % s.air_speed],
		["Air accel (max)", func(s: FighterStats) -> String: return "%.3f" % s.air_acceleration(1.0)],
		["Air friction", func(s: FighterStats) -> String: return "%.4f" % s.air_friction],
		["Gravity", func(s: FighterStats) -> String: return "%.3f" % s.gravity],
		["Fall / fast fall", func(s: FighterStats) -> String: return "%.2f / %.2f" % [s.fall_speed, s.fast_fall_speed()]],
		["Landing (hard)", func(s: FighterStats) -> String: return "%d f" % s.hard_landing_frames],
		["Size (h × r)", func(s: FighterStats) -> String: return "%.0f × %.1f" % [s.height, s.radius]],
	]
