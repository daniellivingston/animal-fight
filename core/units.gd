class_name Units
## Conversion between Smash units and Godot meters.
##
## Fighter stats and move data use the units and timing of Super Smash Bros.
## Ultimate: distances in units, speeds in units/frame, accelerations in
## units/frame². That lets you copy values straight from community data
## (ultimateframedata.com, ssbwiki.com). The simulation advances one Smash
## frame per physics tick, and the project runs physics at a fixed 60 Hz.

## Smash units per Godot meter. A 15-unit-tall fighter is 1.5 m.
const PER_METER := 10.0
## Simulation frames per second. Must match physics/common/physics_ticks_per_second.
const FRAMES_PER_SECOND := 60


static func to_meters(units: float) -> float:
	return units / PER_METER


static func to_units(meters: float) -> float:
	return meters * PER_METER


## Converts a velocity in units/frame (x right, y up) to a Godot velocity in m/s.
static func velocity_to_godot(velocity: Vector2) -> Vector3:
	return Vector3(velocity.x, velocity.y, 0.0) * (FRAMES_PER_SECOND / PER_METER)


## Projects a world position onto the fight plane, in units.
static func point_to_units(point: Vector3) -> Vector2:
	return Vector2(point.x, point.y) * PER_METER
