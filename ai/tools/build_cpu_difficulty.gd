extends SceneTree
## Writes ai/cpu_difficulty.tres from CpuDifficulty.STARTING_VALUES. Run with:
##   Godot --headless --path . --script res://ai/tools/build_cpu_difficulty.gd
## After that, tune the curves in the inspector (or edit the table and rerun).


func _initialize() -> void:
	var difficulty := CpuDifficulty.from_table(CpuDifficulty.STARTING_VALUES)
	var error := ResourceSaver.save(difficulty, CpuDifficulty.DEFAULT_PATH)
	print("Saved %s: %s" % [CpuDifficulty.DEFAULT_PATH, error_string(error)])
	quit(0 if error == OK else 1)
