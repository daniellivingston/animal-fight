class_name AirState
extends FighterState
## Airborne: jumping, falling, tumbling after a strong hit, or helpless after a
## recovery move.

## Tumbling: landing without a tech knocks the fighter down.
var tumbling := false
## Helpless (special fall): can only drift and grab ledges until landing.
var helpless := false
var helpless_landing_lag := 0


func _init(p_fighter: Fighter, p_tumbling: bool = false, p_helpless: bool = false,
		p_helpless_landing_lag: int = 0) -> void:
	super(p_fighter)
	tumbling = p_tumbling
	helpless = p_helpless
	helpless_landing_lag = p_helpless_landing_lag


func state_name() -> StringName:
	if helpless:
		return &"Helpless"
	return &"Tumble" if tumbling else &"Air"


func update() -> void:
	var f := fighter
	if not helpless:
		if f.try_special() or f.try_aerial() or f.try_air_dodge() or f.try_double_jump():
			return
	f.try_fast_fall()
	f.apply_gravity()
	f.apply_air_drift(Fighter.HELPLESS_DRIFT if helpless else 1.0)


func on_landed() -> void:
	if tumbling:
		fighter.land_from_tumble()
	elif helpless:
		fighter.change_state(LandingState.new(fighter, helpless_landing_lag))
	else:
		fighter.land()


func on_left_ground() -> void:
	pass


func can_grab_ledge() -> bool:
	return true


## Helpless fighters can't act until they land and finish the landing lag.
func frames_until_actionable() -> int:
	return helpless_landing_lag + 1 if helpless else 0
