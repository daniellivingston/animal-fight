class_name InputPlan
extends RefCounted
## A short queue of timed input steps ("macros") that a CPU plays back one
## [InputFrame] per frame, through the same [InputTracker] rules as a pad.
##
## Each macro respects the input rules it depends on (docs/ai.md lists them):
## walking stays under the flick threshold, tilts never flick, short-hop up airs
## don't become jump-cancelled up smashes, fast falls are released before
## ledges, a tech is a single shield press.

## How a step ends: after its frames, or as soon as a condition holds (checked
## before each frame; [member Step.frames] is then a time limit).
enum Until { FRAMES, ACTIONABLE, AIRBORNE, GROUNDED, FALLING, LEDGE_READY }

const ATTACK := 1
const SPECIAL := 2
const JUMP := 4
const SHIELD := 8
const SMASH := 16

## Stick tilt for walking and tilts: under [constant InputTracker.FLICK_TO].
const WALK_TILT := 0.6
const TILT := 0.7
## Stick for aerial directions: past the 0.5 aerial threshold, under the
## fast fall (0.65) and flick (0.8) thresholds.
const AERIAL_TILT := 0.6


class Step:
	var frames := 1
	var until := Until.FRAMES
	var stick := Vector2.ZERO
	var cstick := Vector2.ZERO
	var buttons := 0

	func to_frame() -> InputFrame:
		var frame := InputFrame.new()
		frame.stick = stick.limit_length(1.0)
		frame.cstick = cstick.limit_length(1.0)
		frame.attack = buttons & ATTACK != 0
		frame.special = buttons & SPECIAL != 0
		frame.jump = buttons & JUMP != 0
		frame.shield = buttons & SHIELD != 0
		frame.smash = buttons & SMASH != 0
		frame.tap_jump = false
		return frame


## What the plan is for (debug overlay, telemetry).
var label := ""
## Committed plans run to the end unless the fighter is hit.
var committed := false
## The situation that made the plan. A change of situation drops the plan
## unless [member carries_over] (a dive, a drop-aerial off the ledge).
var owner := &""
var carries_over := false

var _steps: Array[Step] = []
var _elapsed := 0


func is_empty() -> bool:
	return _steps.is_empty()


func clear() -> void:
	_steps.clear()
	_elapsed = 0
	label = ""
	committed = false
	owner = &""
	carries_over = false


## Frames left, counting condition steps at their time limit.
func frames_left() -> int:
	var count := -_elapsed
	for step in _steps:
		count += step.frames
	return maxi(count, 0)


## This frame's input, or null when the plan is done.
func next(fighter: Fighter) -> InputFrame:
	while not _steps.is_empty():
		var step := _steps[0]
		if _elapsed >= step.frames or (step.until != Until.FRAMES and _met(step.until, fighter)):
			_steps.pop_front()
			_elapsed = 0
			continue
		_elapsed += 1
		return step.to_frame()
	return null


## One-line description for the debug overlay.
func describe() -> String:
	if _steps.is_empty():
		return "-"
	var parts: PackedStringArray = []
	for i in mini(_steps.size(), 4):
		var step := _steps[i]
		var buttons := ""
		for pair: Array in [[ATTACK, "A"], [SPECIAL, "B"], [JUMP, "J"], [SHIELD, "S"], [SMASH, "Z"]]:
			if step.buttons & int(pair[0]):
				buttons += pair[1]
		var condition: String = "" if step.until == Until.FRAMES else "?" + String(Until.keys()[step.until]).to_lower()
		parts.append("%s(%.1f,%.1f)%s×%d" % [buttons, step.stick.x, step.stick.y, condition, step.frames])
	return " ".join(parts) + (" …" if _steps.size() > 4 else "")


#region Building blocks

## Adds a step holding [param stick] and [param buttons] for [param frames].
func hold(frames: int, stick: Vector2 = Vector2.ZERO, buttons: int = 0, cstick: Vector2 = Vector2.ZERO) -> InputPlan:
	if frames <= 0:
		return self
	var step := Step.new()
	step.frames = frames
	step.stick = stick
	step.buttons = buttons
	step.cstick = cstick
	_steps.append(step)
	return self


## Holds [param stick] and [param buttons] until [param until] holds, for at
## most [param max_frames].
func hold_until(until: Until, max_frames: int, stick: Vector2 = Vector2.ZERO, buttons: int = 0) -> InputPlan:
	hold(max_frames, stick, buttons)
	_steps.back().until = until
	return self


func wait(frames: int) -> InputPlan:
	return hold(frames)


func wait_until(until: Until, max_frames: int) -> InputPlan:
	return hold_until(until, max_frames)

#endregion


#region Macros

## Walk: the stick stays under the flick threshold, so it never dashes.
func walk(direction: int, frames: int, tilt: float = WALK_TILT) -> InputPlan:
	return hold(frames, Vector2(direction * minf(tilt, InputTracker.FLICK_TO - 0.05), 0.0))


## Dash, then run while held: one neutral frame so the move to full tilt is a flick.
func dash(direction: int, frames: int) -> InputPlan:
	hold(1)
	return hold(frames, Vector2(direction, 0.0))


## Dash back and forth [param times] times, [param frames_each] frames per dash.
func dash_dance(direction: int, times: int, frames_each: int) -> InputPlan:
	hold(1)
	for i in times:
		hold(frames_each, Vector2(direction if i % 2 == 0 else -direction, 0.0))
	return hold(1)


## A turnaround on the spot: a short light tilt turns an idle fighter.
func turn(direction: int) -> InputPlan:
	return hold(1, Vector2(direction * 0.3, 0.0))


## Full hop: jump held through jumpsquat. [param stick_x] picks the jump's
## horizontal speed and then drifts.
func full_hop(stick_x: float = 0.0, drift_frames: int = 0) -> InputPlan:
	hold(6, Vector2(stick_x, 0.0), JUMP)
	return hold(drift_frames, Vector2(stick_x, 0.0))


## Short hop: jump released before jumpsquat ends.
func short_hop(stick_x: float = 0.0, drift_frames: int = 0) -> InputPlan:
	hold(1, Vector2(stick_x, 0.0), JUMP)
	return hold(5 + drift_frames, Vector2(stick_x, 0.0))


## Short-hop aerial: jump, then attack during jumpsquat (which forces the short
## hop and keeps the attack buffered for the first airborne frame). The aerial
## direction is a tilt, never a flick, so up air can't turn into a
## jump-cancelled up smash.
func short_hop_aerial(slot: StringName, facing: int, drift: float = 0.0, drift_frames: int = 30) -> InputPlan:
	var stick := aerial_stick(slot, facing)
	hold(1, stick, JUMP)
	hold(1, stick, ATTACK)
	return hold(3 + drift_frames, Vector2(drift, 0.0))


## Full hop, then an aerial [param delay] frames after pressing jump.
func jump_aerial(slot: StringName, facing: int, delay: int, drift: float = 0.0, drift_frames: int = 30) -> InputPlan:
	hold(mini(delay, 6), Vector2(drift, 0.0), JUMP)
	hold(delay - 6, Vector2(drift, 0.0))
	hold(1, aerial_stick(slot, facing), ATTACK)
	return hold(drift_frames, Vector2(drift, 0.0))


## Aerial in the air, then drift.
func aerial(slot: StringName, facing: int, drift: float = 0.0, drift_frames: int = 0) -> InputPlan:
	hold(1, aerial_stick(slot, facing), ATTACK)
	return hold(drift_frames, Vector2(drift, 0.0))


## Mid-air jump: release, then press jump with the stick for its momentum.
func double_jump(stick_x: float = 0.0, drift_frames: int = 0) -> InputPlan:
	hold(1, Vector2(stick_x, 0.0))
	hold(1, Vector2(stick_x, 0.0), JUMP)
	return hold(drift_frames, Vector2(stick_x, 0.0))


## Fast fall: cross below the down threshold once, then let go of down (held
## down also falls through platforms and blocks ledge grabs).
func fast_fall(stick_x: float = 0.0) -> InputPlan:
	hold(1, Vector2(stick_x, 0.0))
	hold(1, Vector2(stick_x, -1.0))
	return hold(1, Vector2(stick_x, 0.0))


## Drop through the soft platform underfoot: flick down.
func drop_through() -> InputPlan:
	hold(1)
	hold(2, Vector2(0.0, -1.0))
	return hold(1)


## Jab or tilt: the stick goes straight to a tilt, under the flick threshold.
func tilt(slot: StringName, facing: int) -> InputPlan:
	hold(1, tilt_stick(slot, facing), ATTACK)
	return hold(1)


## Smash attack with the smash button (no flick timing), charged for
## [param charge] frames past [param charge_frame] if above 0.
func smash_attack(slot: StringName, facing: int, charge: int = 0, charge_frame: int = 0) -> InputPlan:
	var stick := smash_stick(slot, facing)
	if charge > 0:
		hold(charge_frame + charge, stick, SMASH)
	else:
		hold(1, stick, SMASH)
	return hold(1)


## Special in [param direction], then hold [param steer_x] (recovery steering).
func special(direction: Vector2, steer_x: float = 0.0, steer_frames: int = 0) -> InputPlan:
	hold(1, direction, SPECIAL)
	return hold(steer_frames, Vector2(steer_x, 0.0))


func shield(frames: int) -> InputPlan:
	return hold(frames, Vector2.ZERO, SHIELD)


## Roll out of shield: shield, wait until it can act, then flick sideways.
func roll(direction: int) -> InputPlan:
	hold(1, Vector2.ZERO, SHIELD)
	hold_until(Until.ACTIONABLE, 30, Vector2.ZERO, SHIELD)
	hold(1, Vector2(direction, 0.0), SHIELD)
	return hold(1)


## Spot dodge out of shield: flick down.
func spot_dodge() -> InputPlan:
	hold(1, Vector2.ZERO, SHIELD)
	hold_until(Until.ACTIONABLE, 30, Vector2.ZERO, SHIELD)
	hold(1, Vector2(0.0, -1.0), SHIELD)
	return hold(1)


## Air dodge toward [param direction] (zero: neutral air dodge).
func air_dodge(direction: Vector2 = Vector2.ZERO) -> InputPlan:
	hold(1, direction, SHIELD)
	return hold(1, direction)


## Ledge options. They wait for the grab lag first.
func ledge_climb(inward: int) -> InputPlan:
	wait_until(Until.LEDGE_READY, 10)
	hold(1, Vector2(inward, 0.0))
	return hold(1)


func ledge_jump(inward: int = 0) -> InputPlan:
	wait_until(Until.LEDGE_READY, 10)
	hold(1, Vector2.ZERO, JUMP)
	return hold(5, Vector2(inward * 0.5, 0.0))


func ledge_roll() -> InputPlan:
	wait_until(Until.LEDGE_READY, 10)
	hold(1, Vector2.ZERO, SHIELD)
	return hold(1)


func ledge_drop(outward: int) -> InputPlan:
	wait_until(Until.LEDGE_READY, 10)
	return hold(1, Vector2(outward, 0.0))


## Tech: a single shield press [param in_frames] frames from now, then hold
## [param stick_x] for a tech roll (0: tech in place) until landing.
func tech(in_frames: int, stick_x: float = 0.0) -> InputPlan:
	hold(in_frames, Vector2(stick_x, 0.0))
	hold(1, Vector2(stick_x, 0.0), SHIELD)
	return hold_until(Until.GROUNDED, 30, Vector2(stick_x, 0.0))

#endregion


## The stick for an aerial in [param slot] when facing [param facing].
static func aerial_stick(slot: StringName, facing: int) -> Vector2:
	match slot:
		Moveset.FORWARD_AIR:
			return Vector2(facing * AERIAL_TILT, 0.0)
		Moveset.BACK_AIR:
			return Vector2(-facing * AERIAL_TILT, 0.0)
		Moveset.UP_AIR:
			return Vector2(0.0, AERIAL_TILT)
		Moveset.DOWN_AIR:
			return Vector2(0.0, -AERIAL_TILT)
	return Vector2.ZERO


static func tilt_stick(slot: StringName, facing: int) -> Vector2:
	match slot:
		Moveset.FORWARD_TILT:
			return Vector2(facing * TILT, 0.0)
		Moveset.UP_TILT:
			return Vector2(0.0, TILT)
		Moveset.DOWN_TILT:
			return Vector2(0.0, -TILT)
	return Vector2.ZERO


static func smash_stick(slot: StringName, facing: int) -> Vector2:
	match slot:
		Moveset.UP_SMASH:
			return Vector2(0.0, 1.0)
		Moveset.DOWN_SMASH:
			return Vector2(0.0, -1.0)
	return Vector2(facing, 0.0)


static func special_stick(slot: StringName, facing: int) -> Vector2:
	match slot:
		Moveset.UP_SPECIAL:
			return Vector2(0.0, 1.0)
		Moveset.DOWN_SPECIAL:
			return Vector2(0.0, -1.0)
		Moveset.SIDE_SPECIAL:
			return Vector2(facing, 0.0)
	return Vector2.ZERO


static func _met(until: Until, fighter: Fighter) -> bool:
	match until:
		Until.ACTIONABLE:
			return fighter.hitlag_frames == 0 and fighter.state.frames_until_actionable() == 0
		Until.AIRBORNE:
			return not fighter.grounded
		Until.GROUNDED:
			return fighter.grounded
		Until.FALLING:
			return not fighter.grounded and fighter.velocity_self.y + fighter.velocity_knockback.y <= 0.0
		Until.LEDGE_READY:
			return fighter.state is LedgeHangState and fighter.state.frame > LedgeHangState.GRAB_LAG
	return false
