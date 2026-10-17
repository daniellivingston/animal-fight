class_name HitboxData
extends Resource
## One hitbox of a move: a sphere active on a range of frames. Units and angle
## conventions follow Smash frame data, so values can be copied from
## ultimateframedata.com.

## When several hitboxes of one move touch the same target on the same frame,
## the lowest id wins.
@export var id := 0

@export_group("Timing")
## First active frame (frame 1 is the frame the move starts).
@export var start_frame := 1
## Last active frame, inclusive.
@export var end_frame := 1

@export_group("Shape")
## Center relative to the fighter's feet, in units. +x is the facing direction.
@export var offset := Vector2(6.0, 8.0)
@export var radius := 4.0

@export_group("Hit")
@export var damage := 5.0
## Launch angle in degrees: 0 forward, 90 up, 270 down (a meteor smash).
## 361 is the Sakurai angle (see [method SmashFormulas.sakurai_angle]).
@export_range(0, 361) var angle := 361
@export var base_knockback := 20.0
@export var knockback_growth := 100.0
## Weight-based set knockback. When above 0, knockback ignores damage and percent.
@export var set_knockback := 0.0
## Sends the target behind the attacker instead of in front (back airs).
@export var reverse := false
@export var hitlag_multiplier := 1.0
@export var sdi_multiplier := 1.0

@export_group("Shield")
## Extra shield damage on top of the hit's damage.
@export var shield_damage := 0.0
@export var shieldstun_multiplier := 1.0


func is_active(frame: int) -> bool:
	return frame >= start_frame and frame <= end_frame
