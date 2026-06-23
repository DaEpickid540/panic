extends Node3D
## Interactable — press E near this to read lore text on-screen.
## Attach to floor notes, computer terminals, or wall posters.
## The player must look at it (raycast) and be within RANGE.

const RANGE := 3.0
const INTERACTION_KEY := KEY_E

var title: String = ""
var body: String = ""
var _showing := false

signal interact_opened(title: String, body: String)
signal interact_closed


func _ready() -> void:
	add_to_group("interactable")


func _process(_delta: float) -> void:
	if not _showing:
		return
	if Input.is_key_pressed(INTERACTION_KEY) or Input.is_action_just_pressed("ui_cancel"):
		_showing = false
		interact_closed.emit()


func try_interact() -> bool:
	if _showing:
		_showing = false
		interact_closed.emit()
		return true
	_showing = true
	interact_opened.emit(title, body)
	return true


func is_in_range(player_pos: Vector3) -> bool:
	return global_position.distance_to(player_pos) < RANGE
