class_name DefendSituation
extends CpuSituation
## An opponent hitbox is coming (perceived after the reaction delay), or, at
## high anticipation, an opponent is closing in inside its reach (Ultimate's
## pre-emptive defence). Rolls [member CpuDifficulty.Params.defend_chance] once
## per threat, then picks an answer that actually covers the threat's frames:
## shield, spot dodge, roll away, jump away, hitting first, or in the air an
## air dodge, drifting or jumping away. Shield HP and dodge frame data are
## costs (rule R4); rolls never go off the stage.

var _handled := -1
var _hold_until := 0
var _next_anticipation := 0


func situation_name() -> StringName:
	return &"Defend"


func applies(cpu: CpuController) -> bool:
	if not cpu.has_target():
		return false
	if cpu.is_shielding() and cpu.frame < _hold_until:
		return true
	var free := cpu.can_act()
	if cpu.threat_in >= 0 and cpu.threat_id != _handled and free:
		return true
	return free and cpu.fighter.grounded and cpu.frame >= _next_anticipation and _approaching(cpu)


func update(cpu: CpuController) -> void:
	if cpu.threat_in >= 0 and cpu.threat_id != _handled:
		_handled = cpu.threat_id
		_react(cpu)
		return
	if cpu.is_shielding() and cpu.frame < _hold_until:
		if cpu.plan.is_empty():
			cpu.plan.shield(1)
		return
	if cpu.frame >= _next_anticipation and _approaching(cpu):
		_next_anticipation = cpu.frame + 30
		if cpu.rng.randf() < cpu.params.anticipation:
			var frames := cpu.rng.randi_range(8, 18)
			cpu.plan.clear()
			cpu.plan.shield(frames)
			cpu.plan.label = "anticipate"
			cpu.tactic = &"anticipate"
			_hold_until = cpu.frame + frames


## The target is coming toward this fighter and is about to be in range of
## its quick moves.
func _approaching(cpu: CpuController) -> bool:
	if cpu.params.anticipation <= 0.0 or not cpu.target.grounded and cpu.target.position.y > cpu.me.position.y + 30.0:
		return false
	var t := cpu.target
	var toward_me := -cpu.toward_target()
	if t.velocity().x * toward_me < 0.8 or t.is_committed():
		return false
	return cpu.gap_to_target() < cpu.target_book.quick_reach(12) + 14.0


func _react(cpu: CpuController) -> void:
	cpu.telemetry.count_reaction(cpu.world.frame - cpu.target.state_started)
	if cpu.rng.randf() >= cpu.params.defend_chance:
		return
	cpu.telemetry.defends += 1
	var t := cpu.threat_in
	var until := cpu.threat_end
	var stats := cpu.fighter.stats
	var style := cpu.personality.defense_style
	var tactics: Array[CpuSituation.Tactic] = []
	var threat := cpu.target_book.get_profile(cpu.target.move_slot)
	var away := -cpu.toward_target()

	if cpu.fighter.grounded:
		var shield_cost := SmashFormulas.shield_damage(threat.damage, threat.strongest.shield_damage) if threat else 10.0
		if cpu.fighter.shield_hp > shield_cost + 8.0:
			var unsafe := threat != null and -threat.shield_advantage > cpu.book.fastest_startup
			var hold := until + 4
			tactics.append(Tactic.new(&"shield", 2.0 - style * 0.8 + (0.8 if unsafe else 0.0)
					- shield_cost / cpu.fighter.shield_hp, func(p: InputPlan) -> void: p.shield(hold)))
		if not cpu.is_shielding():
			# Shield, then the dodge starts on the next frame.
			var spot := stats.spot_dodge_intangible
			if t >= spot.x + 1 and until <= spot.y + 1:
				tactics.append(Tactic.new(&"spot dodge", 2.2 + style * 0.8, func(p: InputPlan) -> void: p.spot_dodge()))
			var roll := stats.back_roll_intangible
			if t >= roll.x + 1 and cpu.stage.edge_distance_toward(cpu.me.position.x, away) > stats.roll_distance + 15.0:
				tactics.append(Tactic.new(&"roll away", 1.4 + style * 0.6, func(p: InputPlan) -> void: p.roll(away)))
			if _escapes_by_jumping(cpu, away):
				tactics.append(Tactic.new(&"jump away", 1.3 + style * 0.5,
						func(p: InputPlan) -> void: p.full_hop(float(away), 20)))
			for option in cpu.hit_options(1 << MoveBook.Approach.STAND | 1 << MoveBook.Approach.TURN
					| 1 << MoveBook.Approach.OUT_OF_SHIELD, t - 1):
				if option.frames < t:
					tactics.append(Tactic.new(&"beat it out", 2.4 + option.profile.damage * 0.1 + cpu.personality.aggression * 0.5,
							func(p: InputPlan) -> void: cpu.build_attack(p, option), false, option))
	else:
		var air := stats.air_dodge_intangible
		if not cpu.fighter.air_dodge_used and t >= air.x and until <= air.y:
			tactics.append(Tactic.new(&"air dodge", 2.0, func(p: InputPlan) -> void: p.air_dodge()))
		if not _air_path_hit(cpu, float(away)):
			tactics.append(Tactic.new(&"drift away", 1.8, func(p: InputPlan) -> void: p.hold(until + 2, Vector2(away, 0.0))))
		if cpu.me.jumps_left > 0:
			tactics.append(Tactic.new(&"jump away", 1.2, func(p: InputPlan) -> void: p.double_jump(float(away), until)))
		for option in cpu.hit_options(1 << MoveBook.Approach.AIR, t - 1):
			if option.frames < t:
				tactics.append(Tactic.new(&"beat it out", 2.3 + option.profile.damage * 0.1,
						func(p: InputPlan) -> void: cpu.build_attack(p, option), false, option))
	if tactics.is_empty():
		if cpu.fighter.grounded and cpu.fighter.shield_hp > 10.0:
			tactics.append(Tactic.new(&"shield", 1.0, func(p: InputPlan) -> void: p.shield(until + 4)))
		else:
			return
	var chosen: CpuSituation.Tactic
	if cpu.rng.randf() < cpu.params.defend_quality:
		chosen = cpu.pick(tactics)
	else:
		chosen = tactics[cpu.rng.randi_range(0, tactics.size() - 1)]
	if cpu.use(chosen, true):
		if chosen.name == &"shield":
			cpu.telemetry.shields += 1
			_hold_until = cpu.frame + until + 4


func _escapes_by_jumping(cpu: CpuController, away: int) -> bool:
	var path := Predict.jump_path(cpu.me.stats, cpu.me.position, cpu.me.velocity_self.x, true, float(away),
			CpuController.PATH_FRAMES, cpu.stage)
	return not _hits_path(cpu, path)


func _air_path_hit(cpu: CpuController, stick_x: float) -> bool:
	var me := cpu.me
	var path := Predict.air_path(me.stats, me.position, me.velocity_self, me.velocity_knockback, me.fast_falling,
			stick_x, CpuController.PATH_FRAMES, cpu.stage)
	return _hits_path(cpu, path)


## Whether the threatening move reaches this fighter moving along [param path].
func _hits_path(cpu: CpuController, path: PackedVector2Array) -> bool:
	var t := cpu.target
	var threat := cpu.target_book.get_profile(t.move_slot)
	if not threat:
		return false
	var shift := threat.displacement[mini(t.state_frame, threat.total)]
	var origin := t.position - Vector2(shift.x * t.facing, shift.y)
	var attacker := PackedVector2Array() if t.grounded else cpu.predicted_path()
	return threat.first_contact(origin, attacker, t.facing, -t.state_frame, path, cpu.me.hurt_height + 2.0,
			cpu.me.hurt_radius + 1.0) >= 0
