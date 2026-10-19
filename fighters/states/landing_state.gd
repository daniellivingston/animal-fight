class_name LandingState
extends FighterState
## Landing lag: a few frames after touching down (more after aerials and
## helpless falls).

var duration := 0


func _init(p_fighter: Fighter, p_duration: int) -> void:
	super(p_fighter)
	duration = p_duration


func state_name() -> StringName:
	return &"Landing"


func update() -> void:
	fighter.apply_traction()
	if frame > duration:
		fighter.to_neutral()


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	return maxi(duration - frame, 0)
