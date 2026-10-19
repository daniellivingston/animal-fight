class_name ShieldBreakState
extends FighterState
## Shield broke: launched upward, then dizzy on the ground and wide open.

## Height of the pop-up, in units.
const POP_HEIGHT := 25.0

var _dizzy_frames := 0
var _dizzy_start := 0


func state_name() -> StringName:
	return &"ShieldBreak" if _dizzy_start == 0 else &"Dizzy"


func enter() -> void:
	var f := fighter
	f.grounded = false
	f.velocity_self = Vector2(0.0, SmashFormulas.jump_velocity(POP_HEIGHT, f.stats.gravity))
	# Less damage means a longer stun, as in Smash. Placeholder curve.
	_dizzy_frames = maxi(120, 400 - int(f.percent * 2.0))


func update() -> void:
	var f := fighter
	if _dizzy_start == 0:
		f.apply_gravity()
		return
	f.apply_traction()
	if frame - _dizzy_start > _dizzy_frames:
		f.shield_hp = SmashFormulas.SHIELD_BREAK_RESET
		f.to_neutral()


func on_landed() -> void:
	if _dizzy_start == 0:
		_dizzy_start = frame


func on_left_ground() -> void:
	pass


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	if _dizzy_start == 0:
		return _dizzy_frames
	return maxi(_dizzy_frames - (frame - _dizzy_start), 0)
