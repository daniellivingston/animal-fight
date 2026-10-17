class_name WalkState
extends FighterState
## Walking: speed follows how far the stick is tilted, up to the walk speed.


func state_name() -> StringName:
	return &"Walk"


func update() -> void:
	var f := fighter
	if f.try_jump() or f.try_special() or f.try_ground_attack() or f.try_shield() or f.try_drop_through():
		return
	var stick := f.input.current.stick
	var flick := f.input.flicked_x()
	if flick != 0:
		f.facing = flick
		f.change_state(DashState.new(f))
		return
	if stick.y <= -InputTracker.PRESS_THRESHOLD:
		f.change_state(CrouchState.new(f))
		return
	if absf(stick.x) < Fighter.MOVE_DEADZONE:
		f.change_state(IdleState.new(f))
		f.apply_traction()
		return
	f.facing = 1 if stick.x > 0.0 else -1
	f.approach_ground_speed(f.stats.walk_speed * stick.x, f.stats.walk_acceleration)
