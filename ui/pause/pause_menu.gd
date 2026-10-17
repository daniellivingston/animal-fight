class_name PauseMenu
extends CanvasLayer
## Pause and training settings: pick characters, make player 2 a human or a
## dummy (and how it behaves), toggle the debug views, and compare the two
## fighters' stats side by side. Built in code because its options come from the
## roster.

signal opened
signal closed

const _CONTROL_OPTIONS: Array[String] = ["Dummy: stand", "Dummy: shield", "Dummy: jump", "Human (P2 controls)"]
const _DI_OPTIONS: Array[String] = ["None", "Survival DI", "Combo DI"]
const _TAP_JUMP_OPTIONS: Array[String] = ["Auto (off on keyboard)", "On", "Off"]

var _match: Match
var _p1_select := OptionButton.new()
var _p2_select := OptionButton.new()
var _control_select := OptionButton.new()
var _di_select := OptionButton.new()
var _tap_jump_select := OptionButton.new()
var _hitboxes_toggle := CheckButton.new()
var _info_toggle := CheckButton.new()
var _stats_grid := GridContainer.new()
var _resume_button := Button.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	visible = false
	_build()


func setup(match_node: Match) -> void:
	_match = match_node
	for select: OptionButton in [_p1_select, _p2_select]:
		select.clear()
		for data in _match.roster:
			select.add_item(data.display_name)


func open() -> void:
	if visible:
		return
	_p1_select.select(_match.selections[0])
	_p2_select.select(_match.selections[1])
	_control_select.select(3 if _match.player_two_human else int(_match.dummy.behavior))
	_di_select.select(int(_match.dummy.di))
	_tap_jump_select.select(int(GameInput.tap_jump))
	_hitboxes_toggle.button_pressed = DebugSettings.show_hitboxes
	_info_toggle.button_pressed = DebugSettings.show_training_info
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
	_add_row(grid, "Player 1", _p1_select)
	_add_row(grid, "Player 2", _p2_select)
	_add_row(grid, "Player 2 control", _control_select, _CONTROL_OPTIONS)
	_add_row(grid, "Dummy DI", _di_select, _DI_OPTIONS)
	_add_row(grid, "Tap jump", _tap_jump_select, _TAP_JUMP_OPTIONS)
	_add_row(grid, "Hitboxes (F1)", _hitboxes_toggle)
	_add_row(grid, "Training info (F2)", _info_toggle)

	_p1_select.item_selected.connect(_on_fighter_selected.bind(0))
	_p2_select.item_selected.connect(_on_fighter_selected.bind(1))
	_control_select.item_selected.connect(_on_control_selected)
	_di_select.item_selected.connect(func(index: int) -> void: _match.dummy.di = index as DummyController.DI)
	_tap_jump_select.item_selected.connect(func(index: int) -> void: GameInput.tap_jump = index as GameInput.TapJump)
	_hitboxes_toggle.toggled.connect(func(on: bool) -> void: DebugSettings.show_hitboxes = on)
	_info_toggle.toggled.connect(func(on: bool) -> void: DebugSettings.show_training_info = on)

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


func _add_row(grid: GridContainer, text: String, control: Control, options: Array[String] = []) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var select := control as OptionButton
	if select:
		for option in options:
			select.add_item(option)
	control.custom_minimum_size = Vector2(240.0, 48.0)
	grid.add_child(control)


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.pressed.connect(action)
	parent.add_child(button)


func _on_fighter_selected(index: int, slot: int) -> void:
	_match.selections[slot] = index
	_match.start()
	_refresh_stats()


func _on_control_selected(index: int) -> void:
	_match.player_two_human = index == 3
	if not _match.player_two_human:
		_match.dummy.behavior = index as DummyController.Behavior
	_match.apply_controllers()


func _toggle_fullscreen() -> void:
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _refresh_stats() -> void:
	for child in _stats_grid.get_children():
		child.queue_free()
	var a := _match.roster[_match.selections[0]]
	var b := _match.roster[_match.selections[1]]
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
