class_name EdgeguardSituation
extends CpuSituation
## The opponent is offstage, or on the ledge. From the stage: hit it as it
## comes back, cover its ledge getup (timing the hit for when the getup's
## intangibility ends, and favouring the option it uses most when adapting),
## or steal the ledge so it can't grab it. Offstage (high levels): intercept
## with an aerial, only if a way back remains from where the aerial ends
## (rule R3), and only one CPU at a time.

const _GROUND := 1 << MoveBook.Approach.STAND | 1 << MoveBook.Approach.TURN | 1 << MoveBook.Approach.DASH

var _next_dive := 0
var _next_move := 0


func situation_name() -> StringName:
	return &"Edgeguard"


func applies(cpu: CpuController) -> bool:
	if _appetite(cpu) < 0.1 or not cpu.has_target() or not cpu.fighter.grounded or not cpu.can_act():
		return false
	if cpu.stage.is_offstage(cpu.me.position):
		return false
	var t := cpu.target
	if t.activity == FighterSnapshot.Activity.LEDGE or t.activity == FighterSnapshot.Activity.LEDGE_ACTION:
		return true
	return cpu.stage.is_offstage(t.position)


func update(cpu: CpuController) -> void:
	if not cpu.can_replan():
		return
	var t := cpu.target
	var stage := cpu.stage
	var ledge_index := stage.ledge_toward(t.position)
	var ledge := stage.ledge_points[ledge_index]
	var side := stage.ledge_sides[ledge_index]
	var appetite := _appetite(cpu)

	if t.activity == FighterSnapshot.Activity.LEDGE_ACTION and appetite >= 0.25:
		if _cover_getup(cpu, ledge, side):
			return
	var tactics: Array[CpuSituation.Tactic] = []
	var near := cpu.distance_to_target() < cpu.book.quick_reach(20) + 45.0
	for option in cpu.hit_options(_GROUND, 20) if near else []:
		tactics.append(Tactic.new(StringName("edge " + option.profile.slot), cpu.option_value(option) + 1.0,
				func(p: InputPlan) -> void: cpu.build_attack(p, option), true, option))
	if not tactics.is_empty():
		cpu.use(cpu.pick(tactics), true)
		cpu.telemetry.edgeguards += 1
		return
	if appetite >= 0.7 and _steal_ledge(cpu, ledge, side):
		return
	if appetite >= 0.35 and cpu.frame >= _next_dive and _dive(cpu, appetite):
		return
	if cpu.frame < _next_move and not cpu.plan.is_empty():
		return
	_next_move = cpu.frame + cpu.params.decision_interval
	_wait_near_ledge(cpu, ledge, side, appetite)


func _appetite(cpu: CpuController) -> float:
	var bias := cpu.personality.edgeguard_appetite * 0.15 if cpu.personality else 0.0
	return cpu.params.edgeguard_appetite + bias if cpu.params.edgeguard_appetite > 0.0 else 0.0


## The opponent is climbing or rolling up: hit where it ends up, just as its
## intangibility runs out.
func _cover_getup(cpu: CpuController, ledge: Vector2, side: int) -> bool:
	var t := cpu.target
	var body := Units.to_units(0.05) + t.hurt_radius
	var end := Vector2(ledge.x - side * body, ledge.y)
	if t.state_name == &"LedgeRoll":
		end.x -= side * t.stats.roll_distance
	elif t.state_name != &"LedgeClimb":
		return false
	var path := PackedVector2Array()
	path.resize(CpuController.PATH_FRAMES + 1)
	for i in path.size():
		path[i] = end if i > t.intangible_left else Vector2(1.0e6, 1.0e6)
	var options := cpu.hit_options_against(path, _GROUND, t.actionable_in + 12)
	if options.is_empty():
		return false
	var tactics: Array[CpuSituation.Tactic] = []
	for option in options:
		tactics.append(Tactic.new(StringName("cover " + option.profile.slot), cpu.option_value(option, 8.0),
				func(p: InputPlan) -> void: cpu.build_attack(p, option), true, option))
	return cpu.use(cpu.pick(tactics), true)


## Walk off the edge and drift back to hang on the ledge before the opponent
## gets there.
func _steal_ledge(cpu: CpuController, ledge: Vector2, side: int) -> bool:
	var t := cpu.target
	if t.activity == FighterSnapshot.Activity.LEDGE or t.activity == FighterSnapshot.Activity.HITSTUN:
		return false
	if t.position.y > ledge.y - 12.0 or absf(t.position.x - ledge.x) < 12.0:
		return false
	var distance := absf(ledge.x - cpu.me.position.x)
	if distance > 30.0:
		return false
	# From a standstill or a walk: a running fighter would carry its speed off the edge.
	var state := cpu.fighter.state
	if not (state is IdleState or state is WalkState) or absf(cpu.fighter.velocity_self.x) > cpu.fighter.stats.walk_speed:
		return false
	var stats := cpu.fighter.stats
	var walk_frames := ceili(maxf(distance - 4.0, 0.0) / (stats.walk_speed * 0.6))
	cpu.plan.clear()
	cpu.plan.walk(side, walk_frames, 0.6)
	cpu.plan.hold_until(InputPlan.Until.AIRBORNE, 30, Vector2(side * 0.3, 0.0))
	cpu.plan.hold(28, Vector2(-side * 0.6, 0.0))
	cpu.plan.label = "ledge steal"
	cpu.plan.committed = true
	cpu.plan.carries_over = true
	cpu.tactic = &"ledge steal"
	return true


## Jump off after the opponent with an aerial when it can still get back.
func _dive(cpu: CpuController, appetite: float) -> bool:
	_next_dive = cpu.frame + 30
	var risk := cpu.personality.risk if cpu.personality else 0.0
	if cpu.rng.randf() >= (appetite - 0.3) * (1.0 + risk * 0.3):
		return false
	var approaches := 1 << MoveBook.Approach.SHORT_HOP | 1 << MoveBook.Approach.FULL_HOP
	var best: MoveBook.Option
	var best_value := -INF
	for option in cpu.hit_options(approaches, 40, true):
		var value := cpu.option_value(option)
		if value > best_value and cpu.recoverable_after(option):
			best_value = value
			best = option
	if not best or not cpu.world.claim_edgeguard(cpu.target_index, cpu.my_index, 90):
		return false
	cpu.plan.clear()
	cpu.build_attack(cpu.plan, best)
	cpu.plan.label = "dive"
	cpu.plan.committed = true
	cpu.plan.carries_over = true
	cpu.tactic = &"dive"
	cpu.telemetry.edgeguards += 1
	cpu.telemetry.count_move(best.profile.slot)
	return true


## Stand a little way in from the ledge the opponent is coming back to,
## facing it. When it hangs on the ledge, stand where its likely getup ends.
func _wait_near_ledge(cpu: CpuController, ledge: Vector2, side: int, appetite: float) -> void:
	var t := cpu.target
	var spot := 22.0
	if t.activity == FighterSnapshot.Activity.LEDGE and appetite >= 0.25:
		var likely := cpu.habits.likely(HabitModel.Bucket.LEDGE) if cpu.params.adaptation > 0.0 else &""
		if likely == &"LedgeRoll":
			spot = t.stats.roll_distance + 12.0
		elif likely == &"LedgeClimb":
			spot = 12.0
		else:
			spot = [12.0, 18.0, t.stats.roll_distance + 12.0][cpu.rng.randi_range(0, 2)]
	spot += cpu.spacing_noise() * 0.5
	var goal := ledge.x - side * spot
	var dx := goal - cpu.me.position.x
	cpu.plan.clear()
	cpu.plan.label = "wait at ledge"
	cpu.tactic = &"wait at ledge"
	if absf(dx) > 4.0:
		var direction := 1 if dx > 0.0 else -1
		var frames := clampi(ceili(absf(dx) / (cpu.fighter.stats.walk_speed * 0.6)), 1, cpu.params.decision_interval)
		cpu.plan.walk(direction, frames)
	elif cpu.me.facing != side:
		cpu.plan.turn(side)
		cpu.plan.wait(4)
	else:
		cpu.plan.wait(cpu.params.decision_interval)
