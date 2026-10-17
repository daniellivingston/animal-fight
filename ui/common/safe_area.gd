class_name SafeArea
extends Control
## Full-screen container that insets its children away from notches and
## rounded corners on mobile devices. Put on-screen UI inside one of these.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var window_size := Vector2(get_window().size)
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	# The safe area is in screen pixels; convert it to canvas units.
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var to_canvas := get_viewport_rect().size / window_size
	offset_left = safe.position.x * to_canvas.x
	offset_top = safe.position.y * to_canvas.y
	offset_right = -(window_size.x - safe.end.x) * to_canvas.x
	offset_bottom = -(window_size.y - safe.end.y) * to_canvas.y
