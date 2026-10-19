class_name RecoverSituation
extends CpuSituation
## Offstage: get back with a [RecoveryPlanner] plan. The plan is checked again
## every few frames from the fighter's real state and replaced if it no longer
## works. High levels pick among more plans (timing and height mixups,
## avoiding repeats and the edgeguarder) and fight back with aerials when that
## still leaves a way home.

const RECHECK_EVERY := 10
## Frames of input built per plan; the plan is rebuilt before it runs out.
const BUILD_FRAMES := 60
## Simulated frames the plan search may spend on its first poll, then per poll
## after that (the search is spread over polls; see [RecoveryPlanner.Search]).
const FIRST_BUDGET := 160
const SLICE_BUDGET := 120

var _plan: RecoveryPlanner.Plan
var _planned_at := 0
var _path := PackedVector2Array()
var _search: RecoveryPlanner.Search
var _search_frame := 0


func situation_name() -> StringName:
	return &"Recover"


func takes_over() -> bool:
	return true


func applies(cpu: CpuController) -> bool:
	var f := cpu.fighter
	if f.grounded or not cpu.stage or f.hitlag_frames > 0:
		return false
	var state := f.state
	if state is HitstunState or state is LedgeHangState or state is LedgeActionState \
			or state is RespawnState or state is KOState:
		return false
	return cpu.stage.is_offstage(cpu.me.position)


func enter(cpu: CpuController) -> void:
	_plan = null
	_search = null
	cpu.telemetry.recoveries += 1


func update(cpu: CpuController) -> void:
	# Let a committed aerial (an edgeguard, a fight-back) come out and hit;
	# once its hitboxes are done, drift home through its endlag.
	if not cpu.plan.is_empty() and cpu.plan.committed and cpu.plan.label != "recover":
		var attack := cpu.fighter.current_attack()
		if attack:
			var profile := cpu.book.get_profile(attack.slot)
			if attack.frame <= (profile.active_end if profile else 0):
				return
		# Anything else (a ledge steal) only while still close to the ledge.
		elif cpu.stage.distance_offstage(cpu.me.position) < 20.0 \
				and cpu.me.position.y > cpu.stage.main_top - cpu.me.stats.height - 8.0:
			return
		cpu.plan.clear()
	if cpu.fighter.current_attack() and _plan == null and _search == null:
		_drift_home(cpu)
		if cpu.fighter.state.frames_until_actionable() > 1:
			return
	# Mid up special, helpless or air dodging, the plan's own inputs (its
	# steering) are the best there is: follow them, replan once free.
	var air := cpu.fighter.state as AirState
	if _plan and (not air or air.helpless):
		_search = null
		if cpu.plan.is_empty():
			_drift_home(cpu)
		return
	if _search and not _search.done:
		if _search.run(SLICE_BUDGET):
			_adopt(cpu)
		elif not _plan:
			_drift_home(cpu)
		return
	var elapsed := cpu.frame - _planned_at
	if _plan and elapsed < RECHECK_EVERY and not cpu.plan.is_empty():
		return
	var start := RecoveryPlanner.Start.of(cpu.fighter)
	if _plan:
		var shifted := _plan.shifted(elapsed)
		if shifted:
			RecoveryPlanner.simulate(start, shifted, cpu.stage, true)
			if shifted.success:
				_follow(cpu, shifted)
				return
	if _fight_back(cpu, start):
		return
	var tier := cpu.params.recovery_options
	_search = RecoveryPlanner.Search.new(start, tier, cpu.stage, tier >= 6 and cpu.has_target())
	_search_frame = cpu.frame
	_search.run(FIRST_BUDGET)
	_plan = null
	if not _search.results.is_empty() or _search.done:
		_adopt(cpu)
	else:
		_drift_home(cpu)


## Still searching: drift toward the stage for now.
func _drift_home(cpu: CpuController) -> void:
	cpu.plan.clear()
	cpu.plan.label = "recover"
	cpu.plan.hold(1, Vector2(cpu.stage.home_direction(cpu.me.position, cpu.me.hurt_radius), 0.0))


## Picks among the plans the search found, shifted to now, and follows it.
func _adopt(cpu: CpuController) -> void:
	var elapsed := cpu.frame - _search_frame
	var start := RecoveryPlanner.Start.of(cpu.fighter)
	var options: Array[RecoveryPlanner.Plan] = []
	for found in _search.results:
		var shifted := found.shifted(elapsed)
		if shifted:
			shifted.frames = found.frames - elapsed
			shifted.on_ledge = found.on_ledge
			shifted.path = found.path.slice(elapsed) if found.path.size() > elapsed else PackedVector2Array()
			options.append(shifted)
	var tries := 0
	while not options.is_empty() and tries < 3:
		tries += 1
		var chosen := options[0] if cpu.params.recovery_options <= 1 else _choose(cpu, options)
		options.erase(chosen)
		RecoveryPlanner.simulate(start, chosen, cpu.stage, true)
		if chosen.success:
			if cpu.params.recovery_options > 1:
				cpu.remember(chosen.key())
			_follow(cpu, chosen)
			return
	var fallback := _desperate(start, cpu.stage)
	RecoveryPlanner.simulate(start, fallback, cpu.stage, true)
	_follow(cpu, fallback)


## Scores the successful plans: getting back sooner, the profile's preferred
## height, keeping the air dodge, varying from last time and staying away from
## the edgeguarder, with randomness that grows with the level's options.
func _choose(cpu: CpuController, options: Array[RecoveryPlanner.Plan]) -> RecoveryPlanner.Plan:
	var height_bias := cpu.profile.recovery_height if cpu.profile else 0.0
	var spread := cpu.params.recovery_options / 8.0
	var best: RecoveryPlanner.Plan
	var best_score := -INF
	for option in options:
		var score := -option.frames * 0.01
		score += (0.4 - height_bias * 0.4) if option.on_ledge else height_bias * 0.4
		if option.dodge_at > 0:
			score -= 1.5
		score -= cpu.recent_use(option.key()) * 0.8 * spread
		score += cpu.rng.randf() * spread * 1.5
		if cpu.params.recovery_options >= 6 and cpu.has_target() and not option.path.is_empty():
			score -= _exposure(cpu, option.path) * 0.6
		if score > best_score:
			best_score = score
			best = option
	return best


## How close a path comes to where the edgeguarder will be (0 far, 1 touching).
func _exposure(cpu: CpuController, path: PackedVector2Array) -> float:
	var worst := 0.0
	var reach := cpu.target_book.quick_reach(12) + cpu.me.hurt_radius + 6.0
	for i in range(0, mini(path.size(), cpu.predicted_path().size()), 3):
		var distance := path[i].distance_to(cpu.predicted_path()[i] + Vector2(0.0, cpu.target.hurt_height * 0.5))
		worst = maxf(worst, clampf(1.0 - distance / reach, 0.0, 1.0))
	return worst


## Nothing works: use what's left right away (rebuilt plans must not keep
## pushing it back): double jump now, up special once its rise has started.
func _desperate(start: RecoveryPlanner.Start, stage: StageModel) -> RecoveryPlanner.Plan:
	var plan := RecoveryPlanner.Plan.new()
	var first := start.busy + 1
	var can_jump := start.jumps_left > 0 and not start.helpless
	plan.jump_at = first if can_jump else -1
	if start.special and not start.helpless:
		plan.special_at = first + 14 if can_jump else first
	RecoveryPlanner.simulate(start, plan, stage)
	return plan


## Level 9: aerial at an edgeguarder in reach, if a way home remains after it.
func _fight_back(cpu: CpuController, start: RecoveryPlanner.Start) -> bool:
	if cpu.params.recovery_options < 8 or not cpu.has_target() or not cpu.can_act() or start.helpless:
		return false
	# Only near the ledge's height, where a way back stays short.
	if start.body.position.y < cpu.stage.main_top - 30.0 or cpu.stage.distance_offstage(start.body.position) > 40.0:
		return false
	if cpu.distance_to_target() > 35.0 or cpu.target.grounded:
		return false
	var options := cpu.hit_options(1 << MoveBook.Approach.AIR, 10, true)
	if options.is_empty():
		return false
	var option := options[0]
	for other in options:
		if cpu.option_value(other) > cpu.option_value(option):
			option = other
	# Where the aerial leaves the fighter (then drifting home), can it still get back?
	if not cpu.recoverable_after(option):
		return false
	cpu.plan.clear()
	cpu.build_attack(cpu.plan, option)
	cpu.plan.label = "fight back"
	cpu.plan.committed = true
	cpu.plan.carries_over = true
	cpu.tactic = &"fight back"
	cpu.telemetry.count_move(option.profile.slot)
	_plan = null
	return true


## Turns [param plan] into inputs, frame by frame, with the stick rule the
## planner simulated (toward the nearer edge, then the stage center).
func _follow(cpu: CpuController, plan: RecoveryPlanner.Plan) -> void:
	if CpuController.debug_log:
		print("    recover plan at %s v%s face %d: jump %d special %d dodge %d high %s drift %d -> %s in %d (%s), path end %s" % [
				cpu.me.position, cpu.me.velocity(), cpu.me.facing, plan.jump_at, plan.special_at, plan.dodge_at,
				plan.steer_high, plan.drift_after, "OK" if plan.success else "FAIL", plan.frames,
				"ledge" if plan.on_ledge else "land", plan.path[plan.path.size() - 1] if not plan.path.is_empty() else Vector2.ZERO])
	_plan = plan
	_planned_at = cpu.frame
	cpu.tactic = &"recover"
	var stage := cpu.stage
	var stats := cpu.fighter.stats
	var input := cpu.plan
	input.clear()
	input.label = "recover"
	var last_stick := Vector2(INF, INF)
	var last_buttons := -1
	var run := 0
	var position := cpu.me.position
	# Build at least through the plan's last button press, even when the
	# simulation says it ends (or fails) sooner.
	var frames := mini(maxi(maxi(plan.frames, 1), maxi(maxi(plan.special_at, plan.jump_at), plan.dodge_at) + 1), BUILD_FRAMES)
	var phase := RecoveryPlanner.Phase.AIR
	for i in range(1, frames + 1):
		if i == plan.special_at:
			phase = RecoveryPlanner.Phase.SPECIAL
		var toward := plan.stick_x(i, position, phase, stage, stats.radius)
		var stick := Vector2(toward, 0.0)
		var buttons := 0
		if i == plan.special_at:
			stick = Vector2(toward * 0.5, 0.86)
			buttons = InputPlan.SPECIAL
		elif i == plan.jump_at:
			buttons = InputPlan.JUMP
		elif i == plan.dodge_at:
			stick = plan.dodge_direction.normalized()
			buttons = InputPlan.SHIELD
		if stick == last_stick and buttons == last_buttons and buttons == 0:
			run += 1
		else:
			if run > 0:
				input.hold(run, last_stick, last_buttons)
			last_stick = stick
			last_buttons = buttons
			run = 1
		if i - 1 < plan.path.size():
			position = plan.path[i - 1]
	if run > 0:
		input.hold(run, last_stick, last_buttons)
	_path = plan.path


## The planned path, for the debug drawing.
func debug_path() -> PackedVector2Array:
	return _path
