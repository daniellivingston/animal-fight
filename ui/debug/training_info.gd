class_name TrainingInfo
extends CanvasLayer
## Training overlay (F2): each fighter's state and frame, frames until it can
## act (frame advantage), velocities and the numbers behind the last hit it
## took. With AI debug on (F3), each CPU's level, situation, tactic, plan,
## reaction delay and seed. The match seed reproduces the CPUs' choices.

var _match: Match

@onready var _label: Label = %Text


func setup(match_node: Match) -> void:
	_match = match_node


func _process(_delta: float) -> void:
	visible = DebugSettings.show_training_info
	if not visible or not _match:
		return
	var lines: PackedStringArray = []
	lines.append("seed %d" % _match.match_seed)
	var fighters := _match.fighters
	for fighter in fighters:
		if not is_instance_valid(fighter):
			continue
		var actionable := fighter.state.frames_until_actionable()
		lines.append("P%d %s — %s f%d%s%s" % [fighter.player_slot, fighter.data.display_name,
				fighter.state.state_name(), fighter.state.frame,
				"  [hitlag %d]" % fighter.hitlag_frames if fighter.hitlag_frames > 0 else "",
				"  acts in %d" % actionable if actionable > 0 else ""])
		lines.append("  %.1f%%  self (%.2f, %.2f)  launch (%.2f, %.2f)  jumps %d/%d  shield %.1f" % [
				fighter.percent, fighter.velocity_self.x, fighter.velocity_self.y,
				fighter.velocity_knockback.x, fighter.velocity_knockback.y,
				fighter.jumps_used, fighter.stats.jump_count, fighter.shield_hp])
		var hit := fighter.last_hit
		if hit and hit.shielded:
			lines.append("  last: %s %s on shield, %.1f%%, shieldstun %d, hitlag %d" % [
					hit.attacker_name, hit.move_name, hit.damage, hit.hitstun, hit.hitlag])
		elif hit:
			var final_angle := "%.0f°" % hit.final_angle if hit.launch_speed > 0.0 else "…"
			lines.append("  last: %s %s  %.1f%% (stale ×%.3f)  KB %.1f  angle %.0f° → %s after DI%s" % [
					hit.attacker_name, hit.move_name, hit.damage, hit.stale_multiplier, hit.knockback,
					hit.angle, final_angle, "  CC" if hit.crouch_cancelled else ""])
			lines.append("        launch %.2f u/f  hitstun %d  hitlag %d  %s" % [
					hit.launch_speed, hit.hitstun, hit.hitlag, "TUMBLE" if hit.tumble else "no tumble"])
		var cpu := fighter.controller as CpuController
		if cpu and DebugSettings.show_ai_debug:
			lines.append_array(cpu.debug_lines())
	if fighters.size() == 2 and is_instance_valid(fighters[0]) and is_instance_valid(fighters[1]):
		var advantage := fighters[1].state.frames_until_actionable() - fighters[0].state.frames_until_actionable()
		if advantage != 0:
			lines.append("frame advantage: P%d +%d" % [1 if advantage > 0 else 2, absi(advantage)])
	_label.text = "\n".join(lines)
