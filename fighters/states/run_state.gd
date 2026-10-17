class_name RunState
extends FighterState
## Running: accelerates from the dash speed to the run speed.


func state_name() -> StringName:
	return &"Run"


func update() -> void:
	var f := fighter
	if f.try_jump() or f.try_special() or f.try_ground_attack(true) or f.try_shield():
		return
	var stick := f.input.current.stick
	if stick.y <= -InputTracker.PRESS_THRESHOLD:
		f.change_state(CrouchState.new(f))
		return
	if stick.x * f.facing <= -InputTracker.PRESS_THRESHOLD:
		f.change_state(RunBrakeState.new(f, true))
		return
	if stick.x * f.facing < Fighter.MOVE_DEADZONE:
		f.change_state(RunBrakeState.new(f, false))
		return
	f.velocity_self.x = move_toward(f.velocity_self.x, f.facing * f.stats.run_speed, f.stats.run_acceleration)
