class_name CpuController
extends FighterController
## A computer player. It drives its fighter only through [InputFrame]s, like a
## pad, and sees other fighters only through [AiWorld] snapshots that are its
## reaction time old (docs/ai.md: fairness rules R0-R7).
##
## Each [method poll]: perception (delayed views of the other fighters,
## extrapolated to now; threats in range), then situation choice (the first
## [CpuSituation] that applies, in priority order), then the situation scores
## its tactics and fills the [InputPlan], which emits this frame's input.
##
## Levels 1-9 follow Smash; level 10 is a hidden frame-perfect debug level.
## [enum Mode] holds Smash's training CPU modes.

## FIGHT is normal play; the rest are Smash's training modes. STAND, SHIELD and
## JUMP are the training dummy. All of them still DI, tech, recover, get up and
## leave ledges.
enum Mode { FIGHT, STAND, SHIELD, JUMP, WALK, EVADE }

const DEFAULT_LEVEL := 3
const MAX_LEVEL := 9
## Hidden debug level: one-frame reactions and no errors.
const DEBUG_LEVEL := 10
## Frames of prediction kept for the target's path.
const PATH_FRAMES := 45
## How much a recently used tactic's score drops, and how fast that fades
## (per frame).
const REPEAT_PENALTY := 1.2
const REPEAT_DECAY := 0.993
const PERSONALITY_VARIATION := 0.15
## Frames followed after an aerial starts, for the R3 check (longest aerial plus its delay).
const AFTER_FRAMES := 80
## Simulated frames the R3 checks may spend per poll (see [method recoverable_after]).
const R3_BUDGET := 600

## Prints recovery plans and R3 checks (ladder harness --log-plans).
static var debug_log := false

var level := DEFAULT_LEVEL:
	set = set_level
## Smash's internal value / 100 for [member level] (or any value in between).
var skill := 0.21
var mode := Mode.FIGHT
## DI of the training modes (STAND, SHIELD, JUMP); FIGHT uses the level's DI.
var dummy_di := AiDi.Mode.NONE
var world: AiWorld
var difficulty: CpuDifficulty
var params: CpuDifficulty.Params
var personality: CpuPersonality
var profile: CpuProfile
var rng := RandomNumberGenerator.new()
var plan := InputPlan.new()
var habits := HabitModel.new()
var telemetry := CpuTelemetry.new()

#region Perception (refreshed every poll)
var fighter: Fighter
var stage: StageModel
var book: MoveBook
## This CPU's own fighter, now (it knows its own state immediately).
var me := FighterSnapshot.new()
var my_index := -1
## Index of the opponent it's focused on, -1 for none.
var target_index := -1
## The target as the CPU believes it is now: its delayed view, extrapolated.
var target := FighterSnapshot.new()
var target_book: MoveBook
## Age of the target view this frame (reaction delay plus jitter).
var reaction_delay := 0
## Frames until a perceived opponent hitbox reaches this fighter (-1: none),
## when it ends, and which opponent action it belongs to.
var threat_in := -1
var threat_end := -1
var threat_id := -1
#endregion

#region Decision state
var situation: CpuSituation
var tactic := &""
var tactic_score := 0.0
## The attack option last chosen, when and from where (AI debug drawing).
var last_option: MoveBook.Option
var last_option_frame := 0
var last_option_origin := Vector2.ZERO
## Polls so far.
var frame := 0
#endregion

var _situations: Array[CpuSituation] = []
var _view_frame := 0
var _jitter := 0
var _seen_state := -1
var _last_hit: HitInfo
var _forced := false
var _recent: Dictionary[StringName, Vector2] = {}
var _my_path := PackedVector2Array()
var _target_path := PackedVector2Array()
var _path_frame := -1
# Own jump and air paths for this frame's hit queries (see MoveBook.moves_hitting).
var _jump_paths: Dictionary = {}
# Whether each move (by profile and facing) would KO the target this frame.
var _kills: Dictionary = {}
# Where aerials leave the fighter, and whether it can get back from there, this frame.
var _after_paths: Dictionary = {}
var _safe_after: Dictionary = {}
var _r3_budget := 0
var _scratch := PackedVector2Array()
var _previous_target := FighterSnapshot.new()


func _init(p_level: int = DEFAULT_LEVEL, p_mode: Mode = Mode.FIGHT, p_seed: int = 0) -> void:
	difficulty = CpuDifficulty.load_default()
	mode = p_mode
	rng.seed = p_seed
	level = p_level
	_build_situations()


## Sets the level (1-9, or [constant DEBUG_LEVEL]) and its skill value.
func set_level(value: int) -> void:
	level = clampi(value, 1, DEBUG_LEVEL)
	if not difficulty:
		return
	if level == DEBUG_LEVEL:
		skill = 1.0
		params = difficulty.frame_perfect()
	else:
		set_skill(CpuDifficulty.skill_for_level(level))


## Sets an arbitrary skill (0-1) between levels, as Smash events do.
func set_skill(value: float) -> void:
	skill = clampf(value, 0.0, 1.0)
	params = difficulty.sample(skill)


func set_mode(value: Mode) -> void:
	mode = value
	_build_situations()


## The random seed of the CPU in slot [param slot_index] of a match seeded with [param match_seed].
static func seed_for(match_seed: int, slot_index: int) -> int:
	return hash([match_seed, slot_index])


## Seeds the CPU's random choices (from the match seed and slot) and varies its
## personality from the profile's.
func setup(p_world: AiWorld, p_seed: int, p_profile: CpuProfile = null) -> void:
	world = p_world
	rng.seed = p_seed
	profile = p_profile
	var base := p_profile.personality if p_profile and p_profile.personality else CpuPersonality.new()
	personality = base.varied(rng, PERSONALITY_VARIATION)


## Runs [param builder] (func(plan: InputPlan) -> void) as a plan right away,
## ignoring the situations until it's done. For tests and the debug overlay.
func force_plan(builder: Callable) -> void:
	plan.clear()
	builder.call(plan)
	plan.label = "forced"
	plan.committed = true
	_forced = true


func poll(p_fighter: Fighter) -> InputFrame:
	frame += 1
	fighter = p_fighter
	if not personality:
		personality = CpuPersonality.new()
	if not book or book.moveset != fighter.moveset:
		book = MoveBook.of(fighter.moveset)
	if fighter.last_hit != _last_hit:
		_last_hit = fighter.last_hit
		if _last_hit and not _last_hit.shielded:
			plan.clear()
			_forced = false
	if fighter.state is KOState or fighter.state is RespawnState and fighter.state.frame <= 1:
		plan.clear()
		_forced = false

	if world:
		_perceive()
	if _forced and plan.is_empty():
		_forced = false
	if not _forced:
		var next := _pick_situation()
		if next != situation:
			if situation:
				situation.exit(self)
			situation = next
			if situation:
				situation.enter(self)
			# Entering a situation about the fighter's own state (offstage, on a
			# ledge, knocked down, respawning) drops plans made for something else:
			# a ledge option once off the ledge, an approach once offstage.
			if next and next.takes_over() and not plan.carries_over and plan.owner != next.situation_name():
				plan.clear()
		if situation:
			situation.update(self)
			if plan.owner == &"" and not plan.is_empty():
				plan.owner = situation.situation_name()
	var input := plan.next(fighter)
	if not input:
		input = InputFrame.new()
		input.tap_jump = false
	return input


#region Perception

func _perceive() -> void:
	stage = world.stage_model
	my_index = world.index_of(fighter)
	me.capture(fighter, my_index, world.frame, world.fighters)
	_choose_target()
	threat_in = -1
	threat_end = -1
	if target_index < 0:
		return
	# Delayed view: reaction time plus a jitter re-rolled on each new thing the
	# target starts doing. The view never runs backwards and never gets fresher
	# than the reaction time.
	var desired := params.reaction_frames + _jitter
	var at := maxi(_view_frame, world.frame - desired)
	var view := world.view_at(target_index, at)
	if not view:
		target_index = -1
		return
	_view_frame = view.frame
	if view.state_started != _seen_state:
		_seen_state = view.state_started
		_jitter = rng.randi_range(0, params.reaction_jitter) if params.reaction_jitter > 0 else 0
	reaction_delay = world.frame - view.frame
	_previous_target.copy_from(target)
	target.copy_from(view)
	Predict.extrapolate(target, roundi(reaction_delay * params.extrapolation), stage, _scratch)
	target_book = MoveBook.of(target.moveset)
	_path_frame = -1
	_jump_paths.clear()
	_kills.clear()
	_after_paths.clear()
	_safe_after.clear()
	_r3_budget = R3_BUDGET
	_detect_threat()
	if params.adaptation > 0.0 and _previous_target.is_valid():
		habits.observe(_previous_target, target, me, stage)


## Target choice uses only what can be seen (distance, threat, percent,
## offstage), never who controls a fighter (rule R6).
func _choose_target() -> void:
	var best := -1
	var best_score := -INF
	for i in world.fighters.size():
		if i == my_index:
			continue
		var view := world.view(i, params.reaction_frames)
		if not view:
			continue
		var score := -absf(view.position.x - me.position.x) / 40.0 - absf(view.position.y - me.position.y) / 60.0
		score += view.percent / 150.0
		if not view.is_alive():
			score -= 5.0
		if view.activity == FighterSnapshot.Activity.ATTACK:
			score += 0.5
		if i == target_index:
			score += 0.75
		if score > best_score:
			best_score = score
			best = i
	if best != target_index:
		_seen_state = -1
		_view_frame = 0
		target = FighterSnapshot.new()
	target_index = best


## Whether a perceived opponent hitbox will reach this fighter if it stays
## put, and when ([member threat_in], [member threat_end]).
func _detect_threat() -> void:
	if target.activity != FighterSnapshot.Activity.ATTACK or not target.move:
		return
	var move_profile := target_book.get_profile(target.move_slot)
	if not move_profile or not move_profile.has_hitboxes() or target.state_frame >= move_profile.active_end:
		return
	_fill_my_path(move_profile.active_end - target.state_frame + 1)
	var no_path := PackedVector2Array()
	var attacker_path := no_path if target.grounded else predicted_path()
	var shift := move_profile.displacement[mini(target.state_frame, move_profile.total)]
	var origin := target.position - Vector2(shift.x * target.facing, shift.y)
	var t := move_profile.first_contact(origin, attacker_path, target.facing, -target.state_frame,
			_my_path, me.hurt_height + 2.0, me.hurt_radius + 1.0)
	if t < 0:
		return
	threat_in = t
	threat_end = move_profile.active_end - target.state_frame
	threat_id = target.state_started * 8 + target.index


func _fill_my_path(frames: int) -> void:
	frames = clampi(frames, 1, PATH_FRAMES)
	if me.grounded:
		_my_path.resize(frames + 1)
		_my_path.fill(me.position)
	else:
		_my_path = Predict.air_path(me.stats, me.position, me.velocity_self, me.velocity_knockback,
				me.fast_falling, 0.0, frames, stage)

#endregion


#region Helpers for situations

## The target's predicted feet, frame by frame from now (index 0 is the
## perceived present). Computed on first use each frame.
func predicted_path() -> PackedVector2Array:
	if _path_frame != frame:
		_path_frame = frame
		Predict.trajectory(target, PATH_FRAMES, stage, _target_path)
	return _target_path


func has_target() -> bool:
	return target_index >= 0 and target.is_valid() and target.is_alive()


## Whether the fighter can start something new this frame.
func can_act() -> bool:
	if fighter.hitlag_frames > 0 or fighter.state.frames_until_actionable() > 0:
		return false
	var state := fighter.state
	if state is AirState:
		return not (state as AirState).helpless
	return state is IdleState or state is WalkState or state is DashState or state is RunState \
			or state is RunBrakeState or state is CrouchState or state is ShieldState or state is LedgeHangState


## Grounded and free to walk, dash or attack.
func can_act_grounded() -> bool:
	return fighter.grounded and can_act() and not fighter.state is ShieldState


func is_shielding() -> bool:
	return fighter.state is ShieldState


## Whether the current plan may be replaced.
func can_replan() -> bool:
	return plan.is_empty() or not plan.committed


func toward_target() -> int:
	return 1 if target.position.x >= me.position.x else -1


func distance_to_target() -> float:
	return me.position.distance_to(target.position)


## Horizontal gap between the two bodies.
func gap_to_target() -> float:
	return absf(target.position.x - me.position.x) - me.hurt_radius - target.hurt_radius


## Whether the level's move pool (and the character profile) allows [param move_profile] now.
func allowed_move(move_profile: MoveProfile, offstage: bool = false) -> bool:
	var tier := params.move_pool
	match move_profile.category:
		MoveProfile.Category.SMASH:
			if tier < 1:
				return false
		MoveProfile.Category.AERIAL:
			if tier < 2:
				return false
			if tier < 3 and me.grounded and target.grounded:
				return false
		MoveProfile.Category.SPECIAL:
			# Specials as attacks only out of shield (helpless risk), from tier 5.
			if tier < 5 or not is_shielding():
				return false
	# A helpless move near the edge can carry the fighter off for good.
	if move_profile.ends_in_helpless and stage and stage.edge_distance(me.position.x) < 45.0:
		return false
	if offstage and profile and profile.never_offstage.has(move_profile.slot):
		return false
	return true


## Every way to hit the target within [param within] frames, using the
## [param approaches] (bitmask of 1 << [enum MoveBook.Approach]) that the
## fighter's state allows right now.
func hit_options(approaches: int, within: int, offstage_ok: bool = false) -> Array[MoveBook.Option]:
	return hit_options_against(predicted_path(), approaches, within, offstage_ok)


## [method hit_options] against a given target path (e.g. where a ledge getup ends).
func hit_options_against(path: PackedVector2Array, approaches: int, within: int,
		offstage_ok: bool = false) -> Array[MoveBook.Option]:
	if not has_target():
		return []
	approaches &= approaches_now()
	if approaches == 0:
		return []
	var filter := func(p: MoveProfile) -> bool: return allowed_move(p, offstage_ok)
	var options := book.moves_hitting(me, target, path, within, stage, approaches, filter, _jump_paths)
	if offstage_ok:
		return options
	# Rule R3: no aerial that leaves the fighter somewhere it can't get back from.
	var safe: Array[MoveBook.Option] = []
	for option in options:
		if recoverable_after(option):
			safe.append(option)
	return safe


## Whether the fighter can still get back to the stage after [param option]
## (rule R3): where its jump or drift leaves it when the move ends, with the
## jumps and up special it will have left. Ground moves stop at edges. The
## checks share [constant R3_BUDGET] simulated frames per poll; past that,
## the answer is "no".
func recoverable_after(option: MoveBook.Option) -> bool:
	var after := path_after(option)
	if after.is_empty():
		return true
	var frames := mini(option.delay + option.profile.total, AFTER_FRAMES)
	var jumping := _jumps(option)
	var key := Vector4i(option.approach, roundi(option.drift), frames / 8, option.profile.active_end)
	if _safe_after.has(key):
		return _safe_after[key]
	# Toward the target until the hitboxes are done; from then on Recover
	# drifts it home (RecoverSituation), so follow the same rule.
	var switch := clampi(option.delay + option.profile.active_end, 1, frames)
	var body := Predict.Body.new(me.stats, after[switch], after[switch] - after[switch - 1])
	body.fast_falling = me.fast_falling and not jumping
	for i in range(switch, frames):
		Predict.air_frame(body, stage, stage.home_direction(body.position, me.hurt_radius))
		if body.grounded:
			break
	var end := body.position
	if body.grounded or not stage.is_offstage(end):
		if debug_log:
			print("    R3 f%d %s %s drift %.0f: ends %s %s -> safe" % [frame, option.profile.slot, MoveBook.Approach.keys()[option.approach],
					option.drift, end, "grounded" if body.grounded else "onstage"])
		_safe_after[key] = true
		return true
	var safe := false
	if _r3_budget > 0:
		var start := RecoveryPlanner.Start.new()
		start.body = body
		start.facing = me.facing
		start.jumps_left = me.stats.jump_count - 1 if jumping else me.jumps_left
		start.air_dodge_used = me.air_dodge_used
		start.special = fighter.moveset.up_special
		if start.special:
			start.special_rise = RecoveryPlanner.special_reach(start.special, me.stats).y
		var before := RecoveryPlanner.steps
		safe = RecoveryPlanner.recoverable(start, stage, mini(_r3_budget, 400))
		_r3_budget -= RecoveryPlanner.steps - before
	if debug_log:
		print("    R3 f%d %s %s drift %.0f: ends %s offstage, jumps %d -> %s" % [frame, option.profile.slot,
				MoveBook.Approach.keys()[option.approach], option.drift, end, me.jumps_left, safe])
	_safe_after[key] = safe
	return safe


## The fighter's feet over the next [constant AFTER_FRAMES] frames if it
## starts [param option] now (jumping or drifting), or empty for ground moves.
## Cached per poll.
func path_after(option: MoveBook.Option) -> PackedVector2Array:
	if not _jumps(option):
		return _air_after(option) if option.approach == MoveBook.Approach.AIR else PackedVector2Array()
	var full := option.approach == MoveBook.Approach.FULL_HOP
	var key := Vector2(1.0 if full else 0.0, option.drift)
	if not _after_paths.has(key):
		_after_paths[key] = Predict.jump_path(me.stats, me.position, me.velocity_self.x, full, option.drift,
				AFTER_FRAMES, stage)
	return _after_paths[key]


static func _jumps(option: MoveBook.Option) -> bool:
	var approach := option.approach
	return approach == MoveBook.Approach.SHORT_HOP or approach == MoveBook.Approach.FULL_HOP \
			or approach == MoveBook.Approach.OUT_OF_SHIELD and option.profile.is_aerial


func _air_after(option: MoveBook.Option) -> PackedVector2Array:
	var key := Vector2(-1.0, option.drift)
	if not _after_paths.has(key):
		_after_paths[key] = Predict.air_path(me.stats, me.position, me.velocity_self, me.velocity_knockback,
				me.fast_falling, option.drift, AFTER_FRAMES, stage)
	return _after_paths[key]


## The approaches this level may use from the state the fighter is in now:
## out of shield while shielding, ground moves and jumps on the ground,
## aerials in the air.
func approaches_now() -> int:
	var result := 0
	if is_shielding():
		return 1 << MoveBook.Approach.OUT_OF_SHIELD if params.move_pool >= 5 else 0
	if fighter.grounded:
		result |= 1 << MoveBook.Approach.STAND | 1 << MoveBook.Approach.TURN
		if fighter.state is IdleState or fighter.state is WalkState or fighter.state is RunBrakeState:
			result |= 1 << MoveBook.Approach.DASH
		# Jumping attacks only where they can matter: full hops at targets
		# above, short hops at targets within a few dashes.
		var dx := absf(target.position.x - me.position.x)
		var above := target.position.y - me.position.y
		if params.move_pool >= 2 and above > 12.0 and dx < 70.0:
			result |= 1 << MoveBook.Approach.FULL_HOP
		if params.move_pool >= 3 and dx < 60.0 and above > -10.0:
			result |= 1 << MoveBook.Approach.SHORT_HOP
	else:
		result |= 1 << MoveBook.Approach.AIR
	return result


## Base value of hitting with [param option]: damage, a bonus for KOs, minus
## the risk of being punished, plus style.
func option_value(option: MoveBook.Option, kill_bonus: float = 6.0) -> float:
	var move_profile := option.profile
	var value := move_profile.damage * 0.35 - option.frames * 0.04
	var kill_key := Vector2i(move_profile.get_instance_id(), option.facing)
	if not _kills.has(kill_key):
		_kills[kill_key] = move_profile.kills(target, option.facing, stage)
	if _kills[kill_key]:
		value += kill_bonus
		if profile and profile.kill_moves.has(move_profile.slot):
			value += 1.0
	if target.is_shielding():
		var deficit := -move_profile.shield_advantage - target_book.fastest_startup
		value -= maxf(deficit, 0.0) * 0.15 + move_profile.damage * 0.25
	else:
		value -= maxf(move_profile.whiff_lag - 15, 0) * 0.03
	if move_profile.is_aerial:
		value += personality.air_preference * 1.2
	else:
		value -= personality.air_preference * 0.6
	if move_profile.is_smash:
		value += personality.risk * 1.2
	if profile:
		value += profile.move_bias(move_profile.slot)
	return value


## Picks a tactic with a softmax over utility minus a penalty for recent use
## (rule R2): noisy at low levels, near-greedy at high levels, never fixed.
func pick(tactics: Array[CpuSituation.Tactic]) -> CpuSituation.Tactic:
	if tactics.is_empty():
		return null
	var scores := PackedFloat32Array()
	var best := -INF
	for t in tactics:
		var score := t.utility - recent_use(t.name) * REPEAT_PENALTY
		scores.append(score)
		best = maxf(best, score)
	var total := 0.0
	for i in scores.size():
		scores[i] = exp((scores[i] - best) / maxf(params.temperature, 0.01))
		total += scores[i]
	var roll := rng.randf() * total
	for i in scores.size():
		roll -= scores[i]
		if roll <= 0.0:
			return tactics[i]
	return tactics.back()


## Runs [param chosen]: rolls follow-through for offensive tactics (hesitating
## on failure, Smash's main level lever), then fills the plan. Returns whether
## the tactic was used.
func use(chosen: CpuSituation.Tactic, committed: bool = false) -> bool:
	if not chosen:
		return false
	plan.clear()
	if chosen.offensive and rng.randf() > params.follow_through:
		hesitate()
		return false
	chosen.build.call(plan)
	plan.label = chosen.name
	plan.committed = committed
	tactic = chosen.name
	tactic_score = chosen.utility
	remember(chosen.name)
	if chosen.option:
		telemetry.count_move(chosen.option.profile.slot)
		last_option = chosen.option
		last_option_frame = frame
		last_option_origin = me.position
	return true


## Waits a moment instead of acting.
func hesitate() -> void:
	plan.clear()
	plan.wait(rng.randi_range(4, 6 + roundi((1.0 - skill) * 14.0)))
	plan.label = "hesitate"
	tactic = &"hesitate"


## [param frames] with the level's timing error.
func jitter(frames: int) -> int:
	if params.timing_error <= 0.0:
		return frames
	return maxi(frames + roundi(rng.randfn(0.0, params.timing_error)), 0)


## Random spacing error in units.
func spacing_noise() -> float:
	return rng.randf_range(-params.spacing_error, params.spacing_error)


func recent_use(tactic_name: StringName) -> float:
	var entry: Vector2 = _recent.get(tactic_name, Vector2.ZERO)
	return entry.x * pow(REPEAT_DECAY, frame - entry.y)


## Counts a use of [param tactic_name] for the repetition penalty.
func remember(tactic_name: StringName) -> void:
	_recent[tactic_name] = Vector2(recent_use(tactic_name) + 1.0, frame)


## Builds a plan for [param option] (from [method hit_options]).
func build_attack(target_plan: InputPlan, option: MoveBook.Option, charge: int = 0) -> void:
	var move_profile := option.profile
	var slot := move_profile.slot
	var facing := option.facing
	match option.approach:
		MoveBook.Approach.STAND, MoveBook.Approach.TURN:
			if option.approach == MoveBook.Approach.TURN:
				target_plan.turn(facing)
			_build_ground_move(target_plan, move_profile, facing, charge)
		MoveBook.Approach.DASH:
			target_plan.hold(1)
			target_plan.hold(1, Vector2(facing, 0.0))
			target_plan.hold(1, Vector2(facing * 0.5, 0.0), InputPlan.ATTACK)
			target_plan.hold(1)
		# Aerials drift as the hit query assumed until they connect, then let go.
		MoveBook.Approach.SHORT_HOP:
			target_plan.short_hop_aerial(slot, me.facing, option.drift, maxi(option.frames - option.delay - 2, 0))
			target_plan.hold_until(InputPlan.Until.GROUNDED, move_profile.total)
		MoveBook.Approach.FULL_HOP:
			target_plan.jump_aerial(slot, me.facing, option.delay, option.drift, maxi(option.frames - option.delay, 0))
			target_plan.hold_until(InputPlan.Until.GROUNDED, move_profile.total)
		MoveBook.Approach.AIR:
			target_plan.aerial(slot, me.facing, option.drift, option.frames)
			target_plan.hold_until(InputPlan.Until.GROUNDED, move_profile.total)
		MoveBook.Approach.OUT_OF_SHIELD:
			if slot == Moveset.UP_SPECIAL:
				target_plan.special(Vector2(0.0, 1.0), option.drift, move_profile.total)
			elif slot == Moveset.UP_SMASH:
				target_plan.hold(1, Vector2.ZERO, InputPlan.JUMP | InputPlan.SHIELD)
				target_plan.hold(1, Vector2(0.0, 1.0), InputPlan.SMASH)
				target_plan.hold(1)
			else:
				target_plan.hold(1, InputPlan.aerial_stick(slot, me.facing), InputPlan.JUMP | InputPlan.SHIELD)
				target_plan.hold(1, InputPlan.aerial_stick(slot, me.facing), InputPlan.ATTACK)
				target_plan.hold(3 + move_profile.total, Vector2(option.drift, 0.0))


func _build_ground_move(target_plan: InputPlan, move_profile: MoveProfile, facing: int, charge: int) -> void:
	var slot := move_profile.slot
	if move_profile.is_smash:
		target_plan.smash_attack(slot, facing, charge, move_profile.move.charge_frame)
	elif move_profile.is_special:
		target_plan.special(InputPlan.special_stick(slot, facing))
	else:
		target_plan.tilt(slot, facing)


## The direction toward the stage's center.
func toward_stage() -> int:
	return 1 if stage.center_x() >= me.position.x else -1


## One line per piece of state, for the AI debug overlay (F3).
func debug_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	lines.append("  CPU lv%s%s  %s  seed %d" % [level, " (frame-perfect)" if level == DEBUG_LEVEL else "",
			Mode.keys()[mode], rng.seed])
	lines.append("  situation %s  tactic %s (%.2f)  reaction %d f" % [
			situation.situation_name() if situation else &"-", tactic, tactic_score, reaction_delay])
	lines.append("  plan [%s] %s" % [plan.label, plan.describe()])
	if threat_in >= 0:
		lines.append("  threat in %d f (until %d)" % [threat_in, threat_end])
	return lines

#endregion


func _pick_situation() -> CpuSituation:
	for candidate in _situations:
		if candidate.applies(self):
			return candidate
	return null


func _build_situations() -> void:
	_situations = [HitReactionSituation.new(), RecoverSituation.new(), LedgeSituation.new(),
			GroundedDownSituation.new(), RespawnSituation.new()]
	if mode == Mode.FIGHT:
		_situations.append_array([DefendSituation.new(), PunishSituation.new(), AdvantageSituation.new(),
				EdgeguardSituation.new(), NeutralSituation.new()])
	else:
		_situations.append(TrainingModeSituation.new())
	situation = null
