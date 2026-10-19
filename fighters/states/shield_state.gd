class_name ShieldState
extends FighterState
## Holding shield. The shield shrinks while held and regenerates otherwise;
## hits push it back and stun it. Out of shield: jump, up special, roll
## (flick sideways) and spot dodge (flick down).

var _stun := 0
var _drop_frame := 0


func state_name() -> StringName:
	if _stun > 0:
		return &"ShieldStun"
	return &"ShieldDrop" if _drop_frame > 0 else &"Shield"


func update() -> void:
	var f := fighter
	if _stun > 0:
		_stun -= 1
		f.apply_traction()
		return
	if _drop_frame > 0:
		_drop_frame += 1
		f.apply_traction()
		if _drop_frame > SmashFormulas.SHIELD_DROP_FRAMES:
			f.to_neutral()
		return

	f.shield_hp -= SmashFormulas.SHIELD_DECAY
	if f.shield_hp <= 0.0:
		f.break_shield()
		return
	if f.try_jump():
		return
	if f.input.buffered(InputTracker.Btn.SPECIAL) and f.input.special_stick.y >= InputTracker.PRESS_THRESHOLD:
		f.try_special()
		return
	var flick := f.input.flicked_x()
	if flick != 0:
		f.start_roll(flick)
		return
	if f.input.flicked_down():
		f.start_spot_dodge()
		return
	if not f.input.current.shield and frame > SmashFormulas.SHIELD_MIN_FRAMES:
		_drop_frame = 1
	f.apply_traction()


## A hit landed on the shield: [param stun] frames of shieldstun and a pushback
## of [param pushback] units/frame.
func take_hit(stun: int, pushback: float) -> void:
	_stun = stun
	_drop_frame = 0
	fighter.velocity_self.x = pushback


## Whether the bubble is up (it stays up through shieldstun, not while dropping).
func is_raised() -> bool:
	return _drop_frame == 0


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	if _stun > 0:
		return _stun + fighter.hitlag_frames
	if _drop_frame > 0:
		return maxi(SmashFormulas.SHIELD_DROP_FRAMES - _drop_frame, 0)
	return fighter.hitlag_frames
