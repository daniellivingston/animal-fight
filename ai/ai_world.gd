class_name AiWorld
extends RefCounted
## What CPUs can see, owned by [Match] (or the test world). At the end of every
## frame [method capture] records a [FighterSnapshot] of each fighter; CPUs read
## them later through [method view], so they see the world after their
## reaction delay and the same way whatever order fighters tick in.

## Frames of history kept. Longer than the slowest reaction plus its jitter.
const HISTORY := 64

var fighters: Array[Fighter]
var stage_model: StageModel
## Number of frames captured so far.
var frame := 0

var _rings: Array[Array] = []
# Target index -> (claiming fighter index, frame the claim expires).
var _edgeguard_claims: Dictionary[int, Vector2i] = {}


func _init(stage: Stage, p_fighters: Array[Fighter]) -> void:
	stage_model = StageModel.new(stage)
	fighters = p_fighters
	clear()


## Forgets all history (new match, reset, fighters added or removed).
func clear() -> void:
	frame = 0
	_rings.clear()
	_edgeguard_claims.clear()


## Records this frame's snapshot of every fighter. Call after hits resolve.
func capture() -> void:
	frame += 1
	while _rings.size() < fighters.size():
		var ring: Array[FighterSnapshot] = []
		for i in HISTORY:
			ring.append(FighterSnapshot.new())
		_rings.append(ring)
	for i in fighters.size():
		var snapshot: FighterSnapshot = _rings[i][frame % HISTORY]
		snapshot.capture(fighters[i], i, frame, fighters)


## Fighter [param index] as it was [param delay] frames ago (0: the latest
## capture). Clamped to the oldest frame still kept. Null before the first capture.
func view(index: int, delay: int) -> FighterSnapshot:
	if frame == 0 or index >= _rings.size():
		return null
	var at := clampi(frame - delay, maxi(frame - HISTORY + 1, 1), frame)
	return _rings[index][at % HISTORY]


## Fighter [param index] as it was on world frame [param at] (clamped to what's kept).
func view_at(index: int, at: int) -> FighterSnapshot:
	return view(index, frame - at)


func index_of(fighter: Fighter) -> int:
	return fighters.find(fighter)


## Claims going offstage after fighter [param target] for [param frames]
## frames. Fails while another fighter holds a claim on it, so only one CPU
## dives at a time (no "flocking").
func claim_edgeguard(target: int, claimant: int, frames: int) -> bool:
	var claim: Vector2i = _edgeguard_claims.get(target, Vector2i(-1, -1))
	if claim.x >= 0 and claim.x != claimant and claim.y > frame:
		return false
	_edgeguard_claims[target] = Vector2i(claimant, frame + frames)
	return true
