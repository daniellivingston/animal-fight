class_name StaleMoveQueue
extends RefCounted
## Ultimate's stale-move negation: the last 9 moves that connected, newest
## first. Using the same move over and over weakens it; fresh moves get a
## small bonus.

var _moves: Array[StringName] = []
var _weights: Array[float] = []


## Damage multiplier for [param move_id] right now.
func multiplier(move_id: StringName) -> float:
	var negation := 0.0
	var found := false
	for i in _moves.size():
		if _moves[i] == move_id:
			negation += SmashFormulas.STALE_FACTORS[i] * _weights[i]
			found = true
	return 1.0 - negation if found else SmashFormulas.FRESHNESS_BONUS


## Records that [param move_id] connected. Shield hits count less.
func push(move_id: StringName, on_shield: bool = false) -> void:
	_moves.push_front(move_id)
	_weights.push_front(SmashFormulas.STALE_SHIELD_WEIGHT if on_shield else 1.0)
	if _moves.size() > SmashFormulas.STALE_FACTORS.size():
		_moves.pop_back()
		_weights.pop_back()


func clear() -> void:
	_moves.clear()
	_weights.clear()
