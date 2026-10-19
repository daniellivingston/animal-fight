class_name HabitModel
extends RefCounted
## Counts what an opponent tends to do in a few recurring spots (ledge options,
## techs, getups, rolls, shielding when approached, air dodging after a launch),
## from what the CPU perceives. Counts decay so recent habits weigh more. Per
## match and deterministic, unlike amiibo, which learn across matches.

## Recurring spots, each with its own options.
enum Bucket { LEDGE, TECH, GETUP, ROLL, APPROACHED, LAUNCHED }

## Counts lose this share per observation in the same bucket.
const DECAY := 0.85

var _counts: Dictionary[int, Dictionary] = {}
var _roll_bucket := -1
var _roll_start_x := 0.0


## Records that the opponent chose [param option] in [param bucket].
func record(bucket: Bucket, option: StringName) -> void:
	var counts: Dictionary = _counts.get(bucket, {})
	for key: StringName in counts:
		counts[key] = float(counts[key]) * DECAY
	counts[option] = float(counts.get(option, 0.0)) + 1.0
	_counts[bucket] = counts


## The most likely option in [param bucket], or &"" with no data.
func likely(bucket: Bucket) -> StringName:
	var counts: Dictionary = _counts.get(bucket, {})
	var best := &""
	var best_count := 0.0
	for key: StringName in counts:
		if float(counts[key]) > best_count:
			best_count = float(counts[key])
			best = key
	return best


## Compares the target's previous perceived snapshot with the new one and
## records any choice it made. Directions are stored relative to [param me]
## (toward / away).
func observe(before: FighterSnapshot, now: FighterSnapshot, me: FighterSnapshot, _stage: StageModel) -> void:
	if before.state_started == now.state_started or before.index != now.index:
		return
	var toward_me := 1 if me.position.x >= now.position.x else -1
	# Rolls and tech rolls are judged when they end, by how far they went.
	if before.activity == FighterSnapshot.Activity.DODGE and _roll_bucket >= 0:
		var moved := now.position.x - _roll_start_x
		var direction := &"in_place"
		if absf(moved) > 4.0:
			direction = &"toward" if signf(moved) == toward_me else &"away"
		record(_roll_bucket as Bucket, direction)
		_roll_bucket = -1
	match before.activity:
		FighterSnapshot.Activity.LEDGE:
			match now.state_name:
				&"LedgeClimb", &"LedgeRoll", &"LedgeJump":
					record(Bucket.LEDGE, now.state_name)
				_:
					if now.activity == FighterSnapshot.Activity.AIR:
						record(Bucket.LEDGE, &"LedgeDrop")
		FighterSnapshot.Activity.HITSTUN, FighterSnapshot.Activity.TUMBLE:
			if now.state_name == &"Tech":
				record(Bucket.TECH, &"in_place")
			elif now.state_name == &"TechRoll":
				_start_roll(Bucket.TECH, now)
			elif now.activity == FighterSnapshot.Activity.KNOCKDOWN:
				record(Bucket.TECH, &"missed")
			elif now.activity == FighterSnapshot.Activity.AIR_DODGE and before.activity == FighterSnapshot.Activity.HITSTUN:
				record(Bucket.LAUNCHED, &"air_dodge")
		FighterSnapshot.Activity.KNOCKDOWN:
			if now.state_name == &"Getup":
				record(Bucket.GETUP, &"in_place")
			elif now.state_name == &"GetupRoll":
				_start_roll(Bucket.GETUP, now)
		FighterSnapshot.Activity.SHIELD:
			if now.state_name == &"ForwardRoll" or now.state_name == &"BackRoll":
				_start_roll(Bucket.ROLL, now)
	if now.activity == FighterSnapshot.Activity.SHIELD and before.activity != FighterSnapshot.Activity.SHIELD \
			and absf(now.position.x - me.position.x) < 30.0:
		record(Bucket.APPROACHED, &"shield")
	elif now.activity == FighterSnapshot.Activity.ATTACK and absf(now.position.x - me.position.x) < 30.0:
		record(Bucket.APPROACHED, &"attack")


func _start_roll(bucket: Bucket, now: FighterSnapshot) -> void:
	_roll_bucket = bucket
	_roll_start_x = now.position.x
