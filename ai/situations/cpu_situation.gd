class_name CpuSituation
extends RefCounted
## One of a CPU's routines (Smash's AIMain routines): recovering, defending,
## neutral and so on. [CpuController] picks the first situation that
## [method applies] each frame, in priority order, and calls its
## [method update], which may replace the CPU's [InputPlan].
##
## Situations read the world only through the controller's perception
## ([member CpuController.me], [member CpuController.target], ...) and act only
## through the plan.


## One thing the CPU could do, with its score. Built by situations and picked
## by [method CpuController.pick].
class Tactic:
	var name: StringName
	var utility := 0.0
	## Fills the plan: func(plan: InputPlan) -> void.
	var build: Callable
	## Offensive tactics roll [member CpuDifficulty.Params.follow_through] first.
	var offensive := false
	var option: MoveBook.Option

	func _init(p_name: StringName, p_utility: float, p_build: Callable, p_offensive: bool = false,
			p_option: MoveBook.Option = null) -> void:
		name = p_name
		utility = p_utility
		build = p_build
		offensive = p_offensive
		option = p_option


func situation_name() -> StringName:
	return &"Situation"


func applies(_cpu: CpuController) -> bool:
	return false


func enter(_cpu: CpuController) -> void:
	pass


func exit(_cpu: CpuController) -> void:
	pass


func update(_cpu: CpuController) -> void:
	pass


## Whether entering this situation drops plans made by other situations
## (unless they carry over). True for situations about the fighter's own state.
func takes_over() -> bool:
	return false
