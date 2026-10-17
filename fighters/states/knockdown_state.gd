class_name KnockdownState
extends FighterState
## Lying on the ground after a missed tech. Get up in place, roll away with
## the stick, or wait for the automatic getup.

## Tech timings. Approximations: SmashWiki doesn't list Ultimate's values.
const TECH_FRAMES := 26
const TECH_ROLL_FRAMES := 40
const TECH_INTANGIBLE := Vector2i(1, 20)
const TECH_ROLL_DISTANCE := 30.0
const GETUP_FRAMES := 30
const GETUP_INTANGIBLE := Vector2i(1, 22)
const GETUP_ROLL_FRAMES := 35
const GETUP_ROLL_DISTANCE := 25.0
## Frames on the ground before getting up is possible, and before it's forced.
const MIN_LYING_FRAMES := 20
const MAX_LYING_FRAMES := 90


func state_name() -> StringName:
	return &"Knockdown"


func update() -> void:
	var f := fighter
	f.apply_traction()
	if frame < MIN_LYING_FRAMES:
		return
	var input := f.input
	var x := input.current.stick.x
	if absf(x) >= InputTracker.PRESS_THRESHOLD:
		f.change_state(DodgeState.new(f, &"GetupRoll", GETUP_ROLL_FRAMES, GETUP_INTANGIBLE,
				GETUP_ROLL_DISTANCE * signf(x) * f.facing, false))
		return
	var pressed := false
	for button: InputTracker.Btn in InputTracker.Btn.values():
		if input.buffered(button):
			input.consume(button)
			pressed = true
	if pressed or input.current.stick.y >= InputTracker.PRESS_THRESHOLD or frame >= MAX_LYING_FRAMES:
		f.change_state(DodgeState.new(f, &"Getup", GETUP_FRAMES, GETUP_INTANGIBLE, 0.0, false))


func stops_at_edges() -> bool:
	return true
