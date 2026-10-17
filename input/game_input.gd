## Device tracking for the whole game (autoload: [code]GameInput[/code]).
##
## Tracks which kind of device the player used last, so the UI can adapt
## (showing or hiding the touch controls) and tap jump can default to off on
## keyboards. Gameplay input itself goes through the Input Map; see
## [PlayerController].
extends Node

signal device_changed(device: Device)

enum Device { KEYBOARD_MOUSE, GAMEPAD, TOUCH }
enum TapJump { AUTO, ON, OFF }

## Pass [code]-- --touch[/code] on the command line to force touch controls on
## desktop (the mouse emulates a single finger).
const FORCE_TOUCH_ARG := "--touch"

## Minimum stick deflection / mouse movement (pixels) that switches devices, so
## stick drift or a bumped mouse doesn't flip the UI back and forth.
const _JOY_SWITCH_THRESHOLD := 0.5
const _MOUSE_SWITCH_THRESHOLD := 4.0

## Whether flicking the stick up jumps. AUTO turns it off for keyboards, where
## every press of "up" would otherwise be a flick.
var tap_jump := TapJump.AUTO

var device := Device.KEYBOARD_MOUSE:
	set = _set_device

var _force_touch := false
# Fingers currently down. Mobile browsers also report drags as real mouse
# motion, which mustn't switch the device away from touch mid-drag.
var _held_touches: Dictionary[int, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_force_touch = OS.get_cmdline_user_args().has(FORCE_TOUCH_ARG)
	if _force_touch:
		Input.emulate_touch_from_mouse = true
	if _force_touch or OS.has_feature("mobile") \
			or (OS.has_feature("web") and DisplayServer.is_touchscreen_available()):
		device = Device.TOUCH


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_held_touches[touch.index] = true
		else:
			_held_touches.erase(touch.index)
	_detect_device(event)


func is_tap_jump_enabled() -> bool:
	match tap_jump:
		TapJump.ON:
			return true
		TapJump.OFF:
			return false
	return device != Device.KEYBOARD_MOUSE


func _detect_device(event: InputEvent) -> void:
	if _force_touch:
		return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		device = Device.TOUCH
	elif event is InputEventJoypadButton:
		device = Device.GAMEPAD
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= _JOY_SWITCH_THRESHOLD:
			device = Device.GAMEPAD
	elif event is InputEventKey:
		device = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseButton:
		# Touches also arrive as emulated mouse events; ignore those.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			device = Device.KEYBOARD_MOUSE
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.device != InputEvent.DEVICE_ID_EMULATION and _held_touches.is_empty() \
				and motion.screen_relative.length() >= _MOUSE_SWITCH_THRESHOLD:
			device = Device.KEYBOARD_MOUSE


func _set_device(value: Device) -> void:
	if value == device:
		return
	device = value
	device_changed.emit(device)
