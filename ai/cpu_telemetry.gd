class_name CpuTelemetry
extends RefCounted
## Counters a CPU keeps about its own play, for the ladder harness and tuning.

var reactions := 0
## Sum of reaction times (frames from an opponent action starting to the
## defensive input), for the average.
var reaction_frames_total := 0
var defends := 0
var shields := 0
var punish_attempts := 0
var recoveries := 0
var edgeguards := 0
var techs := 0
## Uses per moveset slot.
var moves: Dictionary[StringName, int] = {}


func count_move(slot: StringName) -> void:
	moves[slot] = moves.get(slot, 0) + 1


func count_reaction(frames: int) -> void:
	reactions += 1
	reaction_frames_total += frames


func average_reaction() -> float:
	return float(reaction_frames_total) / reactions if reactions > 0 else 0.0


## Adds [param other]'s counters to these.
func merge(other: CpuTelemetry) -> void:
	reactions += other.reactions
	reaction_frames_total += other.reaction_frames_total
	defends += other.defends
	shields += other.shields
	punish_attempts += other.punish_attempts
	recoveries += other.recoveries
	edgeguards += other.edgeguards
	techs += other.techs
	for slot in other.moves:
		moves[slot] = moves.get(slot, 0) + other.moves[slot]
