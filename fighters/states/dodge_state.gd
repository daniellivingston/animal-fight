class_name DodgeState
extends FighterState
## Grounded evasive moves: spot dodge, rolls, techs and getups. Intangible on a
## window of frames, moving a set distance during that window.

var _name: StringName
var _duration := 0
var _intangible := Vector2i.ZERO
var _distance := 0.0
var _turn_after := false


## [param distance] is in units, relative to facing (negative moves backward).
func _init(p_fighter: Fighter, p_name: StringName, duration: int, intangible: Vector2i,
		distance: float, turn_after: bool) -> void:
	super(p_fighter)
	_name = p_name
	_duration = duration
	_intangible = intangible
	_distance = distance
	_turn_after = turn_after


func state_name() -> StringName:
	return _name


func update() -> void:
	var f := fighter
	if frame > _duration:
		if _turn_after:
			f.facing = -f.facing
		f.to_neutral()
		return
	var span := maxi(_intangible.y - _intangible.x + 1, 1)
	if frame >= _intangible.x and frame <= _intangible.y:
		f.velocity_self.x = _distance / span * f.facing
	else:
		f.velocity_self.x = 0.0


func is_intangible() -> bool:
	return frame >= _intangible.x and frame <= _intangible.y


func stops_at_edges() -> bool:
	return true


func frames_until_actionable() -> int:
	return maxi(_duration - frame, 0)


func intangible_frames_left() -> int:
	return maxi(_intangible.y - frame, 0)
