class_name NeutralSituation
extends CpuSituation
## Neither fighter has the advantage. Every decision interval the CPU looks for
## a move that would land from here (the hit query), and otherwise works
## toward a preferred range: just outside the opponent's quick reach and
## inside its own, with spacing error. Approaches by walking, dashing or
## jumping to platforms; waits, retreats, baits with shield or dash dances.
## Never runs off the stage: every move is limited by the room to the edge.

var _next_decision := 0


func situation_name() -> StringName:
	return &"Neutral"


func applies(_cpu: CpuController) -> bool:
	return true


func update(cpu: CpuController) -> void:
	if not cpu.can_replan() or not cpu.can_act():
		return
	if not cpu.has_target():
		if cpu.plan.is_empty():
			cpu.plan.wait(10)
		return
	if cpu.frame < _next_decision:
		return
	_next_decision = cpu.frame + cpu.params.decision_interval + cpu.rng.randi_range(0, 2)
	_think(cpu)


func _think(cpu: CpuController) -> void:
	var me := cpu.me
	var t := cpu.target
	var stage := cpu.stage
	var stats := cpu.fighter.stats
	var p := cpu.params
	var aggression := cpu.personality.aggression
	var patience := cpu.personality.patience
	var tactics: Array[CpuSituation.Tactic] = []
	var interval := p.decision_interval

	if t.intangible_left < 8:
		for option in cpu.hit_options(cpu.approaches_now(), maxi(interval, 12) + 6, false):
			var utility := cpu.option_value(option) + 1.0 + aggression * 0.5
			# Low levels lean on dash attacks, like Melee CPUs.
			if option.approach == MoveBook.Approach.DASH and p.move_pool <= 2:
				utility += 1.0
			if not _lands_on_stage(cpu, option):
				continue
			tactics.append(Tactic.new(StringName("attack " + option.profile.slot), utility,
					func(plan: InputPlan) -> void: cpu.build_attack(plan, option), true, option))

	var direction := cpu.toward_target()
	var gap := cpu.gap_to_target()
	var their_reach := cpu.target_book.quick_reach(12)
	var my_reach := cpu.book.quick_reach(12)
	var ideal := their_reach + 4.0
	if my_reach > their_reach:
		ideal = (my_reach + their_reach) * 0.5 + 2.0
	ideal += cpu.spacing_noise() - aggression * 6.0
	ideal = maxf(ideal, 2.0)
	var room_toward := stage.edge_distance_toward(me.position.x, direction)
	var room_away := stage.edge_distance_toward(me.position.x, -direction)
	var on_main := absf(me.position.y - stage.main_top) < 2.0

	if cpu.fighter.grounded:
		var above := t.position.y - me.position.y
		if above > 18.0 and t.grounded and absf(t.position.x - me.position.x) < 50.0:
			tactics.append(Tactic.new(&"jump up", 1.0 + aggression * 0.5,
					func(plan: InputPlan) -> void: plan.full_hop(direction * 0.6, 20), true))
		if not on_main and above < -15.0 and (cpu.fighter.state is IdleState or cpu.fighter.state is WalkState):
			tactics.append(Tactic.new(&"drop down", 1.2 + aggression * 0.3, func(plan: InputPlan) -> void: plan.drop_through()))
		if gap > ideal + 6.0:
			var run_frames := _run_frames(stats, room_toward, interval + 4)
			if gap > ideal + 25.0 and run_frames > 0:
				tactics.append(Tactic.new(&"run in", 1.1 + aggression * 1.2 + (gap - ideal) / 40.0,
						func(plan: InputPlan) -> void: plan.dash(direction, run_frames), true))
			var walk_frames := _walk_frames(stats, room_toward, interval + 2, gap - ideal)
			if walk_frames > 0:
				tactics.append(Tactic.new(&"walk in", 1.0 + aggression * 0.8 + (gap - ideal) / 50.0,
						func(plan: InputPlan) -> void: plan.walk(direction, walk_frames), true))
		elif gap < ideal - 6.0 and not t.is_committed():
			var back_frames := _walk_frames(stats, room_away, interval + 2, ideal - gap)
			if back_frames > 0:
				tactics.append(Tactic.new(&"back off", 0.6 + (ideal - gap) / 20.0 - aggression,
						func(plan: InputPlan) -> void: plan.walk(-direction, back_frames)))
			if p.move_pool >= 2:
				var frames := cpu.rng.randi_range(6, 14)
				tactics.append(Tactic.new(&"shield bait", 0.4 + patience * 0.3,
						func(plan: InputPlan) -> void: plan.shield(frames)))
		if p.move_pool >= 7 and room_toward > 40.0 and room_away > 40.0 and gap < ideal + 30.0:
			var times := cpu.rng.randi_range(2, 3)
			tactics.append(Tactic.new(&"dash dance", 0.7, func(plan: InputPlan) -> void:
				plan.dash_dance(direction, times, stats.dash_frames / 2 + 1)))
		var facing_away := me.facing != direction
		tactics.append(Tactic.new(&"wait", 0.5 + patience * 0.4 - aggression * 0.4, func(plan: InputPlan) -> void:
			if facing_away:
				plan.turn(direction)
			plan.wait(interval)))
	else:
		# Airborne and free: drift toward the opponent, or back over the stage.
		var drift := float(direction)
		if stage.edge_distance(me.position.x) < 10.0:
			drift = float(cpu.toward_stage())
		tactics.append(Tactic.new(&"drift", 1.0, func(plan: InputPlan) -> void: plan.hold(interval, Vector2(drift, 0.0))))
		if p.move_pool >= 3 and me.velocity().y <= 0.0 and not me.fast_falling and gap > 20.0 \
				and stage.ground_below(me.position) > -INF:
			tactics.append(Tactic.new(&"fast fall", 0.8 + aggression * 0.5, func(plan: InputPlan) -> void: plan.fast_fall(drift)))
	cpu.use(cpu.pick(tactics))


## Whether a jumping approach comes down on the stage (no accidental trips offstage).
func _lands_on_stage(cpu: CpuController, option: MoveBook.Option) -> bool:
	if option.approach != MoveBook.Approach.SHORT_HOP and option.approach != MoveBook.Approach.FULL_HOP:
		return true
	var path := cpu.path_after(option)
	return not cpu.stage.is_offstage(path[mini(option.delay + option.profile.total + 10, path.size() - 1)])


## Frames it can hold a dash and run toward an edge [param room] units away
## and still stop on the stage (dash, run, then the skid), up to [param limit].
static func _run_frames(stats: FighterStats, room: float, limit: int) -> int:
	var dash := stats.initial_dash_speed * stats.dash_frames
	var skid := stats.run_speed * stats.run_speed / (2.0 * stats.traction)
	var budget := room - 12.0 - dash - skid
	if budget < 0.0:
		return 0
	return mini(stats.dash_frames + floori(budget / stats.run_speed), limit)


## Frames of walking toward an edge [param room] units away, covering at most
## [param wanted] units, up to [param limit].
static func _walk_frames(stats: FighterStats, room: float, limit: int, wanted: float) -> int:
	var speed := stats.walk_speed * InputPlan.WALK_TILT
	var frames := floori(minf(room - 10.0, wanted + 4.0) / speed)
	return clampi(frames, 0, limit)
