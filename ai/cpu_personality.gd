class_name CpuPersonality
extends Resource
## A CPU's style, separate from its skill (amiibo-style). Each weight goes from
## -1 to 1 and biases how the CPU scores its tactics.

## Approach and attack (+) or wait and whiff-punish (-).
@export_range(-1.0, 1.0) var aggression := 0.0
## Aerials (+) or grounded moves (-).
@export_range(-1.0, 1.0) var air_preference := 0.0
## Smash attacks and offstage play (+) or safe pokes (-).
@export_range(-1.0, 1.0) var risk := 0.0
## Shield (-) or dodge and jump away (+) when defending.
@export_range(-1.0, 1.0) var defense_style := 0.0
## Going for edgeguards (+) or letting opponents back (-).
@export_range(-1.0, 1.0) var edgeguard_appetite := 0.0
## Waiting longer at the ledge, on the ground and in shield (+).
@export_range(-1.0, 1.0) var patience := 0.0


## A copy with every weight nudged by up to [param amount], so two CPUs of the
## same character don't play alike.
func varied(rng: RandomNumberGenerator, amount: float) -> CpuPersonality:
	var copy := CpuPersonality.new()
	for property: String in ["aggression", "air_preference", "risk", "defense_style", "edgeguard_appetite", "patience"]:
		copy.set(property, clampf(float(get(property)) + rng.randf_range(-amount, amount), -1.0, 1.0))
	return copy
