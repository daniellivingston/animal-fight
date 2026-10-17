class_name MoveData
extends Resource
## An attack: its duration, hitboxes, landing lag, charge window and any motion
## it applies to the fighter. Frame numbers follow ultimateframedata.com
## conventions (frame 1 is the frame the move starts).

@export var display_name := ""
## Frames the move lasts. The fighter can act again on frame [code]total_frames + 1[/code].
@export var total_frames := 30
@export var hitboxes: Array[HitboxData] = []

@export_group("Aerial")
## Landing lag when landing during the move (aerials, specials).
@export var landing_lag := 0
## Landing before this frame uses a normal landing instead of the landing lag.
@export var autocancel_before := 0
## Landing on or after this frame uses a normal landing (0 = never).
@export var autocancel_after := 0

@export_group("Charge")
## Frame where holding the attack starts a smash charge (0 = can't charge).
@export var charge_frame := 0

@export_group("Motion")
## First and last frame of the move's own motion (0 = none).
@export var motion_start := 0
@export var motion_end := 0
## Velocity during the motion frames in units/frame. +x is the facing direction.
@export var motion_velocity := Vector2.ZERO
## Extra horizontal speed from the stick during the motion (steerable recoveries).
@export var motion_steer := 0.0
## Whether gravity still applies during the motion frames.
@export var gravity_during_motion := false

@export_group("Recovery")
## The fighter enters helpless (special fall) when the move ends in the air.
@export var ends_in_helpless := false
## Frame from which the move can grab a ledge (0 = never).
@export var ledge_grab_frame := 0
## Frame on which the stick can turn the fighter around (B-reverse); 0 = never.
@export var reverse_frame := 0


## The hitboxes active on [param frame], lowest id first.
func active_hitboxes(frame: int) -> Array[HitboxData]:
	var result: Array[HitboxData] = []
	for hitbox in hitboxes:
		if hitbox.is_active(frame):
			result.append(hitbox)
	result.sort_custom(func(a: HitboxData, b: HitboxData) -> bool: return a.id < b.id)
	return result


func has_motion() -> bool:
	return motion_start > 0 and motion_end >= motion_start


func is_in_motion(frame: int) -> bool:
	return has_motion() and frame >= motion_start and frame <= motion_end


## Whether landing on [param frame] uses a normal landing instead of landing lag.
func autocancels(frame: int) -> bool:
	return frame < autocancel_before or (autocancel_after > 0 and frame >= autocancel_after)
