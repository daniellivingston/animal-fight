class_name HitInfo
extends RefCounted
## The numbers behind one hit, for the training overlay and future effects.

var attacker_name := ""
var move_name := ""
var damage := 0.0
var knockback := 0.0
## Launch angle before DI, in degrees.
var angle := 0.0
## Launch angle after DI, in degrees (set when the launch happens).
var final_angle := 0.0
## Initial launch speed in units/frame (set when the launch happens).
var launch_speed := 0.0
var hitstun := 0
var hitlag := 0
var tumble := false
var shielded := false
var crouch_cancelled := false
var stale_multiplier := 1.0
