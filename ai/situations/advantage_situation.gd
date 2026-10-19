class_name AdvantageSituation
extends CpuSituation
## This fighter just hit the opponent, which is in hitstun. Follows up when a
## move lands before the hitstun ends (a true combo, checked against the
## predicted launch at the current percent, so it stops when the follow-up no
## longer works), up to the level's combo depth. Otherwise it waits under the
## landing spot to juggle.

var _hits := 0
var _last_hit_state := -1


func situation_name() -> StringName:
	return &"Advantage"


func applies(cpu: CpuController) -> bool:
	if cpu.params.combo_depth <= 0 or not cpu.has_target():
		return false
	var t := cpu.target
	if t.activity != FighterSnapshot.Activity.HITSTUN or t.last_attacker != cpu.my_index:
		_hits = 0
		return false
	if t.state_started != _last_hit_state:
		_last_hit_state = t.state_started
		_hits += 1
	return _hits <= cpu.params.combo_depth and cpu.can_act()


func update(cpu: CpuController) -> void:
	if not cpu.can_replan() or cpu.stage.is_offstage(cpu.target.position):
		return
	var t := cpu.target
	var window := t.actionable_in + 1
	var tactics: Array[CpuSituation.Tactic] = []
	for option in cpu.hit_options(cpu.approaches_now(), window):
		if option.frames <= t.intangible_left:
			continue
		tactics.append(Tactic.new(StringName("combo " + option.profile.slot), cpu.option_value(option),
				func(p: InputPlan) -> void: cpu.build_attack(p, option), true, option))
	if not tactics.is_empty():
		cpu.use(cpu.pick(tactics), true)
		return
	if cpu.plan.label == "juggle" and not cpu.plan.is_empty():
		return
	# No true follow-up: get under where it lands.
	if not cpu.fighter.grounded:
		return
	var land_x := cpu.predicted_path()[cpu.predicted_path().size() - 1].x
	var dx := land_x - cpu.me.position.x
	cpu.plan.clear()
	cpu.plan.label = "juggle"
	cpu.tactic = &"juggle"
	if absf(dx) > 8.0:
		var direction := 1 if dx > 0.0 else -1
		if cpu.stage.edge_distance_toward(cpu.me.position.x, direction) > 20.0:
			cpu.plan.walk(direction, 6, 0.75)
			return
	cpu.plan.wait(4)
