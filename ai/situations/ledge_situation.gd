class_name LedgeSituation
extends CpuSituation
## Hanging from a ledge. Waits a random time (high levels act inside the ledge
## intangibility), then climbs, rolls, jumps or drops and jumps back with an
## aerial, picked from where the opponent is. While an opponent is offstage
## and needs this ledge, an edgeguarding CPU keeps holding it (ledge hog).

var _decided := false
var _hogging := false


func situation_name() -> StringName:
	return &"Ledge"


func takes_over() -> bool:
	return true


func applies(cpu: CpuController) -> bool:
	return cpu.fighter.state is LedgeHangState


func enter(_cpu: CpuController) -> void:
	_decided = false
	_hogging = false


func update(cpu: CpuController) -> void:
	var f := cpu.fighter
	if not cpu.plan.is_empty():
		return
	var inward := -f.ledge.side if f.ledge else cpu.toward_stage()
	if cpu.mode == CpuController.Mode.FIGHT and cpu.has_target() and _should_hog(cpu):
		_hogging = true
		cpu.plan.wait(5)
		cpu.plan.label = "ledge hog"
		cpu.tactic = &"ledge hog"
		return
	if _decided:
		return
	_decided = true
	var mixup := cpu.params.ledge_mixup
	var patience := cpu.personality.patience if cpu.personality else 0.0
	var wait := 0
	if _hogging:
		wait = 0
	elif mixup < 0.3:
		# Low levels: slow and predictable.
		wait = cpu.rng.randi_range(20, 50)
	else:
		var latest := Fighter.LEDGE_INTANGIBILITY - LedgeHangState.GRAB_LAG - 4
		wait = cpu.rng.randi_range(0, roundi(latest * (0.5 + patience * 0.3)))
		if cpu.rng.randf() < mixup * 0.25:
			wait += cpu.rng.randi_range(20, 60)
	wait = maxi(wait - f.state.frame, 0)

	var tactics: Array[CpuSituation.Tactic] = []
	var far := true
	var close_and_ready := false
	var committed := false
	if cpu.has_target():
		var distance := absf(cpu.target.position.x - cpu.me.position.x)
		far = distance > 45.0
		close_and_ready = distance < 30.0 and cpu.target.grounded and not cpu.target.is_committed()
		committed = cpu.target.is_committed() or not cpu.target.grounded
	var predictable := (1.0 - mixup) * 2.0
	tactics.append(Tactic.new(&"ledge climb", 1.0 + predictable + (1.0 if far else 0.0) - (1.0 if close_and_ready else 0.0),
			func(p: InputPlan) -> void:
				p.wait(wait)
				p.ledge_climb(inward)))
	tactics.append(Tactic.new(&"ledge roll", 0.4 + (1.2 if close_and_ready else 0.0),
			func(p: InputPlan) -> void:
				p.wait(wait)
				p.ledge_roll()))
	tactics.append(Tactic.new(&"ledge jump", 0.5 + (1.0 if committed else 0.0),
			func(p: InputPlan) -> void:
				p.wait(wait)
				p.ledge_jump(inward)))
	if mixup >= 0.7 and f.stats.jump_count >= 2:
		tactics.append(Tactic.new(&"ledge drop aerial", 0.3 + mixup * 0.6 + (0.6 if close_and_ready else 0.0),
				func(p: InputPlan) -> void:
					p.wait(wait)
					p.ledge_drop(-inward)
					p.wait(2)
					p.double_jump(inward, 8)
					p.aerial(Moveset.NEUTRAL_AIR, f.facing, inward, 12)))
	if cpu.use(cpu.pick(tactics), true):
		cpu.plan.label = String(cpu.tactic)
		# The drop and jump back ends offstage on purpose.
		cpu.plan.carries_over = cpu.tactic == &"ledge drop aerial"


## Hold the ledge while the opponent is offstage below it and needs it.
func _should_hog(cpu: CpuController) -> bool:
	var f := cpu.fighter
	if cpu.params.edgeguard_appetite < 0.7 or not f.ledge or f.state.frame > LedgeHangState.MAX_HANG_FRAMES - 30:
		return false
	var t := cpu.target
	if not cpu.stage.is_offstage(t.position) or t.activity == FighterSnapshot.Activity.HITSTUN and t.position.y > cpu.stage.main_top:
		return false
	var same_side := signf(t.position.x - cpu.stage.center_x()) == f.ledge.side
	return same_side and t.position.y < cpu.stage.main_top + 10.0
