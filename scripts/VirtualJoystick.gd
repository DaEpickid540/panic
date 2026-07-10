extends Control
## VirtualJoystick
##
## On-screen thumbstick for mobile. Writes a normalised vector to
## TouchInput.move so PlayerController treats it like keyboard input. The stick
## appears only on touch devices; on desktop it hides itself.
##
## Layout: a fixed base ring with a draggable knob. Touch anywhere inside the
## base captures the stick; release re-centres it.

@export var radius := 90.0
@export var dead_zone := 0.15

@onready var _base: Control = $Base
@onready var _knob: Control = $Base/Knob

var _touch_index := -1


func _ready() -> void:
	visible = TouchInput.enabled
	_base.mouse_filter = Control.MOUSE_FILTER_PASS
	_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			# Only capture a NEW touch when idle AND it lands on the joystick base.
			# Any other finger is completely ignored so it can reach buttons freely.
			if _touch_index == -1 and _hit_test(event.position):
				_touch_index = event.index
				_move_knob(event.position)
				get_viewport().set_input_as_handled()
			# else: different finger or not on joystick — let it through untouched.
		else:
			# Release only our tracked finger; all others pass through.
			if event.index == _touch_index:
				_release()
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		# Only update knob for the finger we are tracking.
		if event.index == _touch_index:
			_move_knob(event.position)
			get_viewport().set_input_as_handled()
	# Mouse fallback so it works in the editor too.
	elif event is InputEventMouseButton:
		if event.pressed and _hit_test(event.global_position):
			_touch_index = 0
			_move_knob(event.global_position)
		elif not event.pressed and _touch_index == 0:
			_release()
	elif event is InputEventMouseMotion and _touch_index == 0:
		_move_knob(event.global_position)


func _hit_test(screen_pos: Vector2) -> bool:
	return Rect2(_base.global_position, _base.size).has_point(screen_pos)


func _move_knob(screen_pos: Vector2) -> void:
	var center := _base.global_position + _base.size * 0.5
	var offset := (screen_pos - center).limit_length(radius)
	_knob.position = _base.size * 0.5 + offset - _knob.size * 0.5
	var v := offset / radius
	TouchInput.move = v if v.length() > dead_zone else Vector2.ZERO


func _release() -> void:
	_touch_index = -1
	TouchInput.move = Vector2.ZERO
	_knob.position = _base.size * 0.5 - _knob.size * 0.5
