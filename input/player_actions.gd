class_name PlayerActions
extends RefCounted
## The Input Map action names for one local player slot.
##
## Slot 1 is keyboard (WASD) + gamepad 0 + touch; slot 2 is keyboard (arrows)
## + gamepad 1. See README "Controls".

var slot: int
var left: StringName
var right: StringName
var up: StringName
var down: StringName
var attack: StringName
var special: StringName
var jump: StringName
var shield: StringName
## Keyboard button that turns the attack into a smash attack.
var smash: StringName
## Keyboard modifier that limits the stick to a tilt (walk, tilt attacks).
var walk: StringName
var cstick_left: StringName
var cstick_right: StringName
var cstick_up: StringName
var cstick_down: StringName


func _init(p_slot: int) -> void:
	assert(p_slot >= 1 and p_slot <= InputActions.MAX_LOCAL_PLAYERS)
	slot = p_slot
	left = _name("left")
	right = _name("right")
	up = _name("up")
	down = _name("down")
	attack = _name("attack")
	special = _name("special")
	jump = _name("jump")
	shield = _name("shield")
	smash = _name("smash")
	walk = _name("walk")
	cstick_left = _name("cstick_left")
	cstick_right = _name("cstick_right")
	cstick_up = _name("cstick_up")
	cstick_down = _name("cstick_down")


## Every action of this slot, e.g. to release them all at once.
func all() -> Array[StringName]:
	return [left, right, up, down, attack, special, jump, shield, smash, walk,
			cstick_left, cstick_right, cstick_up, cstick_down]


func _name(action: String) -> StringName:
	return StringName("p%d_%s" % [slot, action])
