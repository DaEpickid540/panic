extends Node
## EndCondition  (world node)
##
## Watches for the two ways a match ends and surfaces the final stats:
##   1. All hunted converted to ghost  (GameManager fires this on capture).
##   2. Round timer expires.
##
## GameManager owns the actual transition + stat collection; this node is the
## explicit, testable hook the EndUI listens to, and exposes check_now() so the
## end condition can be evaluated on demand (e.g. after a disconnect).

signal match_over(results: Dictionary)

var last_results: Dictionary = {}


func _ready() -> void:
	GameManager.game_ended.connect(_on_game_ended)


func _on_game_ended(results: Dictionary) -> void:
	last_results = results
	match_over.emit(results)


## Re-evaluate the end condition immediately (host only acts on it).
func check_now() -> bool:
	var hunted_left := 0
	for id in GameManager.roles:
		if GameManager.roles[id] == GameManager.Role.HUNTED:
			hunted_left += 1
	if hunted_left == 0 and GameManager.current_phase == GameManager.Phase.HUNTING:
		GameManager.end_game("all_captured")
		return true
	return false
