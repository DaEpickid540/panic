extends Control
## Transparent right-half touch region for FPS camera look-drag.
## Works for both the HUNTER and the RUNNER (both are first-person now).
## Added programmatically by HuntingUI when TouchInput.enabled is true.

const SENSITIVITY := 1.8

var _touch_idx := -1


func _ready() -> void:
	anchor_left   = 0.5
	anchor_top    = 0.0
	anchor_right  = 1.0
	anchor_bottom = 1.0
	offset_left   = 0.0
	offset_top    = 0.0
	offset_right  = 0.0
	offset_bottom = 0.0
	mouse_filter  = MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	# Both hunter and runner are FPS; ghost uses iso (doesn't need this).
	var role := GameManager.get_local_role()
	if role == GameManager.Role.GHOST:
		return

	if event is InputEventScreenTouch:
		if event.pressed and _touch_idx == -1:
			var vp_size := get_viewport_rect().size
			if event.position.x >= vp_size.x * 0.5:
				# Guard: skip touches that land on an interactive GUI control
				# (e.g. mobile action buttons). When emulate_mouse_from_touch is on,
				# Button may only accept_event() on the synthetic mouse event, leaving
				# the raw ScreenTouch unhandled even though a button was hit.
				if _hits_gui_control(event.position):
					return
				_touch_idx = event.index
				get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch_idx:
			_touch_idx = -1
			get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag and event.index == _touch_idx:
		TouchInput.look_delta += event.relative * SENSITIVITY
		get_viewport().set_input_as_handled()


## Returns true if screen_pos is inside the mobile action-button bar so we
## know the touch belongs to a button and must not be claimed as a look drag.
## gui_get_hovered_control() tracks the mouse cursor position, not touch
## position, so it gives wrong results when a second finger hits a button.
## A direct rect test against the known button container is reliable.
func _hits_gui_control(screen_pos: Vector2) -> bool:
	var btns: Control = get_parent().get_node_or_null("MobileButtons")
	if btns != null and btns.visible:
		if btns.get_global_rect().has_point(screen_pos):
			return true
	return false
