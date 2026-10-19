class_name JumpSquatState
extends FighterState
## The few frames between pressing jump and leaving the ground. Releasing jump
## before they end (or pressing attack during them) gives a short hop.

var _tap_jump := false
var _short_hop := false


func _init(p_fighter: Fighter, tap_jump: bool) -> void:
	super(p_fighter)
	_tap_jump = tap_jump


func state_name() -> StringName:
	return &"JumpSquat"


func update() -> void:
	var f := fighter
	var input := f.input
	if input.buffered(InputTracker.Btn.ATTACK):
		# Jump-cancelled up smash, as used out of shield.
		if input.attack_is_smash and input.attack_stick.y >= InputTracker.PRESS_THRESHOLD:
			f.try_ground_attack()
			return
		# Jump + attack together: short hop aerial (the attack stays buffered).
		_short_hop = true
	if input.buffered(InputTracker.Btn.SPECIAL) and input.special_stick.y >= InputTracker.PRESS_THRESHOLD:
		f.try_special()
		return
	f.apply_traction()
	if frame > f.stats.jumpsquat_frames:
		var held := input.current.stick.y >= InputTracker.PRESS_THRESHOLD if _tap_jump else input.current.jump
		f.launch_jump(held and not _short_hop)


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	return maxi(fighter.stats.jumpsquat_frames + 1 - frame, 0)
