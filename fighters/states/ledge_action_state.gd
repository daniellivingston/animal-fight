class_name LedgeActionState
extends FighterState
## Getting off a ledge: climbing up, rolling onto the stage or jumping. The
## fighter is moved along a fixed path, intangible for the stat's window.

enum Kind { CLIMB, ROLL, JUMP }

var kind := Kind.CLIMB

var _ledge: StageLedge
var _start := Vector3.ZERO
var _end := Vector3.ZERO
var _duration := 1
var _intangible_until := 0


func _init(p_fighter: Fighter, p_kind: Kind) -> void:
	super(p_fighter)
	kind = p_kind


func state_name() -> StringName:
	match kind:
		Kind.ROLL:
			return &"LedgeRoll"
		Kind.JUMP:
			return &"LedgeJump"
	return &"LedgeClimb"


func enter() -> void:
	var f := fighter
	var stats := f.stats
	_ledge = f.ledge
	_start = f.global_position
	var top := _ledge.global_position
	var inward := -_ledge.side
	var body := Units.to_meters(stats.radius) + 0.05
	match kind:
		Kind.CLIMB:
			_duration = stats.ledge_getup_frames
			_intangible_until = stats.ledge_getup_intangible
			_end = Vector3(top.x + inward * body, top.y, 0.0)
		Kind.ROLL:
			_duration = stats.ledge_roll_frames
			_intangible_until = stats.ledge_roll_intangible
			_end = Vector3(top.x + inward * (body + Units.to_meters(stats.roll_distance)), top.y, 0.0)
		Kind.JUMP:
			_duration = stats.ledge_jump_frames
			_intangible_until = stats.ledge_jump_intangible
			_end = Vector3(top.x + _ledge.side * body, top.y + 0.1, 0.0)


func update() -> void:
	var f := fighter
	var t := clampf(float(frame) / _duration, 0.0, 1.0)
	# Rise first, then move across.
	var rise := clampf(t * 2.0, 0.0, 1.0)
	var across := clampf(t * 2.0 - 1.0, 0.0, 1.0)
	f.global_position = Vector3(lerpf(_start.x, _end.x, across), lerpf(_start.y, _end.y, rise), 0.0)
	if frame < _duration:
		return
	f.release_ledge()
	if kind == Kind.JUMP:
		f.grounded = false
		f.velocity_self = Vector2(-_ledge.side * 0.4,
				SmashFormulas.jump_velocity(f.stats.full_hop_height, f.stats.gravity))
		f.jumps_used = 1
		f.change_state(AirState.new(f))
	else:
		f.grounded = true
		f.velocity_self = Vector2.ZERO
		f.change_state(IdleState.new(f))


func controls_position() -> bool:
	return true


func is_intangible() -> bool:
	return frame <= _intangible_until


func frames_until_actionable() -> int:
	return maxi(_duration - frame, 0)


func intangible_frames_left() -> int:
	return maxi(_intangible_until - frame, 0)
