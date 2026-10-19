class_name GroundedDownSituation
extends CpuSituation
## Knocked down after a missed tech: get up in place, roll toward or away, or
## lie a while first, mixed by level (Ultimate CPUs always get up after the
## same time). Never rolls off the stage; habits are the opponent's, not ours.

var _decided := false


func situation_name() -> StringName:
	return &"GroundedDown"


func takes_over() -> bool:
	return true


func applies(cpu: CpuController) -> bool:
	return cpu.fighter.state is KnockdownState


func enter(_cpu: CpuController) -> void:
	_decided = false


func update(cpu: CpuController) -> void:
	if _decided:
		return
	_decided = true
	var f := cpu.fighter
	var mixup := cpu.params.ledge_mixup
	var patience := cpu.personality.patience if cpu.personality else 0.0
	var at := KnockdownState.MIN_LYING_FRAMES + 6
	if cpu.rng.randf() < mixup:
		at = cpu.rng.randi_range(KnockdownState.MIN_LYING_FRAMES,
				KnockdownState.MIN_LYING_FRAMES + roundi(20.0 + 25.0 * maxf(patience, 0.0)))
	var wait := maxi(at - f.state.frame, 0)
	var x := cpu.me.position.x
	var toward := cpu.toward_target() if cpu.has_target() else cpu.toward_stage()
	var room := KnockdownState.GETUP_ROLL_DISTANCE + 10.0
	var tactics: Array[CpuSituation.Tactic] = []
	tactics.append(Tactic.new(&"getup", 1.0 + (1.0 - mixup) * 1.5,
			func(p: InputPlan) -> void:
				p.wait(wait)
				p.hold(1, Vector2(0.0, 1.0))
				p.hold(1)))
	for direction: int in [toward, -toward]:
		if cpu.stage.edge_distance_toward(x, direction) < room:
			continue
		var near := cpu.has_target() and cpu.gap_to_target() < 25.0
		var utility := 0.6 * mixup + (0.6 if near and direction == -toward else 0.0)
		tactics.append(Tactic.new(&"getup roll toward" if direction == toward else &"getup roll away", utility,
				func(p: InputPlan) -> void:
					p.wait(wait)
					p.hold(1, Vector2(direction, 0.0))
					p.hold(1)))
	cpu.use(cpu.pick(tactics), true)
