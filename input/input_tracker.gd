class_name InputTracker
extends RefCounted
## Turns raw [InputFrame]s into the signals Smash-style gameplay reacts to:
## button presses kept in a 9-frame buffer, stick flicks (dash, smash attacks,
## tap jump, fast fall, platform drops) and the stick direction at press time.

enum Btn { ATTACK, SPECIAL, JUMP, SHIELD }

## Frames a press stays buffered until a state can use it (Ultimate: 9).
const BUFFER_FRAMES := 9
## A flick travels from below [constant FLICK_FROM] to past [constant FLICK_TO]
## within this many frames. Slower movements are tilts.
const FLICK_FRAMES := 3
const FLICK_FROM := 0.3
const FLICK_TO := 0.8
## An attack pressed within this many frames of a flick is a smash attack.
const SMASH_WINDOW := 4
## Stick threshold for "crossing" down (fast fall) or treating a hold as a direction.
const PRESS_THRESHOLD := 0.65
## Ultimate registers a new SDI input at most every 4 frames.
const SDI_INTERVAL := 4

const _NEVER := 1 << 20

var current := InputFrame.new()
var previous := InputFrame.new()

## Stick direction when the buffered attack was pressed.
var attack_stick := Vector2.ZERO
## Whether the buffered attack was a smash input (flick, C-stick or smash button).
var attack_is_smash := false
## Whether the buffered attack came from the C-stick (aerials by C-stick direction).
var attack_from_cstick := false
## Stick direction when the buffered special was pressed.
var special_stick := Vector2.ZERO

var _press_age: PackedInt32Array
var _history: Array[Vector2] = []
var _flick_age := _NEVER
var _flick_direction := Vector2i.ZERO
var _sdi_age := _NEVER
var _sdi_direction := Vector2i.ZERO


func _init() -> void:
	_press_age.resize(Btn.size())
	_press_age.fill(_NEVER)


## Advances one frame with [param frame] as the new controller state.
func feed(frame: InputFrame) -> void:
	previous = current
	current = frame
	for i in _press_age.size():
		_press_age[i] = mini(_press_age[i] + 1, _NEVER)
	_flick_age = mini(_flick_age + 1, _NEVER)
	_sdi_age = mini(_sdi_age + 1, _NEVER)

	_history.push_back(frame.stick)
	if _history.size() > FLICK_FRAMES + 1:
		_history.pop_front()
	var flick := _detect_flick()
	if flick != Vector2i.ZERO:
		_flick_direction = flick
		_flick_age = 0

	if frame.attack and not previous.attack:
		_press_attack(frame.stick, _flick_age <= SMASH_WINDOW and _stick_matches_flick(), false)
	if frame.smash and not previous.smash:
		_press_attack(frame.stick, true, false)
	if frame.cstick.length() >= FLICK_TO and previous.cstick.length() < FLICK_TO:
		_press_attack(_dominant(frame.cstick), true, true)
	if frame.special and not previous.special:
		special_stick = frame.stick
		_press_age[Btn.SPECIAL] = 0
	if frame.jump and not previous.jump:
		_press_age[Btn.JUMP] = 0
	if frame.shield and not previous.shield:
		_press_age[Btn.SHIELD] = 0


## Whether [param button] was pressed within the buffer window and not consumed.
func buffered(button: Btn) -> bool:
	return _press_age[button] <= BUFFER_FRAMES


## Whether [param button] was pressed on this exact frame.
func just_pressed(button: Btn) -> bool:
	return _press_age[button] == 0


## Marks a buffered press as used so it doesn't trigger a second action.
func consume(button: Btn) -> void:
	_press_age[button] = _NEVER


## Clears every buffered press (e.g. when getting hit).
func clear_buffer() -> void:
	_press_age.fill(_NEVER)


## Horizontal flick on this frame: 1 right, -1 left, 0 none. Starts dashes,
## rolls out of shield and dash dances.
func flicked_x() -> int:
	return _flick_direction.x if _flick_age == 0 else 0


## Whether the stick was flicked up on this frame (tap jump).
func flicked_up() -> bool:
	return _flick_age == 0 and _flick_direction.y > 0


## Whether the stick was flicked down on this frame (platform drop, spot dodge).
func flicked_down() -> bool:
	return _flick_age == 0 and _flick_direction.y < 0


## Whether the stick crossed into the down zone on this frame (fast fall).
func crossed_down() -> bool:
	return current.stick.y <= -PRESS_THRESHOLD and previous.stick.y > -PRESS_THRESHOLD


## Returns the direction of a Smash DI pulse during hitlag, or zero. A pulse
## needs the stick at a new direction, at most every [constant SDI_INTERVAL] frames.
func take_sdi_pulse() -> Vector2:
	var direction := _octant(current.stick)
	if direction == Vector2i.ZERO or direction == _sdi_direction or _sdi_age < SDI_INTERVAL:
		if direction == Vector2i.ZERO:
			_sdi_direction = Vector2i.ZERO
		return Vector2.ZERO
	_sdi_direction = direction
	_sdi_age = 0
	return Vector2(direction).normalized()


func _press_attack(stick: Vector2, is_smash: bool, from_cstick: bool) -> void:
	attack_stick = stick
	attack_is_smash = is_smash
	attack_from_cstick = from_cstick
	_press_age[Btn.ATTACK] = 0


func _detect_flick() -> Vector2i:
	var now := current.stick
	var before := previous.stick
	var result := Vector2i.ZERO
	if absf(now.x) >= FLICK_TO and (absf(before.x) < FLICK_TO or signf(now.x) != signf(before.x)):
		if _came_from_neutral(0, signf(now.x)):
			result.x = int(signf(now.x))
	if absf(now.y) >= FLICK_TO and (absf(before.y) < FLICK_TO or signf(now.y) != signf(before.y)):
		if _came_from_neutral(1, signf(now.y)):
			result.y = int(signf(now.y))
	return result


## Whether, within the flick window, the stick was near neutral (or on the other
## side) on [param axis] before reaching the edge in [param direction].
func _came_from_neutral(axis: int, direction: float) -> bool:
	for i in _history.size() - 1:
		if _history[i][axis] * direction < FLICK_FROM:
			return true
	return false


func _stick_matches_flick() -> bool:
	var stick := current.stick
	if _flick_direction.x != 0 and stick.x * _flick_direction.x >= FLICK_TO * 0.9:
		return true
	return _flick_direction.y != 0 and stick.y * _flick_direction.y >= FLICK_TO * 0.9


static func _dominant(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0.0)
	return Vector2(0.0, signf(v.y))


static func _octant(v: Vector2) -> Vector2i:
	if v.length() < FLICK_TO:
		return Vector2i.ZERO
	var angle := snappedf(v.angle(), PI / 4.0)
	return Vector2i(roundi(cos(angle)), roundi(sin(angle)))
