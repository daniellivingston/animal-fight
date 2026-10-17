class_name CrouchState
extends FighterState
## Crouching: smaller hurtbox, and hits taken are crouch cancelled (less
## knockback and hitlag).


func state_name() -> StringName:
	return &"Crouch"


func update() -> void:
	var f := fighter
	if f.try_jump() or f.try_special() or f.try_ground_attack() or f.try_shield() or f.try_drop_through():
		return
	if f.input.current.stick.y > -InputTracker.PRESS_THRESHOLD * 0.8:
		f.change_state(IdleState.new(f))
	f.apply_traction()


func stops_at_edges() -> bool:
	return true
