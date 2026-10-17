class_name SmashFormulas
## Combat constants and formulas ported from Super Smash Bros. Ultimate.
##
## Sources: ssbwiki.com (Knockback, Hitstun, Hitlag, Directional influence,
## Smash DI, Shield, Stale-move negation, Sakurai angle, Tech, Buffer).
## docs/physics.md explains each formula, and lists what isn't ported yet.

#region Knockback and launch

## Launch speed (units/frame) per unit of knockback.
const LAUNCH_SPEED_PER_KNOCKBACK := 0.03
## Launch speed lost per frame, along the launch direction.
const LAUNCH_DECAY := 0.051
## Hitstun frames per unit of knockback.
const HITSTUN_PER_KNOCKBACK := 0.4
## Knockback at or above this makes the target tumble.
const TUMBLE_THRESHOLD := 80.0
## Knockback multiplier when the target is crouching (crouch cancel).
const CROUCH_CANCEL_KNOCKBACK := 0.85
## Damage multiplier for 1-on-1 matches.
const ONE_ON_ONE_DAMAGE := 1.2
## Share of the stale/fresh damage change that knockback sees.
const STALENESS_KNOCKBACK_SHARE := 0.3

## Sakurai angle (361): grounded targets launch at 0° up to 60 knockback,
## then lerp to 38° at 88 knockback. Aerial targets always launch at 38°.
const SAKURAI_ANGLE := 361
const SAKURAI_LOW_KNOCKBACK := 60.0
const SAKURAI_HIGH_KNOCKBACK := 88.0
const SAKURAI_HIGH_ANGLE := 38.0
const SAKURAI_AIR_ANGLE := 38.0

## Largest change DI can make to the launch angle, in radians (~9.74°).
const DI_MAX_ANGLE := 0.17
## Stick tilt below this is ignored for DI and LSI.
const DI_DEADZONE := 0.2
## Launch speed influence: full up multiplies tumble launches by 1.095, full
## down by 0.92. No effect on launches between 65° and 115° (or 245° to 295°).
const LSI_UP := 1.095
const LSI_DOWN := 0.92
## Distance of one Smash DI pulse during hitlag, in units.
const SDI_DISTANCE := 2.0

#endregion

#region Hitlag and hitstun cancels

const MAX_HITLAG := 30
const HITLAG_CROUCH_CANCEL := 0.67
const HITLAG_SHIELD := 0.67
## Earliest hitstun frame an air dodge can cancel hitstun, if launch speed is low enough.
const HITSTUN_AIR_DODGE_CANCEL := 40
const HITSTUN_AIR_DODGE_MAX_SPEED := 2.5
## Earliest hitstun frame an aerial can cancel hitstun, if launch speed is low enough.
const HITSTUN_AERIAL_CANCEL := 45
const HITSTUN_AERIAL_MAX_SPEED := 2.0

#endregion

#region Stale moves and charge

## Damage removed for each occurrence of a move in the last 9 hits, newest first.
const STALE_FACTORS: Array[float] = [0.09, 0.08545, 0.07635, 0.0679, 0.05945, 0.05035, 0.04255, 0.03345, 0.025]
## Damage multiplier for a move that isn't in the stale queue.
const FRESHNESS_BONUS := 1.05
## Hits on shield count 0.85× toward staleness.
const STALE_SHIELD_WEIGHT := 0.85
const SMASH_CHARGE_MAX_FRAMES := 60
## Damage multiplier of a fully charged smash attack.
const SMASH_CHARGE_FULL := 1.4

#endregion

#region Shield

const SHIELD_MAX := 50.0
const SHIELD_DECAY := 0.15
const SHIELD_REGEN := 0.08
const SHIELD_DAMAGE_MULTIPLIER := 1.19
const SHIELD_BREAK_RESET := 37.5
## Frames the shield must be held before it can be dropped.
const SHIELD_MIN_FRAMES := 3
const SHIELD_DROP_FRAMES := 11
const SHIELD_PUSHBACK_MAX := 1.3

#endregion

#region Teching and knockdown

## Frames before landing in which a shield press techs.
const TECH_WINDOW := 11
## A tech press locks out teching for this many frames.
const TECH_LOCKOUT := 40

#endregion


## Knockback dealt by a hit. [param percent] is the target's damage after the
## hit, [param damage] the hit's damage as knockback sees it, [param ratio] the
## product of modifiers such as rage. With [param set_knockback] > 0 the hit
## uses weight-based set knockback: damage and percent are ignored.
static func knockback(percent: float, damage: float, weight: float, growth: float,
		base: float, set_knockback: float = 0.0, ratio: float = 1.0) -> float:
	var p := percent
	var d := damage
	if set_knockback > 0.0:
		p = 10.0
		d = set_knockback
	var scaled := (p / 10.0 + p * d / 20.0) * (200.0 / (weight + 100.0)) * 1.4 + 18.0
	return (scaled * (growth / 100.0) + base) * ratio


## Rage multiplier from the attacker's percent: 1.0 at 35% and below, up to 1.1 at 150%.
static func rage(attacker_percent: float) -> float:
	return 1.0 + clampf((attacker_percent - 35.0) / 115.0, 0.0, 1.0) * 0.1


static func hitstun_frames(knockback_value: float) -> int:
	return maxi(floori(knockback_value * HITSTUN_PER_KNOCKBACK) - 1, 0)


static func is_tumble(knockback_value: float) -> bool:
	return knockback_value >= TUMBLE_THRESHOLD


## Hitlag (freeze frames) for both fighters. [param damage] excludes the 1v1
## multiplier.
static func hitlag_frames(damage: float, multiplier: float = 1.0, crouch_cancel: bool = false,
		shield: bool = false) -> int:
	if shield:
		multiplier = maxf(multiplier, 1.0) * HITLAG_SHIELD
	var frames := floori((damage * 0.65 + 6.0) * multiplier)
	if crouch_cancel:
		frames = floori(frames * HITLAG_CROUCH_CANCEL)
	return clampi(frames, 0, MAX_HITLAG)


## Resolves the Sakurai angle (361) to degrees.
static func sakurai_angle(knockback_value: float, target_grounded: bool) -> float:
	if not target_grounded:
		return SAKURAI_AIR_ANGLE
	var t := inverse_lerp(SAKURAI_LOW_KNOCKBACK, SAKURAI_HIGH_KNOCKBACK, knockback_value)
	return lerpf(0.0, SAKURAI_HIGH_ANGLE, clampf(t, 0.0, 1.0))


## Applies directional influence: the stick component perpendicular to the
## launch rotates it by up to [constant DI_MAX_ANGLE]. Angles in radians.
static func apply_di(angle: float, stick: Vector2) -> float:
	if stick.length() < DI_DEADZONE:
		return angle
	var launch := Vector2.from_angle(angle)
	var perpendicular := launch.cross(stick.limit_length(1.0))
	return angle + perpendicular * DI_MAX_ANGLE


## Launch speed influence multiplier for a tumble launch at [param angle] (radians).
static func launch_speed_influence(angle: float, stick: Vector2) -> float:
	if stick.length() < DI_DEADZONE:
		return 1.0
	var degrees := fposmod(rad_to_deg(angle), 360.0)
	if (degrees > 65.0 and degrees < 115.0) or (degrees > 245.0 and degrees < 295.0):
		return 1.0
	var y := clampf(stick.y, -1.0, 1.0)
	return lerpf(1.0, LSI_UP, y) if y > 0.0 else lerpf(1.0, LSI_DOWN, -y)


## Initial launch velocity (units/frame) for [param knockback_value] at [param angle] (radians).
static func launch_velocity(knockback_value: float, angle: float) -> Vector2:
	return Vector2.from_angle(angle) * knockback_value * LAUNCH_SPEED_PER_KNOCKBACK


## One frame of launch speed decay.
static func decay_launch(velocity: Vector2) -> Vector2:
	var speed := velocity.length()
	if speed <= LAUNCH_DECAY:
		return Vector2.ZERO
	return velocity * ((speed - LAUNCH_DECAY) / speed)


static func shieldstun_frames(damage: float, multiplier: float = 1.0) -> int:
	return floori(damage * 0.8 * multiplier + 2.0)


## Shield damage taken from a hit (raw shield HP).
static func shield_damage(damage: float, extra: float) -> float:
	return (damage + extra) * SHIELD_DAMAGE_MULTIPLIER


## Shield bubble scale for the given shield HP (0.15 to 1.0).
static func shield_scale(hp: float) -> float:
	return clampf(hp / SHIELD_MAX, 0.0, 1.0) * 0.85 + 0.15


## Defender pushback speed (units/frame) after blocking a hit.
static func shield_pushback(shieldstun: int) -> float:
	return minf((shieldstun + 1) * 0.09, SHIELD_PUSHBACK_MAX)


## Initial upward speed that reaches [param height] units under [param gravity],
## for the integration fighters use (move by v, then v -= gravity).
static func jump_velocity(height: float, gravity: float) -> float:
	return (-gravity + sqrt(gravity * gravity + 8.0 * gravity * height)) / 2.0
