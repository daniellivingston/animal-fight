class_name RespawnState
extends FighterState
## On the revival platform after a KO. Any input (or waiting) drops the
## fighter into the stage with a few seconds of invincibility.

## Frames before input can drop the fighter, and before it drops on its own.
const MIN_FRAMES := 20
const MAX_FRAMES := 300


func state_name() -> StringName:
	return &"Respawn"


func update() -> void:
	if frame < MIN_FRAMES:
		return
	var input := fighter.input
	var moved := input.current.stick.length() >= InputTracker.PRESS_THRESHOLD
	var pressed := false
	for button: InputTracker.Btn in InputTracker.Btn.values():
		pressed = pressed or input.buffered(button)
	if moved or pressed or frame > MAX_FRAMES:
		fighter.leave_respawn_platform()


func controls_position() -> bool:
	return true


func is_intangible() -> bool:
	return true


func frames_until_actionable() -> int:
	return maxi(MIN_FRAMES - frame, 0)


func intangible_frames_left() -> int:
	return maxi(MAX_FRAMES - frame, 0) + Fighter.RESPAWN_INVINCIBILITY
