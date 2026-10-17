class_name Moveset
extends Resource
## A fighter's attacks, one [MoveData] per input slot. Empty slots do nothing.

const JAB := &"jab"
const FORWARD_TILT := &"forward_tilt"
const UP_TILT := &"up_tilt"
const DOWN_TILT := &"down_tilt"
const DASH_ATTACK := &"dash_attack"
const FORWARD_SMASH := &"forward_smash"
const UP_SMASH := &"up_smash"
const DOWN_SMASH := &"down_smash"
const NEUTRAL_AIR := &"neutral_air"
const FORWARD_AIR := &"forward_air"
const BACK_AIR := &"back_air"
const UP_AIR := &"up_air"
const DOWN_AIR := &"down_air"
const NEUTRAL_SPECIAL := &"neutral_special"
const SIDE_SPECIAL := &"side_special"
const UP_SPECIAL := &"up_special"
const DOWN_SPECIAL := &"down_special"

@export_group("Ground")
@export var jab: MoveData
@export var forward_tilt: MoveData
@export var up_tilt: MoveData
@export var down_tilt: MoveData
@export var dash_attack: MoveData

@export_group("Smash")
@export var forward_smash: MoveData
@export var up_smash: MoveData
@export var down_smash: MoveData

@export_group("Aerial")
@export var neutral_air: MoveData
@export var forward_air: MoveData
@export var back_air: MoveData
@export var up_air: MoveData
@export var down_air: MoveData

@export_group("Special")
@export var neutral_special: MoveData
@export var side_special: MoveData
@export var up_special: MoveData
@export var down_special: MoveData


## The move in [param slot] (one of the constants above), or null.
func get_move(slot: StringName) -> MoveData:
	return get(slot) as MoveData
