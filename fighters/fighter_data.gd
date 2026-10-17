class_name FighterData
extends Resource
## Everything that makes one character: name, look, stats and moves. Add a
## character by making a new FighterData (see fighters/roster/).

@export var display_name := ""
## One line describing how the character plays, shown in menus.
@export_multiline var description := ""
@export var color := Color.WHITE
## Visual scene instanced under the fighter's Model node. Its root must be a [FighterModel].
@export var model_scene: PackedScene
@export var stats: FighterStats
@export var moveset: Moveset
