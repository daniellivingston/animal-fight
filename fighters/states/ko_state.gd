class_name KOState
extends FighterState
## Knocked out past a blast zone: hidden until respawn.

const RESPAWN_DELAY := 60


func state_name() -> StringName:
	return &"KO"


func enter() -> void:
	fighter.velocity_self = Vector2.ZERO
	fighter.velocity_knockback = Vector2.ZERO
	fighter.set_body_enabled(false)


func update() -> void:
	if frame > RESPAWN_DELAY:
		fighter.respawn()


func controls_position() -> bool:
	return true
