class_name AirDodgeState
extends FighterState
## Ultimate-style air dodge: neutral (keeps falling) or directional (a burst of
## movement that ignores gravity, then a slow recovery). One per airtime.

## Frames a directional dodge keeps its initial speed, then frames it slows down.
const DIRECTIONAL_HOLD_FRAMES := 5
const DIRECTIONAL_SLOW_FRAMES := 15
const DIRECTIONAL_SLOWDOWN := 0.85
const NEUTRAL_LANDING_LAG := 11
const DIRECTIONAL_LANDING_LAG := 19

var _direction := Vector2.ZERO


func _init(p_fighter: Fighter, stick: Vector2) -> void:
	super(p_fighter)
	if stick.length() >= 0.3:
		_direction = stick.normalized()


func state_name() -> StringName:
	return &"AirDodge"


func enter() -> void:
	fighter.fast_falling = false
	if _direction != Vector2.ZERO:
		fighter.velocity_self = _direction * fighter.stats.air_dodge_speed


func update() -> void:
	var f := fighter
	if frame > f.stats.air_dodge_frames:
		f.to_neutral()
		return
	if _direction == Vector2.ZERO:
		f.apply_gravity()
		f.apply_air_drift()
	elif frame <= DIRECTIONAL_HOLD_FRAMES:
		pass
	elif frame <= DIRECTIONAL_HOLD_FRAMES + DIRECTIONAL_SLOW_FRAMES:
		f.velocity_self *= DIRECTIONAL_SLOWDOWN
	else:
		f.apply_gravity()
		f.apply_air_drift()


func on_landed() -> void:
	fighter.velocity_self.x *= 0.5
	var lag := NEUTRAL_LANDING_LAG if _direction == Vector2.ZERO else DIRECTIONAL_LANDING_LAG
	fighter.change_state(LandingState.new(fighter, lag))


func on_left_ground() -> void:
	pass


func is_intangible() -> bool:
	var window := fighter.stats.air_dodge_intangible
	return frame >= window.x and frame <= window.y


func can_grab_ledge() -> bool:
	return frame > fighter.stats.air_dodge_intangible.y
