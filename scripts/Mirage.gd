extends Node3D
## Mirage — a fake hunter that wanders at distance and vanishes when approached.
##
## The runner sees a red figure far away and can't tell if it's the real hunter.
## When they get within VANISH_DIST metres the mirage disappears with a glitch
## burst, revealing it was an illusion. Reappears elsewhere after a delay.

const WANDER_SPEED := 2.2    # slow and deliberate — like a ghost
const VANISH_DIST  := 9.0    # disappears when player gets this close
const RESPAWN_MIN  := 50.0
const RESPAWN_MAX  := 90.0

var _spawner: Node
var _bound: float = 88.0
var _wander_target := Vector3.ZERO
var _mesh: Node3D
var _visible := false
var _respawn_cd := 0.0

signal vanished   # tells GlitchOverlay to fire a burst


func _ready() -> void:
	_mesh = Node3D.new()
	add_child(_mesh)
	_build_mirage_mesh()
	# Delay first appearance so the match has a moment to breathe.
	_respawn_cd = randf_range(30.0, 60.0)
	_set_visible(false)


func setup(spawner: Node, bound: float) -> void:
	_spawner = spawner
	_bound   = bound
	_pick_wander()


func _process(delta: float) -> void:
	if GameManager.current_phase != GameManager.Phase.HUNTING:
		return

	if not _visible:
		_respawn_cd -= delta
		if _respawn_cd <= 0.0:
			_spawn_far_from_player()
			_set_visible(true)
		return

	# Vanish if the local player gets too close.
	var lp := _get_local_player()
	if lp != null:
		if global_position.distance_to(lp.global_position) < VANISH_DIST:
			vanished.emit()
			_set_visible(false)
			_respawn_cd = randf_range(RESPAWN_MIN, RESPAWN_MAX)
			return

	# Slow wander.
	var to := _wander_target - global_position
	to.y = 0.0
	if to.length() < 1.5:
		_pick_wander()
	else:
		var dir := to.normalized()
		global_position += dir * WANDER_SPEED * delta
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 0.08)

	global_position.x = clampf(global_position.x, -_bound, _bound)
	global_position.z = clampf(global_position.z, -_bound, _bound)


func _pick_wander() -> void:
	_wander_target = Vector3(randf_range(-_bound + 6, _bound - 6),
							 0.1,
							 randf_range(-_bound + 6, _bound - 6))


## Spawn at a point that is far from the player but visible (not behind them).
func _spawn_far_from_player() -> void:
	var lp := _get_local_player()
	var best_pos := Vector3(_bound * 0.7, 0.1, 0.0)
	var best_score := -1.0
	for attempt in 10:
		var ang := randf_range(0, TAU)
		var r   := randf_range(_bound * 0.5, _bound * 0.88)
		var pos := Vector3(cos(ang) * r, 0.1, sin(ang) * r)
		if lp == null:
			best_pos = pos
			break
		var dist := pos.distance_to(lp.global_position)
		# Prefer positions that are far but still inside the forward arc.
		var cam := get_viewport().get_camera_3d()
		var score := dist
		if cam != null:
			var to_pos := (pos - cam.global_position).normalized()
			var cam_fwd := -cam.global_transform.basis.z
			# Prefer positions the player can see (dot > 0 = in front).
			score += cam_fwd.dot(to_pos) * 20.0
		if score > best_score:
			best_score = score
			best_pos   = pos
	global_position = best_pos
	_pick_wander()


func _get_local_player() -> Node3D:
	if _spawner == null:
		return null
	var lp = _spawner.get("local_player")
	return lp if (lp != null and is_instance_valid(lp)) else null


func _set_visible(show: bool) -> void:
	_visible = show
	if _mesh:
		_mesh.visible = show


## Hunter appearance: same red glow as the real hunter RemotePlayer.
func _build_mirage_mesh() -> void:
	Avatar.build(_mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(0.85, 0.05, 0.05)
	mat.emission_enabled = true
	mat.emission        = Color(0.4, 0.0, 0.0)
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a  = 0.80   # slightly transparent — close inspection reveals it's wrong
	Avatar.set_material(_mesh, mat)
