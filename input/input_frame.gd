class_name InputFrame
extends RefCounted
## One frame of controller state for a fighter: where the sticks are and which
## buttons are held. [InputTracker] derives presses, flicks and the buffer.

## Control stick, x right and y up, length at most 1.
var stick := Vector2.ZERO
## C-stick (right stick): instant smash attacks on the ground, aerials in the air.
var cstick := Vector2.ZERO
var attack := false
var special := false
var jump := false
var shield := false
## Keyboard "smash" button: attack as a smash attack in the stick direction.
var smash := false
## Whether flicking the stick up jumps. Usually off on keyboards.
var tap_jump := true
