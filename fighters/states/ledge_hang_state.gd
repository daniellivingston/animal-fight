class_name LedgeHangState
extends FighterState
## Hanging from a ledge. Toward the stage or up climbs, jump jumps, shield
## rolls onto the stage, away or down lets go.

## Frames after grabbing before the fighter can act.
const GRAB_LAG := 6
## The fighter lets go automatically after this many frames.
const MAX_HANG_FRAMES := 300


func state_name() -> StringName:
	return &"LedgeHang"


func update() -> void:
	var f := fighter
	if frame <= GRAB_LAG:
		return
	var input := f.input
	var stick := input.current.stick
	var inward := -f.ledge.side
	var tapped := input.current.tap_jump and input.flicked_up()
	if input.buffered(InputTracker.Btn.JUMP) or tapped:
		input.consume(InputTracker.Btn.JUMP)
		f.change_state(LedgeActionState.new(f, LedgeActionState.Kind.JUMP))
	elif input.buffered(InputTracker.Btn.SHIELD):
		input.consume(InputTracker.Btn.SHIELD)
		f.change_state(LedgeActionState.new(f, LedgeActionState.Kind.ROLL))
	elif stick.x * inward >= InputTracker.PRESS_THRESHOLD or stick.y >= InputTracker.PRESS_THRESHOLD \
			or input.buffered(InputTracker.Btn.ATTACK):
		input.consume(InputTracker.Btn.ATTACK)
		f.change_state(LedgeActionState.new(f, LedgeActionState.Kind.CLIMB))
	elif stick.x * inward <= -InputTracker.PRESS_THRESHOLD or stick.y <= -InputTracker.PRESS_THRESHOLD \
			or frame > MAX_HANG_FRAMES:
		f.release_ledge()
		f.change_state(AirState.new(f))


func controls_position() -> bool:
	return true
