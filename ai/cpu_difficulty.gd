class_name CpuDifficulty
extends Resource
## How CPU skill (0 to 1) maps to every tuning parameter, one [Curve] per
## parameter so they can be tuned in the inspector. Levels 1-9 map to Smash's
## internal 0-100 values (Brawl on), so the uneven steps between levels carry
## over and an event or test can ask for any skill in between.
##
## [constant STARTING_VALUES] holds the table from plans/cpu-ai.md, tuned with
## the ladder harness (tests/ai_ladder.gd; docs/ai.md records the changes);
## ai/tools/build_cpu_difficulty.gd turns it into ai/cpu_difficulty.tres.
## docs/ai.md explains each parameter.

## Smash's internal value (0-100) for levels 1-9 (SmashWiki, "Artificial intelligence").
const LEVEL_VALUES: Array[int] = [0, 15, 21, 31, 42, 48, 60, 75, 100]
const DEFAULT_PATH := "res://ai/cpu_difficulty.tres"

## Value of each parameter at levels 1-9.
const STARTING_VALUES := {
	"reaction_frames": [40, 36, 32, 30, 27, 25, 22, 18, 10],
	"reaction_jitter": [8, 7, 7, 6, 5, 5, 4, 3, 2],
	"extrapolation": [0.0, 0.1, 0.2, 0.35, 0.5, 0.6, 0.75, 0.9, 1.0],
	"decision_interval": [30, 26, 24, 20, 16, 14, 10, 7, 4],
	"follow_through": [0.15, 0.30, 0.42, 0.48, 0.58, 0.68, 0.75, 0.87, 0.98],
	"defend_chance": [0.05, 0.12, 0.20, 0.25, 0.35, 0.45, 0.55, 0.70, 0.85],
	"defend_quality": [0.0, 0.1, 0.2, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0],
	"punish_chance": [0.05, 0.12, 0.22, 0.28, 0.38, 0.50, 0.60, 0.78, 0.95],
	"combo_depth": [0, 0, 0, 1, 1, 1, 2, 2, 4],
	"spacing_error": [8.0, 7.0, 6.0, 5.0, 4.0, 3.5, 2.5, 1.5, 0.5],
	"timing_error": [6.0, 5.0, 5.0, 4.0, 3.0, 3.0, 2.0, 1.0, 0.5],
	"move_pool": [0, 1, 2, 3, 4, 5, 6, 7, 8],
	"smash_charge": [0.0, 0.0, 0.0, 0.0, 0.5, 0.6, 0.75, 0.9, 1.0],
	"tech_chance": [0.0, 0.05, 0.10, 0.20, 0.35, 0.45, 0.60, 0.75, 0.90],
	"tech_mixup": [0.0, 0.0, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 1.0],
	"di_quality": [0.0, 0.0, 0.2, 0.35, 0.5, 0.7, 0.8, 0.9, 1.0],
	"recovery_options": [0, 1, 2, 3, 4, 5, 6, 7, 8],
	"edgeguard_appetite": [0.0, 0.0, 0.0, 0.1, 0.25, 0.35, 0.5, 0.7, 0.9],
	"ledge_mixup": [0.0, 0.1, 0.2, 0.3, 0.45, 0.55, 0.7, 0.85, 1.0],
	"anticipation": [0.0, 0.0, 0.0, 0.0, 0.1, 0.2, 0.35, 0.5, 0.7],
	"adaptation": [0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.5, 0.7, 1.0],
}

## Perception delay: how many frames old the CPU's view of other fighters is.
@export var reaction_frames: Curve
## Random extra frames of delay, rolled per reaction event.
@export var reaction_jitter: Curve
## How far (0-1) it predicts the present from its delayed view.
@export var extrapolation: Curve
## Frames between re-plans in neutral.
@export var decision_interval: Curve
## Chance of acting on a chosen offensive option; otherwise it hesitates.
@export var follow_through: Curve
## Chance of responding to a perceived threat at all.
@export var defend_chance: Curve
## How well (0-1) the defensive option is chosen instead of picked at random.
@export var defend_quality: Curve
## Chance of punishing perceived endlag.
@export var punish_chance: Curve
## Follow-ups chained after a hit, with true-combo checks.
@export var combo_depth: Curve
## Units of random error on the range it aims for.
@export var spacing_error: Curve
## Frames of random error on macro timings (tech press, ledge release, hops).
@export var timing_error: Curve
## Move pool tier (0-8): which move categories it uses (docs/ai.md).
@export var move_pool: Curve
## Share (0-1) of a punish window spent charging smash attacks.
@export var smash_charge: Curve
## Chance of pressing shield in the tech window.
@export var tech_chance: Curve
## How evenly (0-1) it mixes tech in place, toward and away.
@export var tech_mixup: Curve
## DI: 0 none, then random, then survival DI some of the time, then
## situational (combo DI at low percent), then simulated optimal DI and SDI.
@export var di_quality: Curve
## Recovery option tier (0-8): which recovery tools it may use and mix.
@export var recovery_options: Curve
## Willingness (0-1) to edgeguard: covering the ledge, then going offstage.
@export var edgeguard_appetite: Curve
## Variety (0-1) of ledge and getup options and timings.
@export var ledge_mixup: Curve
## Chance (0-1) of defending pre-emptively when an opponent approaches in range.
@export var anticipation: Curve
## Strength (0-1) of the opponent habit model.
@export var adaptation: Curve


## Every parameter at one skill value, as plain numbers.
class Params:
	var skill := 0.0
	var reaction_frames := 40
	var reaction_jitter := 8
	var extrapolation := 0.0
	var decision_interval := 30
	var follow_through := 0.15
	var defend_chance := 0.05
	var defend_quality := 0.0
	var punish_chance := 0.05
	var combo_depth := 0
	var spacing_error := 8.0
	var timing_error := 6.0
	var move_pool := 0
	var smash_charge := 0.0
	var tech_chance := 0.0
	var tech_mixup := 0.0
	var di_quality := 0.0
	var recovery_options := 0
	var edgeguard_appetite := 0.0
	var ledge_mixup := 0.0
	var anticipation := 0.0
	var adaptation := 0.0
	## Softmax temperature for tactic choice: noisy at low skill, near-greedy at high.
	var temperature := 2.0


static func load_default() -> CpuDifficulty:
	if ResourceLoader.exists(DEFAULT_PATH):
		var loaded := load(DEFAULT_PATH) as CpuDifficulty
		if loaded:
			return loaded
	return from_table(STARTING_VALUES)


## Skill (0-1) for a level 1-9 (Smash's internal value / 100).
static func skill_for_level(level: int) -> float:
	return LEVEL_VALUES[clampi(level, 1, LEVEL_VALUES.size()) - 1] / 100.0


## Builds the curves from a table of per-level values (see [constant STARTING_VALUES]).
static func from_table(table: Dictionary) -> CpuDifficulty:
	var difficulty := CpuDifficulty.new()
	for key: String in table:
		var values: Array = table[key]
		var curve := Curve.new()
		var low := 0.0
		var high := 1.0
		for value: float in values:
			low = minf(low, value)
			high = maxf(high, value)
		curve.min_value = low
		curve.max_value = high
		for i in values.size():
			curve.add_point(Vector2(LEVEL_VALUES[i] / 100.0, float(values[i])), 0.0, 0.0,
					Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		difficulty.set(key, curve)
	return difficulty


## Samples every curve at [param skill].
func sample(skill: float) -> Params:
	var p := Params.new()
	p.skill = clampf(skill, 0.0, 1.0)
	p.reaction_frames = roundi(_at(reaction_frames, p.skill, 40.0))
	p.reaction_jitter = roundi(_at(reaction_jitter, p.skill, 8.0))
	p.extrapolation = _at(extrapolation, p.skill, 0.0)
	p.decision_interval = maxi(roundi(_at(decision_interval, p.skill, 30.0)), 1)
	p.follow_through = _at(follow_through, p.skill, 0.15)
	p.defend_chance = _at(defend_chance, p.skill, 0.05)
	p.defend_quality = _at(defend_quality, p.skill, 0.0)
	p.punish_chance = _at(punish_chance, p.skill, 0.05)
	p.combo_depth = floori(_at(combo_depth, p.skill, 0.0) + 0.001)
	p.spacing_error = _at(spacing_error, p.skill, 8.0)
	p.timing_error = _at(timing_error, p.skill, 6.0)
	p.move_pool = floori(_at(move_pool, p.skill, 0.0) + 0.001)
	p.smash_charge = _at(smash_charge, p.skill, 0.0)
	p.tech_chance = _at(tech_chance, p.skill, 0.0)
	p.tech_mixup = _at(tech_mixup, p.skill, 0.0)
	p.di_quality = _at(di_quality, p.skill, 0.0)
	p.recovery_options = floori(_at(recovery_options, p.skill, 0.0) + 0.001)
	p.edgeguard_appetite = _at(edgeguard_appetite, p.skill, 0.0)
	p.ledge_mixup = _at(ledge_mixup, p.skill, 0.0)
	p.anticipation = _at(anticipation, p.skill, 0.0)
	p.adaptation = _at(adaptation, p.skill, 0.0)
	p.temperature = lerpf(3.0, 0.35, p.skill)
	return p


## The hidden debug level 10: Smash-faithful level 9 behaviour, with
## one-frame reactions and no errors (ladder harness, benchmarks).
func frame_perfect() -> Params:
	var p := sample(1.0)
	p.reaction_frames = 1
	p.reaction_jitter = 0
	p.extrapolation = 1.0
	p.decision_interval = 1
	p.follow_through = 1.0
	p.defend_chance = 1.0
	p.defend_quality = 1.0
	p.punish_chance = 1.0
	p.combo_depth = 6
	p.spacing_error = 0.0
	p.timing_error = 0.0
	p.tech_chance = 1.0
	p.di_quality = 1.0
	p.anticipation = 1.0
	p.temperature = 0.1
	return p


static func _at(curve: Curve, skill: float, fallback: float) -> float:
	return curve.sample(skill) if curve else fallback
