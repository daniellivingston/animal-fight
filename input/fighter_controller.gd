class_name FighterController
extends RefCounted
## Base class for whatever drives a fighter: a local player, a training dummy,
## and later a CPU or a network peer. Called once per simulation frame.


## Returns this frame's input for [param fighter].
func poll(_fighter: Fighter) -> InputFrame:
	return InputFrame.new()
