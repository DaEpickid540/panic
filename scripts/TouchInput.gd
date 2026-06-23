extends Node
## TouchInput (autoload singleton)
##
## Bridges mobile on-screen controls to gameplay. The VirtualJoystick writes
## `move`; a tilt/drag look region writes `look_delta` (consumed each frame).
## PlayerController merges these with keyboard/mouse so one code path serves
## desktop and mobile.

var move: Vector2 = Vector2.ZERO          # -1..1 per axis (joystick)
var look_delta: Vector2 = Vector2.ZERO    # accumulated look since last consume
var enabled: bool = false                 # true on touch devices


func _ready() -> void:
	enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


## Consume and clear the accumulated look delta (call once per frame).
func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
