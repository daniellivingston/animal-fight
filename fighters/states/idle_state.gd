class_name IdleState
extends FighterState
## Standing on the ground. Every grounded action starts from here.


func state_name() -> StringName:
	return &"Idle"


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
	if absf(stick.x) >= Fighter.MOVE_DEADZONE:
		f.facing = 1 if stick.x > 0.0 else -1
		f.change_state(WalkState.new(f))
		return
	f.apply_traction()


func stops_at_edges() -> bool:
	return true
