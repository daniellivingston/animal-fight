class_name RecoveryPlanner
extends RefCounted
## Plans how to get back from offstage (rule R3). Candidate plans (when to
## double jump, when to up special, whether to air dodge, how to drift) are
## simulated frame by frame with the fighter's own stats and moves, mirroring
## the air, up special, helpless and air dodge states and the ledge-grab rules
## of [method Fighter._try_grab_ledge]. Failing plans are dropped.
##
## The level's recovery tier decides how many candidates it sees: one fixed
## pattern at level 1, timing and height mixups and air dodges higher up.
## Each jump choice is simulated once; up special starts branch off its
## recorded frames, and only where the ledge is within the special's reach.

## Frames simulated per plan at most.
const LIMIT := 220
## Up special start times are tried every this many frames.
const SPECIAL_STEP := 5

enum Phase { AIR, SPECIAL, HELPLESS, DODGE }

static var _reach_cache: Dictionary = {}
## Frames simulated so far, for budgeting searches.
static var steps := 0


## One way to recover: frame numbers count from now (1 = this frame), -1 = never.
class Plan:
	var jump_at := -1
	var special_at := -1
	var dodge_at := -1
	var dodge_direction := Vector2.ZERO
	## Frames before drifting toward the stage (a drift mixup).
	var drift_after := 0
	## From the up special on, steer over the stage to land on top instead of
	## aiming for the ledge.
	var steer_high := false
	var success := false
	## Frames until it grabs the ledge or lands.
	var frames := 0
	var on_ledge := false
	var path := PackedVector2Array()

	func copy() -> Plan:
		var plan := Plan.new()
		plan.jump_at = jump_at
		plan.special_at = special_at
		plan.dodge_at = dodge_at
		plan.dodge_direction = dodge_direction
		plan.drift_after = drift_after
		plan.steer_high = steer_high
		return plan

	## The same plan [param frames] frames later, or null if a step already passed.
	func shifted(frames: int) -> Plan:
		var plan := copy()
		plan.jump_at = _shift(jump_at, frames)
		plan.special_at = _shift(special_at, frames)
		plan.dodge_at = _shift(dodge_at, frames)
		plan.drift_after = maxi(drift_after - frames, 0)
		if plan.jump_at == -2 or plan.special_at == -2 or plan.dodge_at == -2:
			return null
		return plan

	static func _shift(at: int, frames: int) -> int:
		if at < 0:
			return -1
		return at - frames if at - frames >= 1 else -2

	## Identifies the plan's shape for the repetition penalty.
	func key() -> StringName:
		return StringName("recover j%d s%d d%d %s" % [(jump_at + 9) / 10, (special_at + 9) / 10, signi(dodge_at),
				"high" if steer_high else "ledge"])


	## The stick the plan holds on frame [param i] at [param position], in
	## [param phase]. Used by the simulation and to build the inputs.
	func stick_x(i: int, position: Vector2, phase: int, stage: StageModel, radius: float) -> float:
		if i <= drift_after:
			return 0.0
		if steer_high and (phase == Phase.SPECIAL or phase == Phase.HELPLESS) and i >= special_at:
			return 1.0 if stage.center > position.x else -1.0
		return stage.home_direction(position, radius)


## What the fighter is like at the start of a plan.
class Start:
	var body: Predict.Body
	var facing := 1
	var jumps_left := 0
	var air_dodge_used := false
	var helpless := false
	var ledge_cooldown := 0
	var special: MoveData
	## Frames left of an attack or dodge already in progress.
	var busy := 0
	## How high the up special rises (see [method RecoveryPlanner.special_reach]).
	var special_rise := 0.0

	static func of(fighter: Fighter) -> Start:
		var start := Start.new()
		var position := Units.point_to_units(fighter.global_position)
		start.body = Predict.Body.new(fighter.stats, position, fighter.velocity_self, fighter.velocity_knockback)
		start.body.fast_falling = fighter.fast_falling
		start.facing = fighter.facing
		start.jumps_left = maxi(fighter.stats.jump_count - fighter.jumps_used, 0)
		start.air_dodge_used = fighter.air_dodge_used
		var air := fighter.state as AirState
		start.helpless = air != null and air.helpless
		start.ledge_cooldown = fighter.get_ledge_cooldown()
		start.special = fighter.moveset.up_special
		if start.special:
			start.special_rise = RecoveryPlanner.special_reach(start.special, fighter.stats).y
		if not (fighter.state is AirState):
			start.busy = fighter.state.frames_until_actionable()
			var attack := fighter.state as AttackState
			if attack and attack.move.ends_in_helpless:
				start.helpless = true
		return start


## The simulation's state between frames.
class SimState:
	var body: Predict.Body
	var phase := Phase.AIR
	var facing := 1
	var jumps := 0
	var dodge_ok := true
	var move_frame := 0
	var dodge_frame := 0
	var dodge_direction := Vector2.ZERO
	## Frames simulated so far.
	var i := 0

	func copy() -> SimState:
		var s := SimState.new()
		s.body = body.copy()
		s.phase = phase
		s.facing = facing
		s.jumps = jumps
		s.dodge_ok = dodge_ok
		s.move_frame = move_frame
		s.dodge_frame = dodge_frame
		s.dodge_direction = dodge_direction
		s.i = i
		return s


static func _initial(start: Start) -> SimState:
	var s := SimState.new()
	s.body = start.body.copy()
	s.phase = Phase.HELPLESS if start.helpless and start.busy == 0 else Phase.AIR
	s.facing = start.facing
	s.jumps = start.jumps_left
	s.dodge_ok = not start.air_dodge_used
	return s


## Simulates [param plan] from [param start] and fills its result fields.
static func simulate(start: Start, plan: Plan, stage: StageModel, record: bool = false) -> void:
	_run(_initial(start), start, plan, stage, record)


static func _run(s: SimState, start: Start, plan: Plan, stage: StageModel, record: bool = false) -> void:
	plan.success = false
	plan.on_ledge = false
	if record:
		plan.path.clear()
	while s.i < LIMIT:
		var result := _step(s, start, plan, stage)
		if record:
			plan.path.append(s.body.position)
		if result != 0:
			plan.success = result > 0
			plan.on_ledge = result == 2
			plan.frames = s.i
			return
	plan.frames = LIMIT


## Advances one frame. Returns 1 on landing on ground, 2 on grabbing a ledge,
## -1 when the plan has failed, 0 otherwise. Gravity and drift are inlined
## ([method Predict.gravity], [method Predict.drift]): this is the planner's
## inner loop.
static func _step(s: SimState, start: Start, plan: Plan, stage: StageModel) -> int:
	steps += 1
	s.i += 1
	var i := s.i
	var body := s.body
	var stats := body.stats
	var special := start.special
	var stick_x := plan.stick_x(i, body.position, s.phase if not (i == plan.special_at and s.phase == Phase.AIR) else Phase.SPECIAL,
			stage, stats.radius)
	var vx := body.velocity_self.x
	var vy := body.velocity_self.y
	# 0: no gravity or drift this frame; 1: gravity and drift; 2: helpless drift.
	var physics := 1
	if i > start.busy:
		match s.phase:
			Phase.AIR:
				if i == plan.special_at and special:
					# A fast fall carries on until the move's motion starts (AttackState).
					s.phase = Phase.SPECIAL
					s.move_frame = 1
					physics = 0
				elif i == plan.jump_at and s.jumps > 0:
					s.jumps -= 1
					body.fast_falling = false
					vx = stick_x * stats.air_speed * stats.air_jump_x
					vy = SmashFormulas.jump_velocity(stats.air_jump_height, stats.gravity)
					physics = 0
				elif i == plan.dodge_at and s.dodge_ok:
					s.phase = Phase.DODGE
					s.dodge_frame = 1
					s.dodge_ok = false
					body.fast_falling = false
					var direction := plan.dodge_direction
					s.dodge_direction = direction.normalized() if direction.length() >= 0.3 else Vector2.ZERO
					if s.dodge_direction != Vector2.ZERO:
						vx = s.dodge_direction.x * stats.air_dodge_speed
						vy = s.dodge_direction.y * stats.air_dodge_speed
					physics = 0
			Phase.SPECIAL:
				s.move_frame += 1
				var frame := s.move_frame
				if special.reverse_frame == frame and stick_x * s.facing <= -InputTracker.PRESS_THRESHOLD:
					s.facing = -s.facing
					vx = -vx
				if frame > special.total_frames:
					s.phase = Phase.HELPLESS if special.ends_in_helpless else Phase.AIR
					physics = 0
				elif special.is_in_motion(frame):
					body.fast_falling = false
					vx = special.motion_velocity.x * s.facing + stick_x * special.motion_steer
					if not special.gravity_during_motion or frame == special.motion_start:
						vy = special.motion_velocity.y
						physics = 0
					else:
						vy = maxf(vy - stats.gravity, -stats.fall_speed)
						physics = 0
			Phase.HELPLESS:
				physics = 2
			Phase.DODGE:
				s.dodge_frame += 1
				if s.dodge_frame > stats.air_dodge_frames:
					s.phase = Phase.AIR
				elif s.dodge_direction != Vector2.ZERO and s.dodge_frame <= AirDodgeState.DIRECTIONAL_HOLD_FRAMES:
					physics = 0
				elif s.dodge_direction != Vector2.ZERO and s.dodge_frame <= AirDodgeState.DIRECTIONAL_HOLD_FRAMES \
						+ AirDodgeState.DIRECTIONAL_SLOW_FRAMES:
					vx *= AirDodgeState.DIRECTIONAL_SLOWDOWN
					vy *= AirDodgeState.DIRECTIONAL_SLOWDOWN
					physics = 0
	elif i == start.busy and start.helpless:
		s.phase = Phase.HELPLESS
	if physics > 0:
		vy = -stats.fast_fall_speed() if body.fast_falling else maxf(vy - stats.gravity, -stats.fall_speed)
		var max_speed := stats.air_speed * (Fighter.HELPLESS_DRIFT if physics == 2 else 1.0)
		if absf(stick_x) < Fighter.MOVE_DEADZONE:
			vx = move_toward(vx, 0.0, stats.air_friction)
		else:
			var target := max_speed * stick_x
			if absf(vx) > absf(target) and signf(vx) == signf(stick_x):
				vx = move_toward(vx, target, stats.air_friction)
			else:
				vx = move_toward(vx, target, stats.air_acceleration(absf(stick_x)))
	body.velocity_self = Vector2(vx, vy)
	var rising := vy + body.velocity_knockback.y > 0.0
	if Predict.move(body, stage, rising) == 1:
		return 1 if stage.ground_below(body.position) > -INF else -1
	var position := body.position
	var can_grab := i > start.ledge_cooldown and i > start.busy
	match s.phase:
		Phase.SPECIAL:
			can_grab = can_grab and special.ledge_grab_frame > 0 and s.move_frame >= special.ledge_grab_frame
		Phase.DODGE:
			can_grab = can_grab and s.dodge_frame > stats.air_dodge_intangible.y
		_:
			can_grab = can_grab and not rising
	if can_grab and absf(absf(position.x - stage.center) - (stage.main_right - stage.main_left) * 0.5) < 20.0 \
			and _grabs_ledge(body, stage):
		return 2
	var zone := stage.blast_zone
	if position.x < zone.position.x or position.x > zone.end.x or position.y < zone.position.y:
		return -1
	# Out of jumps and too low for what's left to reach the ledge: give up early.
	if not rising and s.jumps == 0 and s.phase != Phase.DODGE:
		# Rise still to come: an unused up special, or one that has only just started.
		var rise := 0.0
		if special and (s.phase == Phase.AIR or s.phase == Phase.SPECIAL and s.move_frame <= special.motion_end):
			rise = start.special_rise
		if position.y < stage.main_top - stats.height - Fighter.LEDGE_GRAB_REACH - 4.0 - rise:
			return -1
	return 0


## Mirrors the geometry check of [method Fighter._try_grab_ledge].
static func _grabs_ledge(body: Predict.Body, stage: StageModel) -> bool:
	var stats := body.stats
	for i in stage.ledge_points.size():
		var point := stage.ledge_points[i]
		var outward := (body.position.x - point.x) * stage.ledge_sides[i]
		if outward < -stats.radius or outward > stats.radius + Fighter.LEDGE_GRAB_REACH:
			continue
		var above_feet := point.y - body.position.y
		if above_feet >= stats.height * 0.5 and above_feet <= stats.height + Fighter.LEDGE_GRAB_REACH:
			return true
	return false


## How far an up special carries a fighter with [param stats] from a standstill
## (x: horizontal reach steering forward, y: rise), cached.
static func special_reach(special: MoveData, stats: FighterStats) -> Vector2:
	var key := [special, stats]
	if _reach_cache.has(key):
		return _reach_cache[key]
	var body := Predict.Body.new(stats)
	var reach := Vector2.ZERO
	for frame in range(2, special.total_frames + 40):
		if frame <= special.total_frames and special.is_in_motion(frame):
			body.velocity_self = Vector2(special.motion_velocity.x + special.motion_steer, special.motion_velocity.y)
		else:
			Predict.gravity(body)
			Predict.drift(body, 1.0, Fighter.HELPLESS_DRIFT if frame > special.total_frames else 1.0)
		body.position += body.velocity_self
		reach.y = maxf(reach.y, body.position.y)
		if body.position.y >= -stats.height:
			reach.x = maxf(reach.x, body.position.x)
	_reach_cache[key] = reach
	return reach


## Whether an up special started from [param body] could reach a ledge or the stage.
static func _special_could_reach(body: Predict.Body, reach: Vector2, stage: StageModel) -> bool:
	var stats := body.stats
	var top := stage.main_top
	if body.position.y > top + 10.0:
		return false
	var rise_needed := top - stats.height - Fighter.LEDGE_GRAB_REACH - body.position.y
	if rise_needed > reach.y + 4.0:
		return false
	var edge := stage.main_left if body.position.x < stage.center_x() else stage.main_right
	var gap := absf(edge - body.position.x) - stats.radius - Fighter.LEDGE_GRAB_REACH
	return gap <= reach.x + 6.0


## An anytime search for recovery plans from one [Start]: [method run] spends
## a budget of simulated frames per call, so the search can spread over
## several polls. Plans found are relative to the search's start (shift them
## by the frames since, see [method Plan.shifted]).
##
## Low tiers stop at the first success, trying a fixed pattern first: jump
## once below the ledge, then up special as early as it reaches. Higher tiers
## also try other jump timings, a delayed drift and air dodges, and keep up to
## three up special timings per jump choice (early, middle, late: a height mixup).
class Search:
	var start: Start
	var tier := 0
	var stage: StageModel
	var record := false
	var results: Array[Plan] = []
	var done := false

	var _jobs: Array[Array] = []
	var _reach := Vector2.ZERO
	var _first_jump := -1
	var _keep := 1
	var _max_results := 1
	# Per base being branched: successes so far.
	var _found: Dictionary[Plan, int] = {}

	func _init(p_start: Start, p_tier: int, p_stage: StageModel, p_record: bool = false) -> void:
		start = p_start
		tier = p_tier
		stage = p_stage
		record = p_record
		var has_jump := start.jumps_left > 0 and not start.helpless
		var special := start.special if not start.helpless else null
		_reach = RecoveryPlanner.special_reach(special, start.body.stats) if special else Vector2.ZERO
		_first_jump = RecoveryPlanner._first_jump_frame(start, stage) if has_jump else -1
		_keep = 1 if tier <= 1 else 2
		_max_results = 1 if tier <= 1 else (3 if tier <= 4 else 6)
		_jobs.append([&"base", Vector2i(_first_jump, 0)])
		if has_jump and tier >= 2:
			_jobs.append([&"base", Vector2i(_first_jump + 12, 0)])
			_jobs.append([&"base", Vector2i(-1, 0)])
		if has_jump and tier >= 6:
			_jobs.append([&"base", Vector2i(1, 0)])
		if tier >= 5:
			_jobs.append([&"base", Vector2i(_first_jump, 10)])
		if tier >= 4 and not start.air_dodge_used and not start.helpless:
			var toward := signf(stage.center - start.body.position.x)
			for dodge_at: int in [1, 14]:
				for direction: Vector2 in [Vector2(toward, 0.0), Vector2(toward, 1.0).normalized()]:
					_jobs.append([&"dodge", dodge_at, direction])

	## Simulates up to about [param budget] frames. Returns whether the search is done.
	func run(budget: int) -> bool:
		var used := RecoveryPlanner.steps
		while not _jobs.is_empty() and RecoveryPlanner.steps - used < budget:
			var job: Array = _jobs.pop_front()
			match job[0]:
				&"base":
					_run_base(job[1])
				&"special":
					_run_special(job[1], job[2], job[3], job[4])
				&"dodge":
					var plan := Plan.new()
					plan.jump_at = _first_jump
					plan.dodge_at = job[1] if _first_jump < 0 else _first_jump + job[1]
					plan.dodge_direction = job[2]
					RecoveryPlanner.simulate(start, plan, stage, record)
					if plan.success:
						results.append(plan)
			if results.size() >= _max_results:
				_jobs.clear()
		done = _jobs.is_empty()
		return done

	## Runs a jump choice without up special, queueing up special branches from
	## its frames (right after it, before the next jump choice).
	func _run_base(choice: Vector2i) -> void:
		var base := Plan.new()
		base.jump_at = choice.x
		base.drift_after = choice.y
		var special := start.special if not start.helpless else null
		var first := base.jump_at + 8 if base.jump_at > 0 else 1
		var branches: Array[Array] = []
		var s := RecoveryPlanner._initial(start)
		var outcome := 0
		var stats := start.body.stats
		while s.i < LIMIT and outcome == 0:
			var next := s.i + 1
			if special and next >= first and (next - first) % SPECIAL_STEP == 0 and s.phase == Phase.AIR and s.i >= start.busy:
				if RecoveryPlanner._special_could_reach(s.body, _reach, stage):
					branches.append([&"special", base, next, s.copy(), false])
					# High enough to clear the top: also try landing on the stage.
					if tier >= 3 and s.body.position.y + _reach.y > stage.main_top + 4.0:
						branches.append([&"special", base, next, s.copy(), true])
				elif s.body.position.y < stage.main_top - _reach.y - stats.height * 2.0:
					# Too low for the up special from here on.
					special = null
			outcome = RecoveryPlanner._step(s, start, base, stage)
		base.success = outcome > 0
		base.on_ledge = outcome == 2
		base.frames = s.i
		if base.success:
			if record:
				RecoveryPlanner.simulate(start, base, stage, true)
			results.append(base)
		_found[base] = 0
		for i in range(branches.size() - 1, -1, -1):
			_jobs.push_front(branches[i])

	func _run_special(base: Plan, special_at: int, state: SimState, high: bool) -> void:
		if _found.get(base, 0) >= _keep or _found.get(base, 0) < 0:
			return
		var plan := base.copy()
		plan.special_at = special_at
		plan.steer_high = high
		RecoveryPlanner._run(state.copy(), start, plan, stage)
		if plan.success:
			if record:
				RecoveryPlanner.simulate(start, plan, stage, true)
			results.append(plan)
			_found[base] = _found.get(base, 0) + 1
		elif _found.get(base, 0) > 0:
			# Past the window of working up special timings.
			_found[base] = -1


## The successful plans for recovery tier [param tier] (0-8), searched to the
## end (see [RecoveryPlanner.Search]).
static func successful(start: Start, tier: int, stage: StageModel, record: bool = false) -> Array[Plan]:
	var search := Search.new(start, tier, stage, record)
	search.run(1 << 30)
	return search.results


## The first frame worth jumping on in the fixed pattern: once falling below
## the ledge's height.
static func _first_jump_frame(start: Start, stage: StageModel) -> int:
	var body := start.body.copy()
	for i in range(1, 90):
		Predict.gravity(body)
		Predict.drift(body, signf(stage.center_x() - body.position.x))
		Predict.move(body, stage, true)
		if i > start.busy and body.velocity().y <= 0.0 and body.position.y < stage.main_top - 5.0:
			return i
	return maxi(start.busy + 1, 1)


## Whether the fighter described by [param start] can still get back (the R3
## check before going offstage), with the fixed-pattern plans. Gives up as
## "no" after [param budget] simulated frames: when in doubt, don't go.
static func recoverable(start: Start, stage: StageModel, budget: int = 500) -> bool:
	var search := Search.new(start, 1, stage)
	search.run(budget)
	return not search.results.is_empty()
