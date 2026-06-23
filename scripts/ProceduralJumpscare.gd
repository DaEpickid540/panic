extends Control
## ProceduralJumpscare — draws a horror face directly to the screen.
##
## Phases:
##   BLACK  (0.07s) — sudden black-out primes the contrast
##   FLASH  (0.06s) — blinding white flash (the real jump scare beat)
##   FACE   (0.40s) — horror face zooms toward the camera
##   LINGER (0.20s) — face fades out slowly (leaves dread)
##
## Call trigger() to start the sequence. The node stays invisible otherwise.

enum Phase { IDLE, BLACK, FLASH, FACE, LINGER }

const PHASE_DUR := {
	Phase.BLACK:  0.07,
	Phase.FLASH:  0.06,
	Phase.FACE:   0.40,
	Phase.LINGER: 0.22,
}

var _phase: Phase = Phase.IDLE
var _t: float = 0.0

# Per-scare random offsets so every jumpscare looks slightly different.
var _eye_l_dir  := Vector2.ZERO
var _eye_r_dir  := Vector2.ZERO
var _crack_seed := 0
var _mouth_skew := 0.0


func _ready() -> void:
	layout_mode  = 1
	anchors_preset = 15   # full rect
	anchor_right  = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false


## Start a jumpscare from outside. phase_t is unused — just call this.
func trigger() -> void:
	_phase = Phase.BLACK
	_t     = 0.0
	_eye_l_dir  = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.8)).normalized()
	_eye_r_dir  = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.8)).normalized()
	_crack_seed = randi()
	_mouth_skew = randf_range(-0.06, 0.06)
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if _phase == Phase.IDLE:
		return
	_t += delta
	var dur: float = PHASE_DUR.get(_phase, 0.5)
	if _t >= dur:
		_t -= dur
		match _phase:
			Phase.BLACK:  _phase = Phase.FLASH
			Phase.FLASH:  _phase = Phase.FACE
			Phase.FACE:   _phase = Phase.LINGER
			Phase.LINGER:
				_phase = Phase.IDLE
				visible = false
				return
	queue_redraw()


func _draw() -> void:
	var sz := get_rect().size
	var cx := sz.x * 0.5
	var cy := sz.y * 0.55   # face sits slightly below centre (more imposing)

	match _phase:
		Phase.BLACK:
			draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0, 0, 0, 1.0))

		Phase.FLASH:
			var a := 1.0 - (_t / PHASE_DUR[Phase.FLASH]) * 0.3
			draw_rect(Rect2(0, 0, sz.x, sz.y), Color(1, 0.98, 0.92, a))

		Phase.FACE:
			_draw_face(sz, cx, cy, _t / PHASE_DUR[Phase.FACE], 1.0)

		Phase.LINGER:
			var fade := 1.0 - _t / PHASE_DUR[Phase.LINGER]
			_draw_face(sz, cx, cy, 1.0, fade)


func _draw_face(sz: Vector2, cx: float, cy: float, progress: float, alpha: float) -> void:
	# Face zooms in from far to filling the screen.
	var zoom := lerpf(0.45, 1.0, progress)
	var fw   := sz.x * 0.78 * zoom
	var fh   := sz.y * 0.92 * zoom
	# Slight wobble on the face each frame for living, breathing effect.
	var wx := sin(progress * 42.0) * 6.0 * progress
	var wy := cos(progress * 31.0) * 4.0 * progress
	var fc := Vector2(cx + wx, cy + wy)

	# ── Background ──
	draw_rect(Rect2(0, 0, sz.x, sz.y), Color(0, 0, 0, alpha))

	# ── Face oval (dead pale with slight green-gray rot tinge) ──
	_fill_ellipse(fc, fw * 0.5, fh * 0.5, Color(0.14, 0.09, 0.09, alpha))

	# ── Eyes ──
	var ex  := fw * 0.24
	var ey  := fh * 0.15
	var er  := fw * 0.14   # eye radius
	var lcx := fc + Vector2(-ex, -ey)
	var rcx := fc + Vector2( ex, -ey)

	# Eye whites (blood-red sclera)
	_fill_ellipse(lcx, er, er * 0.75, Color(0.62, 0.04, 0.04, alpha))
	_fill_ellipse(rcx, er, er * 0.75, Color(0.62, 0.04, 0.04, alpha))

	# Pupils (large, off-centre — looking past you)
	var pr := er * 0.52
	_fill_ellipse(lcx + _eye_l_dir * er * 0.32, pr, pr, Color(0, 0, 0, alpha))
	_fill_ellipse(rcx + _eye_r_dir * er * 0.32, pr, pr, Color(0, 0, 0, alpha))

	# Glint in each eye (tiny white dot — makes them look wet/alive)
	var gi := er * 0.16
	draw_circle(lcx + Vector2(-er * 0.15, -er * 0.18), gi, Color(1, 1, 1, alpha * 0.9))
	draw_circle(rcx + Vector2(-er * 0.15, -er * 0.18), gi, Color(1, 1, 1, alpha * 0.9))

	# ── Veins / cracks radiating from eyes ──
	var rng := RandomNumberGenerator.new()
	rng.seed = _crack_seed
	for eye_pos: Vector2 in [lcx, rcx]:
		for i in 7:
			var ang := rng.randf_range(0, TAU)
			var length := rng.randf_range(er * 1.1, er * 2.6)
			var p1: Vector2 = eye_pos
			var p2: Vector2 = eye_pos + Vector2(cos(ang), sin(ang)) * length
			draw_line(p1, p2, Color(0.55, 0.0, 0.0, alpha * rng.randf_range(0.3, 0.6)), 1.2)

	# ── Mouth ──
	var mw := fw * 0.52 + _mouth_skew * fw   # slightly asymmetric
	var mh := fh * 0.14
	var my := fc.y + fh * 0.22
	# Mouth cavity (black)
	_fill_ellipse(Vector2(fc.x, my), mw * 0.5, mh * 0.5, Color(0, 0, 0, alpha))

	# Teeth (jagged white triangles along top and bottom of mouth)
	var tooth_count := 9
	var tw := mw / tooth_count
	for i in tooth_count:
		var tx := fc.x - mw * 0.5 + tw * i
		# Upper teeth point downward
		var pts_top := PackedVector2Array([
			Vector2(tx,       my - mh * 0.42),
			Vector2(tx + tw * 0.5, my + mh * 0.08),
			Vector2(tx + tw,  my - mh * 0.42),
		])
		draw_colored_polygon(pts_top, Color(0.88, 0.85, 0.82, alpha))
		# Lower teeth point upward (only draw on even indices for gap effect)
		if i % 2 == 0:
			var pts_bot := PackedVector2Array([
				Vector2(tx + tw * 0.1, my + mh * 0.42),
				Vector2(tx + tw * 0.6, my - mh * 0.08),
				Vector2(tx + tw,       my + mh * 0.42),
			])
			draw_colored_polygon(pts_bot, Color(0.82, 0.78, 0.75, alpha * 0.85))

	# ── Vignette (red-dark edges, face gets darker toward perimeter) ──
	for ring in 4:
		var t01 := float(ring) / 4.0
		var r := lerpf(fw * 0.45, sz.length() * 0.65, t01)
		draw_arc(fc, r, 0, TAU, 32,
			Color(0.15, 0.0, 0.0, alpha * (0.18 - t01 * 0.04)), r * 0.22)

	# ── Motion lines (radial, suggesting rush toward camera) ──
	if progress > 0.1:
		var ml_alpha := progress * alpha * 0.25
		for i in 18:
			var ang := float(i) / 18.0 * TAU
			var dist := sz.length() * 0.5
			draw_line(fc, fc + Vector2(cos(ang), sin(ang)) * dist,
				Color(0.2, 0.0, 0.0, ml_alpha), 1.0)


## Draw a filled ellipse using a polygon approximation.
func _fill_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 32
	for i in steps:
		var a := float(i) / float(steps) * TAU
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)
