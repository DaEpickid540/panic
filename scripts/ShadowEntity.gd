extends Node3D
## ShadowEntity — a dark figure that only moves when you're not looking at it.
##
## Horror rule: it closes the distance while you look away, freezes instantly
## the moment your camera passes over it. At < 2.5m it triggers a jumpscare
## and teleports to a new distant spawn point (it never actually kills you —
## that uncertainty is the point).

const MOVE_SPEED  := 5.5    # how fast it approaches when unseen
const VIEW_DOT    := 0.52   # camera dot > this = player is "looking at it"
const SCARE_DIST  := 2.5    # triggers jumpscare + teleport at this range
const RESPAWN_MIN := 20.0   # minimum wait before reappearing
const RESPAWN_MAX := 45.0   # maximum wait

var _spawner: Node           # PlayerSpawner for getting the local player + camera
var _bound: float = 88.0    # arena half-size; entity stays inside ±bound

var _visible := true         # false while on respawn cooldown
var _respawn_cd := 0.0
var _mesh: Node3D

# Emit this to tell HuntingUI to fire a jumpscare.
signal triggered_scare


func _ready() -> void:
	_mesh = Node3D.new()
	add_child(_mesh)
	_build_shadow_mesh()
	# Start a few seconds in so it's not right there at match start.
	_respawn_cd = randf_range(8.0, 18.0)
	_set_visible(false)


func setup(spawner: Node, bound: float) -> void:
	_spawner = spawner
	_bound   = bound
	_teleport_to_edge()


func _process(delta: float) -> void:
	if GameManager.current_phase != GameManager.Phase.HUNTING:
		return

	if not _visible:
		_respawn_cd -= delta
		if _respawn_cd <= 0.0:
			_teleport_to_edge()
			_set_visible(true)
		return

	var player := _get_local_player()
	if player == null:
		return

	var dist := global_position.distance_to(player.global_position)

	# Trigger scare if close enough.
	if dist < SCARE_DIST:
		triggered_scare.emit()
		_teleport_to_edge()
		_set_visible(false)
		_respawn_cd = randf_range(RESPAWN_MIN, RESPAWN_MAX)
		return

	# Move only while the player isn't looking at it.
	if not _player_looking_at_us(player):
		var dir := (global_position - player.global_position)
		dir.y = 0.0
		# Actually move TOWARD player (toward = negative of dir).
		dir = -dir.normalized()
		global_position += dir * MOVE_SPEED * delta
		# Clamp to arena.
		global_position.x = clampf(global_position.x, -_bound, _bound)
		global_position.z = clampf(global_position.z, -_bound, _bound)

	# Always face the player.
	var look_dir := player.global_position - global_position
	look_dir.y = 0.0
	if look_dir.length_squared() > 0.01:
		rotation.y = atan2(look_dir.x, look_dir.z)


## Returns true if the player's active camera cone intersects with this entity.
func _player_looking_at_us(player: Node3D) -> bool:
	# Use the active camera so it works for both FPS and iso views.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	var to_self := (global_position - cam.global_position).normalized()
	# Godot camera looks along local -Z.
	var cam_fwd := -cam.global_transform.basis.z
	return cam_fwd.dot(to_self) > VIEW_DOT


func _get_local_player() -> Node3D:
	if _spawner == null:
		return null
	var lp = _spawner.get("local_player")
	return lp if (lp != null and is_instance_valid(lp)) else null


## Teleport to a random point on the arena perimeter, away from the player.
func _teleport_to_edge() -> void:
	var lp := _get_local_player()
	var best_pos := Vector3.ZERO
	var best_dist := -1.0
	for attempt in 8:
		var ang := randf_range(0, TAU)
		var r   := randf_range(_bound * 0.65, _bound * 0.92)
		var pos := Vector3(cos(ang) * r, 0.1, sin(ang) * r)
		var d := 9999.0 if lp == null else pos.distance_to(lp.global_position)
		if d > best_dist:
			best_dist = d
			best_pos  = pos
	global_position = best_pos


func _set_visible(show: bool) -> void:
	_visible = show
	if _mesh:
		_mesh.visible = show


## Dark near-invisible avatar: standard mesh painted almost fully black.
func _build_shadow_mesh() -> void:
	Avatar.build(_mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color    = Color(0.04, 0.02, 0.06)
	mat.emission_enabled = true
	mat.emission        = Color(0.08, 0.0, 0.12)   # faint violet glow
	mat.emission_energy_multiplier = 0.6
	mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a  = 0.72   # slightly see-through so it reads as "wrong"
	Avatar.set_material(_mesh, mat)
