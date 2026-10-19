class_name RunBrakeState
extends FighterState
## Skidding to a stop out of a run, or turning around (run turnaround).

## Longest a skid lasts if the fighter is somehow still moving.
const MAX_BRAKE_FRAMES := 30

var turning := false


func _init(p_fighter: Fighter, p_turning: bool) -> void:
	super(p_fighter)
	turning = p_turning


func state_name() -> StringName:
	return &"RunTurn" if turning else &"RunBrake"


func update() -> void:
	var f := fighter
	if f.try_jump() or f.try_special() or f.try_ground_attack() or f.try_shield():
		return
	f.apply_traction()
	var stick := f.input.current.stick
	if turning:
		if frame > f.stats.run_turn_frames:
			f.facing = -f.facing
			if stick.x * f.facing >= Fighter.MOVE_DEADZONE:
				f.change_state(RunState.new(f))
			else:
				f.change_state(IdleState.new(f))
		return
	if stick.x * f.facing <= -InputTracker.PRESS_THRESHOLD:
		turning = true
		frame = 1
	elif f.velocity_self.x == 0.0 or frame > MAX_BRAKE_FRAMES:
		f.change_state(IdleState.new(f))


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	return maxi(fighter.stats.run_turn_frames - frame, 0) if turning else 0
