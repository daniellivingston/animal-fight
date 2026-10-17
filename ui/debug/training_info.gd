class_name TrainingInfo
extends CanvasLayer
## Training overlay (F2): each fighter's state and frame, velocities and the
## numbers behind the last hit it took.

var _fighters: Array[Fighter] = []

@onready var _label: Label = %Text


func setup(fighters: Array[Fighter]) -> void:
	_fighters = fighters


func _process(_delta: float) -> void:
	visible = DebugSettings.show_training_info
	if not visible:
		return
	var lines: PackedStringArray = []
	for fighter in _fighters:
		if not is_instance_valid(fighter):
			continue
		lines.append("P%d %s — %s f%d%s" % [fighter.player_slot, fighter.data.display_name,
				fighter.state.state_name(), fighter.state.frame,
				"  [hitlag %d]" % fighter.hitlag_frames if fighter.hitlag_frames > 0 else ""])
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
	_label.text = "\n".join(lines)
