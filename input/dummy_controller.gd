class_name DummyController
extends FighterController
## Training dummy: stands, shields or jumps, and can DI the hits it takes.

enum Behavior { STAND, SHIELD, JUMP }
enum DI { NONE, SURVIVAL, COMBO }

const _JUMP_INTERVAL := 90

var behavior := Behavior.STAND
var di := DI.NONE
var _frame := 0


func poll(fighter: Fighter) -> InputFrame:
	_frame += 1
	var frame := InputFrame.new()
	match behavior:
		Behavior.SHIELD:
			frame.shield = fighter.grounded
		Behavior.JUMP:
			frame.jump = _frame % _JUMP_INTERVAL < 2

	var launch := fighter.get_pending_launch_direction()
	if launch != Vector2.ZERO and di != DI.NONE:
		frame.stick = _di_stick(launch, fighter)
	return frame


## Holds the stick perpendicular to the launch. "Survival" bends it upward (or
## toward the stage on vertical launches) to live longer; "Combo" does the opposite.
func _di_stick(launch: Vector2, fighter: Fighter) -> Vector2:
	var perpendicular := Vector2(-launch.y, launch.x)
	var toward_safety := perpendicular.y
	if absf(toward_safety) < 0.2:
		# Near-vertical launch: drift toward the stage center instead.
		toward_safety = perpendicular.x * -signf(fighter.global_position.x)
	if toward_safety < 0.0:
		perpendicular = -perpendicular
	return perpendicular if di == DI.SURVIVAL else -perpendicular
