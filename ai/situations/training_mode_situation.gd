class_name TrainingModeSituation
extends CpuSituation
## Smash's training CPU modes. STAND, SHIELD and JUMP behave exactly like the
## old training dummy; WALK walks back and forth, turning at edges; EVADE runs
## away from the opponent. Recovering, teching and getting up are handled by
## the situations before this one.

## Frames between jumps in JUMP mode.
const JUMP_INTERVAL := 90

var _walk_direction := 1


func situation_name() -> StringName:
	return &"TrainingMode"


func applies(_cpu: CpuController) -> bool:
	return true


func update(cpu: CpuController) -> void:
	var f := cpu.fighter
	cpu.plan.clear()
	match cpu.mode:
		CpuController.Mode.SHIELD:
			cpu.plan.hold(1, Vector2.ZERO, InputPlan.SHIELD if f.grounded else 0)
		CpuController.Mode.JUMP:
			cpu.plan.hold(1, Vector2.ZERO, InputPlan.JUMP if cpu.frame % JUMP_INTERVAL < 2 else 0)
		CpuController.Mode.WALK:
			if cpu.stage and f.grounded and cpu.stage.edge_distance_toward(cpu.me.position.x, _walk_direction) < 15.0:
				_walk_direction = -_walk_direction
			cpu.plan.walk(_walk_direction, 1)
		CpuController.Mode.EVADE:
			_evade(cpu)
		_:
			cpu.plan.hold(1)


func _evade(cpu: CpuController) -> void:
	if not cpu.has_target() or not cpu.fighter.grounded:
		cpu.plan.hold(1)
		return
	var away := -cpu.toward_target()
	# Cornered: run back past the opponent instead of off the stage.
	if cpu.stage.edge_distance_toward(cpu.me.position.x, away) < 30.0:
		away = -away
	if cpu.gap_to_target() > 60.0 and cpu.stage.edge_distance(cpu.me.position.x) > 30.0:
		cpu.plan.hold(1)
		return
	var stick := Vector2(away, 0.0)
	if not (cpu.fighter.state is DashState or cpu.fighter.state is RunState) and cpu.fighter.input.current.stick.x * away > 0.3:
		stick = Vector2.ZERO
	cpu.plan.hold(1, stick)
