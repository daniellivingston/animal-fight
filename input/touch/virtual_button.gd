class_name VirtualButton
extends Control
## Round on-screen button that triggers an Input Map action. Multi-touch safe.
##
## Emits real [InputEventAction]s, so [code]_unhandled_input[/code] handlers
## see a tap exactly like a key or gamepad button press.

@export var action := &"p1_attack"
## Label drawn in the middle of the button.
@export var text := "":
	set(value):
		text = value
		queue_redraw()
## Draws the button faded, e.g. when its action currently does nothing.
@export var dimmed := false:
	set(value):
		dimmed = value
		queue_redraw()
@export var color := Color(1.0, 1.0, 1.0, 0.2)
@export var pressed_color := Color(1.0, 1.0, 1.0, 0.45)
@export var rim_color := Color(1.0, 1.0, 1.0, 0.6)
@export var font_size := 24

var _touch_index := -1


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_EXIT_TREE:
			if _touch_index != -1:
				_touch_index = -1
				_send_action(false)
		NOTIFICATION_RESIZED:
			queue_redraw()


## Only the inscribed circle is touchable; touches outside fall through.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size / 2.0) <= _radius()


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if not touch:
		return
	if touch.pressed and _touch_index == -1:
		_touch_index = touch.index
		_send_action(true)
		accept_event()
	elif not touch.pressed and touch.index == _touch_index:
		_touch_index = -1
		_send_action(false)
		accept_event()


func _draw() -> void:
	var center := size / 2.0
	var alpha := 0.5 if dimmed else 1.0
	var fill := pressed_color if _touch_index != -1 else color
	draw_circle(center, _radius(), fill * Color(1, 1, 1, alpha), true, -1.0, true)
	draw_circle(center, _radius() - 1.5, rim_color * Color(1, 1, 1, alpha), false, 3.0, true)

	if text.is_empty():
		return
	var font := get_theme_default_font()
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(center.x - text_width / 2.0, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, alpha))


func _radius() -> float:
	return minf(size.x, size.y) / 2.0


func _send_action(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
	queue_redraw()
