class_name HitstunState
extends FighterState
## Hit and launched. The fighter is frozen in hitlag first (handled by
## [Fighter]), then flies with knockback and can't act until hitstun ends,
## except for Ultimate's air dodge and aerial hitstun cancels.

var duration := 0
var tumble := false


func _init(p_fighter: Fighter, p_duration: int, p_tumble: bool) -> void:
	super(p_fighter)
	duration = p_duration
	tumble = p_tumble


func state_name() -> StringName:
	return &"Hitstun"


func update() -> void:
	var f := fighter
	if frame > duration:
		if f.grounded:
			f.to_neutral()
		else:
			f.change_state(AirState.new(f, tumble))
			f.state.update()
		return
	if f.grounded:
		f.apply_traction()
		return
	var launch_speed := f.velocity_knockback.length()
	if frame >= SmashFormulas.HITSTUN_AIR_DODGE_CANCEL and launch_speed < SmashFormulas.HITSTUN_AIR_DODGE_MAX_SPEED:
		if f.try_air_dodge():
			return
	if frame >= SmashFormulas.HITSTUN_AERIAL_CANCEL and launch_speed < SmashFormulas.HITSTUN_AERIAL_MAX_SPEED:
		if f.try_aerial():
			return
	f.apply_gravity()
	# Air friction doesn't apply while launched.
	f.apply_air_drift(1.0, f.velocity_knockback == Vector2.ZERO)


func on_landed() -> void:
	if tumble:
		fighter.land_from_tumble()


func on_left_ground() -> void:
	pass


func frames_until_actionable() -> int:
	return maxi(duration - frame, 0) + fighter.hitlag_frames
