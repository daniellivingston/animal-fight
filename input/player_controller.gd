class_name PlayerController
extends FighterController
## Reads a local player's actions from the Input Map (keyboard, gamepad and the
## on-screen touch controls all feed the same actions).

## How far the stick reaches while the keyboard walk modifier is held. Below the
## flick threshold, so it walks and tilts instead of dashing and smashing.
const WALK_TILT := 0.7

var actions: PlayerActions


func _init(slot: int) -> void:
	actions = PlayerActions.new(slot)


func poll(_fighter: Fighter) -> InputFrame:
	var frame := InputFrame.new()
	var a := actions
	frame.stick = Input.get_vector(a.left, a.right, a.down, a.up)
	if Input.is_action_pressed(a.walk):
		frame.stick = frame.stick.limit_length(WALK_TILT)
	frame.cstick = Input.get_vector(a.cstick_left, a.cstick_right, a.cstick_down, a.cstick_up)
	frame.attack = Input.is_action_pressed(a.attack)
	frame.special = Input.is_action_pressed(a.special)
	frame.jump = Input.is_action_pressed(a.jump)
	frame.shield = Input.is_action_pressed(a.shield)
	frame.smash = Input.is_action_pressed(a.smash)
	frame.tap_jump = GameInput.is_tap_jump_enabled()
	return frame
