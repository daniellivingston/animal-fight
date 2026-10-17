class_name StageLedge
extends Marker3D
## A grabbable ledge: place the marker on the top corner of solid ground.

## Which side of the ground the ledge is on: -1 left edge, 1 right edge.
@export_enum("Left:-1", "Right:1") var side := 1

## The fighter hanging from this ledge, if any.
var occupant: Fighter


## Where a fighter with [param stats] hangs: just outside the edge, hands at the corner.
func hang_position(stats: FighterStats) -> Vector3:
	var p := global_position
	return Vector3(p.x + side * (Units.to_meters(stats.radius) + 0.02),
			p.y - Units.to_meters(stats.height) * 0.8, 0.0)
