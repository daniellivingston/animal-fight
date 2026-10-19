class_name HitReactionSituation
extends CpuSituation
## Getting hit. In hitlag: SDI pulses (high levels) and the DI held on the last
## hitlag frame. In hitstun: drift toward the stage, tech the landing, and
## cancel hitstun only when a follow-up is coming (rule R4). The training modes
## use the dummy's fixed DI setting instead of the level's.

var _hit: HitInfo
var _di := Vector2.ZERO
var _sdi := Vector2.ZERO
var _sdi_pulses := 0
var _tech_decided := false
var _cancel_decided := false
var _scratch := PackedVector2Array()


func situation_name() -> StringName:
	return &"HitReaction"


func applies(cpu: CpuController) -> bool:
	var f := cpu.fighter
	if f.hitlag_frames > 0 and f.get_pending_launch_direction() != Vector2.ZERO:
		return true
	if f.state is HitstunState:
		return true
	var air := f.state as AirState
	if air and air.tumbling and not air.helpless and cpu.stage and cpu.me.velocity().y < 0.0 \
			and not cpu.stage.is_offstage(cpu.me.position):
		var land := Predict.frames_to_land_fast(cpu.me, cpu.stage, 6, _scratch)
		return land > 0
	return false


func update(cpu: CpuController) -> void:
	var f := cpu.fighter
	if f.last_hit != _hit:
		_new_hit(cpu)
	if f.hitlag_frames > 0 and f.get_pending_launch_direction() != Vector2.ZERO:
		_hitlag(cpu)
	elif f.state is HitstunState:
		_hitstun(cpu)
	else:
		_tumble_landing(cpu)


func _new_hit(cpu: CpuController) -> void:
	var f := cpu.fighter
	_hit = f.last_hit
	_tech_decided = false
	_cancel_decided = false
	_sdi_pulses = 0
	var launch := f.get_pending_launch_direction()
	if cpu.mode != CpuController.Mode.FIGHT:
		_di = AiDi.fixed(cpu.dummy_di, launch, f.global_position.x)
		return
	var attacker_x := cpu.target.position.x if cpu.has_target() else cpu.me.position.x - f.facing
	var quality := cpu.params.di_quality
	_di = Vector2.ZERO
	if quality > 0.0 and cpu.stage:
		if cpu.rng.randf() < quality:
			var margin := Predict.launch_margin(f.stats, cpu.me.position,
					SmashFormulas.launch_velocity(f.get_pending_knockback(), launch.angle()),
					SmashFormulas.hitstun_frames(f.get_pending_knockback()), cpu.stage, 20)
			var in_danger := margin < 80.0
			if quality >= 0.95:
				_di = AiDi.best(f, cpu.stage) if in_danger else AiDi.away(f, attacker_x)
			elif quality >= 0.8:
				_di = AiDi.fixed(AiDi.Mode.SURVIVAL, launch, f.global_position.x) if in_danger else AiDi.away(f, attacker_x)
			else:
				_di = AiDi.fixed(AiDi.Mode.SURVIVAL, launch, f.global_position.x)
		else:
			_di = Vector2.from_angle(cpu.rng.randf() * TAU)
		if quality >= 0.85:
			_sdi_pulses = 1 + roundi((quality - 0.85) / 0.15 * 3.0)
			_sdi = AiDi.sdi_direction(f, attacker_x, cpu.stage)


func _hitlag(cpu: CpuController) -> void:
	var f := cpu.fighter
	var stick := Vector2.ZERO
	if cpu.mode != CpuController.Mode.FIGHT:
		# The dummy holds its DI for the whole hitlag, as it always did.
		stick = _di
	elif f.hitlag_frames == 1:
		stick = _di
	elif _sdi_pulses > 0 and f.hitlag_frames % InputTracker.SDI_INTERVAL == 0:
		stick = _sdi
		_sdi_pulses -= 1
	cpu.plan.clear()
	cpu.plan.hold(1, stick)


func _hitstun(cpu: CpuController) -> void:
	var f := cpu.fighter
	var state := f.state as HitstunState
	if not cpu.plan.is_empty() and cpu.plan.committed:
		return
	var stage := cpu.stage
	var stick_x := 0.0
	if cpu.mode == CpuController.Mode.FIGHT and cpu.params.di_quality >= 0.35 and stage \
			and (stage.is_offstage(cpu.me.position) or stage.blast_margin(cpu.me.position) < 60.0):
		stick_x = stage.home_direction(cpu.me.position, cpu.me.hurt_radius)

	if state.tumble and not _tech_decided and stage and cpu.me.velocity().y < 1.0:
		var land := Predict.frames_to_land_fast(cpu.me, stage, 24, _scratch)
		if land > 0 and land <= SmashFormulas.TECH_WINDOW + 4:
			_tech_decided = true
			if cpu.rng.randf() < cpu.params.tech_chance and not _press_would_air_dodge(f, state, land):
				var press_in := clampi(cpu.jitter(land - 5), 0, land + 30)
				cpu.plan.clear()
				cpu.plan.tech(press_in, _tech_direction(cpu))
				cpu.plan.label = "tech"
				cpu.plan.committed = true
				cpu.telemetry.techs += 1
				return

	# Hitstun cancels only against a perceived follow-up (Ultimate CPUs spend them on reflex).
	if not _cancel_decided and cpu.mode == CpuController.Mode.FIGHT and cpu.threat_in >= 0 and cpu.threat_in <= 12:
		var speed := f.velocity_knockback.length()
		if state.frame >= SmashFormulas.HITSTUN_AIR_DODGE_CANCEL and speed < SmashFormulas.HITSTUN_AIR_DODGE_MAX_SPEED \
				and not f.air_dodge_used and cpu.rng.randf() < cpu.params.defend_quality:
			_cancel_decided = true
			cpu.plan.clear()
			cpu.plan.air_dodge(Vector2(-cpu.toward_target(), 0.3).normalized())
			cpu.plan.committed = true
			return
	cpu.plan.clear()
	cpu.plan.hold(1, Vector2(stick_x, 0.0))


## Tumbling into the ground after hitstun: shield would air dodge, not tech,
## so the choice is a neutral air dodge (landing lag instead of a knockdown) or nothing.
func _tumble_landing(cpu: CpuController) -> void:
	if _tech_decided:
		return
	_tech_decided = true
	if cpu.mode == CpuController.Mode.FIGHT and not cpu.fighter.air_dodge_used \
			and cpu.rng.randf() < cpu.params.tech_chance * 0.7:
		cpu.plan.clear()
		cpu.plan.air_dodge()
		cpu.plan.committed = true


## Whether a shield press [param land] - 5 frames from now would air dodge out
## of hitstun instead of teching.
static func _press_would_air_dodge(f: Fighter, state: HitstunState, land: int) -> bool:
	var press_frame := state.frame + maxi(land - 5, 0)
	return press_frame >= SmashFormulas.HITSTUN_AIR_DODGE_CANCEL and not f.air_dodge_used \
			and f.velocity_knockback.length() < SmashFormulas.HITSTUN_AIR_DODGE_MAX_SPEED + 0.5


## Tech in place, toward or away from the opponent, evenly at full
## [member CpuDifficulty.Params.tech_mixup], never rolling off the stage.
static func _tech_direction(cpu: CpuController) -> float:
	var mixup := cpu.params.tech_mixup
	var roll := cpu.rng.randf()
	var direction := 0
	if roll < mixup / 3.0:
		direction = cpu.toward_target() if cpu.has_target() else 1
	elif roll < mixup * 2.0 / 3.0:
		direction = -cpu.toward_target() if cpu.has_target() else -1
	if direction != 0 and cpu.stage.edge_distance_toward(cpu.me.position.x, direction) < KnockdownState.TECH_ROLL_DISTANCE + 12.0:
		direction = 0
	return float(direction)
