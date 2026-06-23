extends Control
## UIManager  (the CanvasLayer's root Control in Main.tscn)
##
## Shows exactly one phase screen at a time, driven by GameManager.phase_changed,
## with a 500 ms cross-fade. Each phase screen is a child Control named to match
## the Phase enum.

const FADE := 0.5

@onready var _screens := {
	GameManager.Phase.LOBBY: $LobbyUI,
	GameManager.Phase.COUNTDOWN: $CountdownUI,
	GameManager.Phase.HUNTING: $HuntingUI,
	GameManager.Phase.END: $EndUI,
}


func _ready() -> void:
	GameManager.phase_changed.connect(_on_phase_changed)
	for phase in _screens:
		var s: Control = _screens[phase]
		s.visible = (phase == GameManager.current_phase)
		s.modulate.a = 1.0 if s.visible else 0.0


func _on_phase_changed(new_phase: int, old_phase: int) -> void:
	# Outside of active hunting the mouse must always be free for menus.
	if new_phase != GameManager.Phase.HUNTING:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _screens.has(old_phase):
		_fade_out(_screens[old_phase])
	if _screens.has(new_phase):
		_fade_in(_screens[new_phase])


func _fade_in(s: Control) -> void:
	s.visible = true
	create_tween().tween_property(s, "modulate:a", 1.0, FADE)


func _fade_out(s: Control) -> void:
	var t := create_tween()
	t.tween_property(s, "modulate:a", 0.0, FADE)
	t.tween_callback(func(): s.visible = false)
