class_name FighterStats
extends Resource
## A fighter's attributes, in Super Smash Bros. Ultimate units so values can be
## compared with (and copied from) ultimateframedata.com/stats.
##
## Distances are units (10 units = 1 m), speeds units/frame, accelerations
## units/frame², durations frames at 60 fps. docs/fighter-stats.md explains
## every stat and gives the range across Ultimate's cast.

@export_group("Body")
## How hard the fighter is to launch. Ultimate: 62 (Pichu) to 135 (Bowser), Mario 98.
@export var weight := 98.0
## Hurtbox and collision capsule height, in units.
@export var height := 15.0
## Hurtbox and collision capsule radius, in units.
@export var radius := 4.0
## Hurtbox height while crouching, as a fraction of [member height].
@export_range(0.3, 1.0) var crouch_height_ratio := 0.6

@export_group("Ground movement")
## Top walking speed at full tilt. Ultimate: 0.62 to 1.575.
@export var walk_speed := 1.155
## Speed gained per frame while walking toward the stick's target speed.
@export var walk_acceleration := 0.15
## Speed on the first frame of a dash. Ultimate: 1.45 to 2.45.
@export var initial_dash_speed := 1.936
## Length of the initial dash before it becomes a run. Ultimate: 7 to 16.
@export var dash_frames := 10
## Top running speed. Ultimate: 1.18 to 3.85.
@export var run_speed := 1.76
## Speed gained per frame while running, from the dash speed up to the run speed.
@export var run_acceleration := 0.1
## Frames to turn around out of a run.
@export var run_turn_frames := 14
## Deceleration per frame on the ground. Ultimate: 0.076 to 0.138.
@export var traction := 0.102

@export_group("Jumps")
## Frames between pressing jump and leaving the ground. 3 for everyone in Ultimate.
@export var jumpsquat_frames := 3
## Ultimate: 16.5 to 50.51.
@export var full_hop_height := 36.33
## Ultimate: 10 to 22.11.
@export var short_hop_height := 17.54
## Height of each mid-air jump. Ultimate: 19.79 to 57.35.
@export var air_jump_height := 36.33
## Total jumps including the ground jump (2 = one double jump).
@export_range(1, 6) var jump_count := 2
## Share of ground speed kept when jumping.
@export var jump_momentum := 0.85
## Horizontal speed the stick adds when jumping from the ground.
@export var jump_initial_x := 0.35
## Horizontal speed cap when leaving the ground.
@export var jump_max_x := 1.5
## Horizontal speed of a mid-air jump at full tilt, as a fraction of [member air_speed].
@export var air_jump_x := 1.0

@export_group("Air movement")
## Top horizontal air speed. Ultimate: 0.735 to 1.344.
@export var air_speed := 1.208
## Air acceleration while any horizontal input is held.
@export var air_acceleration_base := 0.01
## Additional air acceleration scaled by stick tilt. Base + additional = max (Ultimate: 0.03 to 0.13).
@export var air_acceleration_additional := 0.07
## Horizontal deceleration in the air without input. Ultimate: 0.00375 to 0.05.
@export var air_friction := 0.015
## Downward acceleration. Ultimate: 0.053 to 0.23.
@export var gravity := 0.087
## Terminal falling speed. Ultimate: 0.98 to 2.1.
@export var fall_speed := 1.5
## Fast fall speed as a multiple of [member fall_speed] (1.6 for everyone in Ultimate).
@export var fast_fall_multiplier := 1.6

@export_group("Landing")
## Landing frames after a normal fall.
@export var hard_landing_frames := 4
## Landing frames after a light landing (low falling speed).
@export var soft_landing_frames := 2

@export_group("Shield and dodges")
## Shield bubble radius at full shield, in units.
@export var shield_radius := 10.0
## First and last intangible frame of the spot dodge.
@export var spot_dodge_intangible := Vector2i(3, 17)
@export var spot_dodge_frames := 25
@export var forward_roll_intangible := Vector2i(4, 15)
@export var forward_roll_frames := 29
@export var back_roll_intangible := Vector2i(5, 16)
@export var back_roll_frames := 34
## Distance covered by a roll, in units.
@export var roll_distance := 28.0
@export var air_dodge_intangible := Vector2i(3, 29)
@export var air_dodge_frames := 52
## Initial speed of a directional air dodge.
@export var air_dodge_speed := 2.6

@export_group("Ledge")
@export var ledge_getup_intangible := 33
@export var ledge_getup_frames := 34
@export var ledge_roll_intangible := 25
@export var ledge_roll_frames := 45
@export var ledge_jump_intangible := 12
@export var ledge_jump_frames := 14


func fast_fall_speed() -> float:
	return fall_speed * fast_fall_multiplier


## Air acceleration for a horizontal stick tilt of [param tilt] (0 to 1).
func air_acceleration(tilt: float) -> float:
	return air_acceleration_base + air_acceleration_additional * clampf(tilt, 0.0, 1.0)
