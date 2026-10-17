class_name DashState
extends FighterState
## Initial dash: a burst at the initial dash speed for the dash frames, which
## turns into a run if the stick is still held. Flicking the other way starts a
## new dash (dash dancing).


func state_name() -> StringName:
	return &"Dash"


func enter() -> void:
	fighter.velocity_self.x = fighter.facing * fighter.stats.initial_dash_speed


func update() -> void:
	var f := fighter
	if f.try_jump() or f.try_special() or f.try_ground_attack(true) or f.try_shield():
		return
	var flick := f.input.flicked_x()
	if flick == -f.facing:
		f.facing = flick
		f.change_state(DashState.new(f))
		return
	if frame > f.stats.dash_frames:
		if f.input.current.stick.x * f.facing >= Fighter.MOVE_DEADZONE:
			f.change_state(RunState.new(f))
		else:
			f.change_state(IdleState.new(f))
			f.apply_traction()
		return
	f.velocity_self.x = f.facing * f.stats.initial_dash_speed
