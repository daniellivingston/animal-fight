extends SceneTree
## Writes the CPU profiles in ai/profiles/ (personality and move preferences per
## archetype). Run with:
##   Godot --headless --path . --script res://ai/tools/build_cpu_profiles.gd
## Roster characters point at them through FighterData.cpu_profile.

const PROFILES := {
	# All-rounder (Cat, Husky): likes aerials, a little aggressive.
	"all_rounder": {"aggression": 0.2, "air_preference": 0.5, "risk": 0.0, "defense_style": 0.2,
			"edgeguard_appetite": 0.2, "patience": 0.0, "recovery_height": 0.0,
			"move_weights": {&"forward_air": 0.3, &"up_tilt": 0.2}},
	# Grounded heavy hitter (Bear): smash-happy, shields, covers ledges.
	"bear": {"aggression": 0.1, "air_preference": -0.4, "risk": 0.5, "defense_style": -0.3,
			"edgeguard_appetite": 0.0, "patience": 0.2, "recovery_height": 0.3,
			"move_weights": {&"forward_smash": 0.5, &"down_smash": 0.3},
			"kill_moves": [&"forward_smash", &"up_smash"], "never_offstage": [&"down_air"]},
	# Speedsters (Fox, Shiba Inu): rush in, dodge instead of shielding, impatient.
	"speedster": {"aggression": 0.6, "air_preference": 0.3, "risk": -0.2, "defense_style": 0.5,
			"edgeguard_appetite": 0.4, "patience": -0.5, "recovery_height": -0.3,
			"move_weights": {&"dash_attack": 0.3, &"neutral_air": 0.2}},
	# Rushdown (Wolf, White Horse): pressure and risky kills.
	"rushdown": {"aggression": 0.7, "air_preference": 0.0, "risk": 0.3, "defense_style": 0.1,
			"edgeguard_appetite": 0.5, "patience": -0.3, "recovery_height": 0.0,
			"move_weights": {&"forward_tilt": 0.2, &"forward_smash": 0.2}},
	# Floaty (Deer, Alpaca): fights in the air, waits, recovers high.
	"floaty": {"aggression": -0.2, "air_preference": 0.7, "risk": -0.1, "defense_style": 0.3,
			"edgeguard_appetite": 0.3, "patience": 0.4, "recovery_height": 0.5,
			"move_weights": {&"back_air": 0.3, &"up_air": 0.2}},
	# Heavyweights (Donkey, Stag, Horse, Cow, Bull): patient, shield, big punishes.
	"heavy": {"aggression": -0.1, "air_preference": -0.3, "risk": 0.4, "defense_style": -0.4,
			"edgeguard_appetite": -0.2, "patience": 0.3, "recovery_height": 0.2,
			"move_weights": {&"forward_smash": 0.3, &"up_smash": 0.2},
			"kill_moves": [&"forward_smash", &"up_smash"], "never_offstage": [&"down_air"]},
}


func _initialize() -> void:
	var failed := false
	for key: String in PROFILES:
		var spec: Dictionary = PROFILES[key]
		var personality := CpuPersonality.new()
		for property: String in ["aggression", "air_preference", "risk", "defense_style", "edgeguard_appetite", "patience"]:
			personality.set(property, spec[property])
		var profile := CpuProfile.new()
		profile.personality = personality
		profile.recovery_height = spec["recovery_height"]
		var weights: Dictionary[StringName, float] = {}
		for slot: StringName in spec.get("move_weights", {}):
			weights[slot] = spec["move_weights"][slot]
		profile.move_weights = weights
		var kill_moves: Array[StringName] = []
		kill_moves.assign(spec.get("kill_moves", []))
		profile.kill_moves = kill_moves
		var never: Array[StringName] = []
		never.assign(spec.get("never_offstage", []))
		profile.never_offstage = never
		var path := "res://ai/profiles/%s.tres" % key
		var error := ResourceSaver.save(profile, path)
		print("%s: %s" % [path, error_string(error)])
		failed = failed or error != OK
	quit(1 if failed else 0)
