class_name CpuProfile
extends Resource
## Optional per-character CPU flavour and fixes, referenced from
## [member FighterData.cpu_profile] (Brawl's per-character AI overrides). A CPU
## plays reasonably without one: everything else comes from the moveset,
## stats and stage.

## Default personality for the character.
@export var personality: CpuPersonality
## Extra utility per moveset slot (e.g. [code]forward_smash: 1.5[/code]).
@export var move_weights: Dictionary[StringName, float] = {}
## Slots never used offstage (moves that would drag the CPU down).
@export var never_offstage: Array[StringName] = []
## Preferred kill moves, scored higher when a KO is on.
@export var kill_moves: Array[StringName] = []
## Recovery height preference: -1 aims low (sweetspot the ledge), 1 aims high
## (land on stage).
@export_range(-1.0, 1.0) var recovery_height := 0.0


func move_bias(slot: StringName) -> float:
	return move_weights.get(slot, 0.0)
