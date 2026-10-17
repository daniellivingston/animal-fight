class_name InputActions
## Names of the actions defined in Project Settings > Input Map.
## Reference these constants instead of string literals to avoid typos.
##
## Per-player actions are named [code]p<slot>_<name>[/code] (e.g.
## [code]p1_attack[/code]); get them through [PlayerActions].

const PAUSE := &"pause"
const TOGGLE_HITBOXES := &"toggle_hitboxes"
const TOGGLE_TRAINING_INFO := &"toggle_training_info"
const RESET_MATCH := &"reset_match"

## Number of local player slots that have actions in the Input Map.
const MAX_LOCAL_PLAYERS := 2
