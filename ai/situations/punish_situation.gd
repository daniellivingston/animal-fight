class_name PunishSituation
extends CpuSituation
## The opponent is stuck (endlag, landing lag, a missed tech, a getup, shield
## break, helpless landing) for longer than this fighter needs to reach it and
## hit. Picks the move with the best reward that lands before the opponent can
## act and after its intangibility ends: a KO move if it kills now, a charged
## smash if the window allows. Rolls [member CpuDifficulty.Params.punish_chance]
## once per window.

var _window := -1
var _go := false


func situation_name() -> StringName:
	return &"Punish"


func applies(cpu: CpuController) -> bool:
	if not cpu.has_target() or not cpu.can_act() or cpu.threat_in >= 0:
		return false
	var t := cpu.target
	if t.activity == FighterSnapshot.Activity.HITSTUN or t.actionable_in < 4:
		return false
	if t.state_started == _window and not _go:
		return false
	return t.position.distance_to(cpu.me.position) < 90.0


func update(cpu: CpuController) -> void:
	var t := cpu.target
	if t.state_started != _window:
		_window = t.state_started
		_go = cpu.rng.randf() < cpu.params.punish_chance
		if _go:
			cpu.telemetry.punish_attempts += 1
	if not _go or not cpu.can_replan():
		return
	var window := t.actionable_in
	# While closing in on a long window, looking every other frame is enough.
	if window > 12 and cpu.plan.label == "close in" and cpu.frame % 2 == 1:
		return
	var tactics: Array[CpuSituation.Tactic] = []
	for option in cpu.hit_options(cpu.approaches_now(), window + 1):
		if option.frames <= t.intangible_left:
			continue
		var charge := 0
		if option.profile.is_smash and option.profile.chargeable and cpu.params.smash_charge > 0.0 and cpu.params.move_pool >= 4:
			charge = mini(floori((window - option.frames) * cpu.params.smash_charge), SmashFormulas.SMASH_CHARGE_MAX_FRAMES)
			if charge < 6:
				charge = 0
		var value := cpu.option_value(option, 8.0) + charge * 0.04
		tactics.append(Tactic.new(StringName("punish " + option.profile.slot), value,
				func(p: InputPlan) -> void: cpu.build_attack(p, option, charge), false, option))
	if tactics.is_empty():
		if cpu.plan.label == "close in" and not cpu.plan.is_empty():
			return
		# Too far for now: close in while the window lasts.
		if window > 18 and cpu.fighter.grounded and not cpu.is_shielding() and cpu.gap_to_target() > 8.0:
			var direction := cpu.toward_target()
			if cpu.stage.edge_distance_toward(cpu.me.position.x, direction) > 30.0:
				cpu.plan.clear()
				cpu.plan.dash(direction, mini(window / 2, 10))
				cpu.plan.label = "close in"
				cpu.tactic = &"close in"
		return
	cpu.use(cpu.pick(tactics), true)
