extends Control
## GlitchOverlay — screen-tear, scan-line, and chromatic-noise effects.
##
## Triggered by HuntingUI when:
##   • The hunter is very close (redness > 0.75)
##   • A jumpscare fires
##   • Randomly every 40-100 s for ambient dread
##
## Each "glitch burst" lasts 0.1-0.3 s and consists of:
##   • 4-9 horizontal scan-line strips at random y positions
##   • One full-width "tear" band that appears shifted
##   • A brief colour tint flash (red or green tinge)

var _active_strips: Array[ColorRect] = []
var _tint: ColorRect
var _tear: ColorRect

var _burst_timer := 0.0   # > 0 while a burst is active
var _ambient_cd  := 0.0   # counts down to next random ambient glitch

signal burst_ended   # emitted when a glitch burst finishes


func _ready() -> void:
	layout_mode = 1
	anchors_preset = 15
	anchor_right   = 1.0
	anchor_bottom  = 1.0
	mouse_filter   = MOUSE_FILTER_IGNORE
	visible        = true   # always in the tree; strips are added/removed

	# Persistent full-screen tint (normally invisible).
	_tint = ColorRect.new()
	_tint.layout_mode  = 1
	_tint.anchors_preset = 15
	_tint.anchor_right = 1.0
	_tint.anchor_bottom = 1.0
	_tint.mouse_filter = MOUSE_FILTER_IGNORE
	_tint.modulate.a   = 0.0
	add_child(_tint)

	# The "tear" strip — a horizontal band that slides.
	_tear = ColorRect.new()
	_tear.layout_mode = 0
	_tear.mouse_filter = MOUSE_FILTER_IGNORE
	_tear.visible = false
	add_child(_tear)

	_ambient_cd = randf_range(40.0, 100.0)


func _process(delta: float) -> void:
	if _burst_timer > 0.0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_clear_strips()
	else:
		# Ambient random glitch.
		_ambient_cd -= delta
		if _ambient_cd <= 0.0:
			_ambient_cd = randf_range(40.0, 100.0)
			trigger_burst("ambient")


## Fire a glitch burst. kind: "ambient", "danger", "scare"
func trigger_burst(kind: String = "ambient") -> void:
	_clear_strips()
	var sz := get_viewport_rect().size
	var strip_count := 5 if kind == "ambient" else 9
	var dur := 0.12 if kind == "ambient" else 0.22

	_burst_timer = dur

	# Scan-line strips.
	for i in strip_count:
		var strip := ColorRect.new()
		strip.layout_mode = 0
		strip.mouse_filter = MOUSE_FILTER_IGNORE
		var h := randf_range(2.0, 14.0)
		var y := randf_range(0.0, sz.y - h)
		var shift := randf_range(-24.0, 24.0)   # horizontal tear displacement
		strip.size = Vector2(sz.x, h)
		strip.position = Vector2(shift, y)
		# Alternate between dark red and bright green-teal for a CRT feel.
		if randi() % 2 == 0:
			strip.color = Color(randf_range(0.5, 0.9), 0.0, 0.0, randf_range(0.25, 0.55))
		else:
			strip.color = Color(0.0, randf_range(0.3, 0.6), randf_range(0.4, 0.7), randf_range(0.15, 0.35))
		add_child(strip)
		_active_strips.append(strip)

	# Tear band.
	_tear.visible = true
	var tear_h := randf_range(18.0, 50.0)
	var tear_y := randf_range(sz.y * 0.1, sz.y * 0.85)
	_tear.size     = Vector2(sz.x, tear_h)
	_tear.position = Vector2(randf_range(-8.0, 8.0), tear_y)
	_tear.color    = Color(1.0, 1.0, 1.0, randf_range(0.06, 0.18))

	# Tint flash.
	_tint.color = Color(randf_range(0.3, 0.7), 0.0, 0.0, 0.0)
	var t := create_tween()
	t.tween_property(_tint, "modulate:a", randf_range(0.25, 0.5), 0.04)
	t.tween_property(_tint, "modulate:a", 0.0, dur * 0.7)


func _clear_strips() -> void:
	for s in _active_strips:
		if is_instance_valid(s):
			s.queue_free()
	_active_strips.clear()
	_tear.visible = false
	burst_ended.emit()
