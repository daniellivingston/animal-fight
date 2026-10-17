class_name TouchStick
extends Control
## Floating analog stick for touch screens. It appears where the thumb lands
## and follows the thumb past its rim, and it presses the four direction
## actions with analog strength, so [InputTracker] sees tilts and flicks just
## like a gamepad stick (dash, smash attacks, tap jump, fast fall).
##
## Godot's [VirtualJoystick] isn't used because flick detection depends on the
## exact per-frame deflection and following behaviour defined here.

@export var action_left := &"p1_left"
@export var action_right := &"p1_right"
@export var action_up := &"p1_up"
@export var action_down := &"p1_down"
## Thumb travel for full deflection, in canvas units.
@export var radius := 80.0
## Where the stick rests while untouched, as a fraction of this control's size.
@export var rest_ratio := Vector2(0.3, 0.72)
@export var base_color := Color(1.0, 1.0, 1.0, 0.12)
@export var rim_color := Color(1.0, 1.0, 1.0, 0.45)
@export var knob_color := Color(1.0, 1.0, 1.0, 0.55)

var _touch_index := -1
var _origin := Vector2.ZERO
## Deflection, x right and y down, length at most 1.
var _value := Vector2.ZERO


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_EXIT_TREE:
			_release()
		NOTIFICATION_RESIZED:
			queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index == -1:
			_touch_index = touch.index
			_origin = touch.position
			_set_value(Vector2.ZERO)
			accept_event()
		elif not touch.pressed and touch.index == _touch_index:
			_release()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index:
			return
		var offset := drag.position - _origin
		if offset.length() > radius:
			# Follow the thumb so reversing direction is always one short swipe.
			_origin = drag.position - offset.normalized() * radius
			offset = drag.position - _origin
		_set_value(offset / radius)
		accept_event()


func _draw() -> void:
	var center := _origin if _touch_index != -1 else size * rest_ratio
	draw_circle(center, radius, base_color, true, -1.0, true)
	draw_circle(center, radius, rim_color, false, 3.0, true)
	draw_circle(center + _value * radius, radius * 0.45, knob_color, true, -1.0, true)


func _set_value(value: Vector2) -> void:
	_value = value.limit_length(1.0)
	_press(action_right, _value.x)
	_press(action_left, -_value.x)
	_press(action_down, _value.y)
	_press(action_up, -_value.y)
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_set_value(Vector2.ZERO)


static func _press(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)
