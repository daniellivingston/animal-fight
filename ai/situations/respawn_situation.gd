class_name RespawnSituation
extends CpuSituation
## On the revival platform: wait a random time (shorter at high levels), then
## drop, drifting away from the opponent. High levels hold off while the
## opponent waits below with an attack out (Brawl).

var _drop_at := 0


func situation_name() -> StringName:
	return &"Respawn"


func takes_over() -> bool:
	return true


func applies(cpu: CpuController) -> bool:
	return cpu.fighter.state is RespawnState


func enter(cpu: CpuController) -> void:
	var patience := cpu.personality.patience if cpu.personality else 0.0
	var latest := roundi(lerpf(240.0, 70.0, cpu.skill) * (1.0 + patience * 0.3))
	_drop_at = cpu.rng.randi_range(RespawnState.MIN_FRAMES, maxi(latest, RespawnState.MIN_FRAMES + 1))


func update(cpu: CpuController) -> void:
	var f := cpu.fighter
	if not cpu.plan.is_empty() or f.state.frame < _drop_at:
		return
	var below_and_attacking := cpu.has_target() and cpu.target.activity == FighterSnapshot.Activity.ATTACK \
			and absf(cpu.target.position.x - cpu.me.position.x) < 30.0
	if below_and_attacking and cpu.skill >= 0.6 and f.state.frame < RespawnState.MAX_FRAMES - 30:
		return
	var side := -cpu.toward_target() if cpu.has_target() and cpu.skill >= 0.4 else (1 if cpu.rng.randf() < 0.5 else -1)
	cpu.plan.hold(3, Vector2(side * 0.75, 0.0))
	cpu.plan.label = "respawn drop"
	cpu.tactic = &"respawn drop"
