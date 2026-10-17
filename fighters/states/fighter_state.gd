class_name FighterState
extends RefCounted
## Base class for fighter states (Smash "actions" such as idle, dash, jumpsquat
## or hitstun).
##
## A state runs one frame per [method update]. It reads [member Fighter.input],
## sets [member Fighter.velocity_self] and changes state through
## [method Fighter.change_state]. The fighter moves after [method update].
## Overrides below tell the fighter how to treat the state (edge behaviour,
## ledge grabs, intangibility).

var fighter: Fighter
## Frame number within the state. Frame 1 is the frame the state was entered;
## [method update] first runs with frame 2.
var frame := 1


func _init(p_fighter: Fighter) -> void:
	fighter = p_fighter


func state_name() -> StringName:
	return &"State"


func enter() -> void:
	pass


func exit() -> void:
	pass


## One frame of logic.
func update() -> void:
	pass


## The fighter touched the ground this frame.
func on_landed() -> void:
	fighter.land()


## The fighter left the ground without jumping (walked or got pushed off).
func on_left_ground() -> void:
	fighter.change_state(AirState.new(fighter))


## Grounded states that shouldn't slide off platform edges return true.
func stops_at_edges() -> bool:
	return false


func can_grab_ledge() -> bool:
	return false


## Whether the state can grab a ledge while moving upward (recovery moves).
func grabs_ledge_while_rising() -> bool:
	return false


## States that place the fighter directly (ledge, KO) skip the physics move.
func controls_position() -> bool:
	return false


func is_intangible() -> bool:
	return false
