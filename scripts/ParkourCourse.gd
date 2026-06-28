extends Node3D
## ParkourCourse — procedurally generates a linear obstacle course with checkpoints.
##
## The course is a sequence of platforms connected by gaps that match the player's
## jump physics (JUMP_FORCE=7, gravity=18 → max height ~1.36m, max gap ~4.2m at
## full sprint). Each segment is guaranteed reachable.
##
## Ghosts can push runners (knockback, not damage) but anti-targeting prevents
## spamming the same player.

signal player_fell(peer_id: int)
signal course_finished(peer_id: int)

const SEGMENT_COUNT  := 28
const PLATFORM_MIN_W := 2.5
const PLATFORM_MAX_W := 5.0
const PLATFORM_MIN_D := 2.0
const PLATFORM_MAX_D := 4.0
const MAX_GAP_H      := 3.8
const MAX_HEIGHT_UP   := 1.2
const MAX_HEIGHT_DOWN := 1.5
const CHECKPOINT_EVERY := 5

## The whole course floats above the map floor so falling clearly leaves it.
const BASE_Y    := 18.0
const BAND_LOW  := BASE_Y - 4.0    # lowest a valid platform may sit
const BAND_HIGH := BASE_Y + 10.0   # highest a valid platform may sit
const KILL_Y    := BASE_Y - 7.0    # below every valid platform → a real fall
const ROOM_HALF := 55.0            # course stays inside the white void room

var _rng := RandomNumberGenerator.new()
var _platforms: Array[Dictionary] = []
var _checkpoints: Array[Vector3] = []
var _spawner: Node
var _active := false


func setup(spawner: Node, seed_val: int) -> void:
	_spawner = spawner
	_rng.seed = seed_val
	_generate()
	_active = true


func _generate() -> void:
	var pos := Vector3(0, BASE_Y, 0)
	var forward := Vector3(0, 0, -1)

	for i in SEGMENT_COUNT:
		var pw := _rng.randf_range(PLATFORM_MIN_W, PLATFORM_MAX_W)
		var pd := _rng.randf_range(PLATFORM_MIN_D, PLATFORM_MAX_D)
		var ph := 0.4

		_make_platform(pos, Vector3(pw, ph, pd), i)
		_platforms.append({"pos": pos, "size": Vector3(pw, ph, pd), "index": i})

		if i % CHECKPOINT_EVERY == 0:
			_checkpoints.append(pos + Vector3(0, 1.0, 0))
			_make_checkpoint_marker(pos)

		if i == SEGMENT_COUNT - 1:
			_make_finish(pos)
			break

		var gap := _rng.randf_range(1.5, MAX_GAP_H)
		var dy := _rng.randf_range(-MAX_HEIGHT_DOWN, MAX_HEIGHT_UP)
		var turn := _rng.randf_range(-0.4, 0.4)
		# Steer back toward the room centre if we're drifting near a wall, so the
		# course always stays inside the bounded white room.
		if absf(pos.x) > ROOM_HALF - 14.0 or absf(pos.z) > ROOM_HALF - 14.0:
			var inward := (Vector3.ZERO - Vector3(pos.x, 0, pos.z)).normalized()
			forward = forward.lerp(inward, 0.5).normalized()
		else:
			forward = forward.rotated(Vector3.UP, turn).normalized()
		pos += forward * (pd * 0.5 + gap + pd * 0.5) + Vector3(0, dy, 0)
		pos.y = clampf(pos.y, BAND_LOW, BAND_HIGH)   # never descend into the kill plane
		pos.x = clampf(pos.x, -ROOM_HALF + 6.0, ROOM_HALF - 6.0)
		pos.z = clampf(pos.z, -ROOM_HALF + 6.0, ROOM_HALF - 6.0)

		if i > 3 and _rng.randf() < 0.2:
			_make_obstacle(pos, pw)
		if i > 5 and _rng.randf() < 0.15:
			_make_moving_platform(pos, pw, pd)


func _make_platform(pos: Vector3, size: Vector3, idx: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.94, 0.94, 0.96)   # clean white platforms
	m.roughness = 0.7
	mi.material_override = m
	body.add_child(mi)
	# Subtle light-gray rim so edges read against the white room.
	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.7, 0.72, 0.76)
	var edge := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(size.x + 0.1, 0.06, size.z + 0.1)
	edge.mesh = em
	edge.position = Vector3(0, size.y * 0.5, 0)
	edge.material_override = edge_mat
	body.add_child(edge)


func _make_checkpoint_marker(pos: Vector3) -> void:
	var flag := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = 3.0
	flag.mesh = cm
	flag.position = pos + Vector3(0, 1.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.85, 0.3)
	m.emission_enabled = true
	m.emission = Color(0.05, 0.6, 0.15)
	m.emission_energy_multiplier = 2.0
	flag.material_override = m
	add_child(flag)
	var light := OmniLight3D.new()
	light.light_color = Color(0.1, 0.85, 0.3)
	light.light_energy = 1.5
	light.omni_range = 8.0
	light.position = pos + Vector3(0, 2.0, 0)
	add_child(light)


func _make_finish(pos: Vector3) -> void:
	var arch := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6, 4, 0.4)
	arch.mesh = bm
	arch.position = pos + Vector3(0, 2.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.8, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.8, 0.65, 0.05)
	m.emission_energy_multiplier = 3.0
	arch.material_override = m
	add_child(arch)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1 << 1
	area.position = pos + Vector3(0, 2, 0)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(6, 4, 2)
	cs.shape = bs
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_finish_body)


func _make_obstacle(pos: Vector3, plat_w: float) -> void:
	var wall_h := _rng.randf_range(0.8, 1.6)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0, wall_h * 0.5 + 0.2, 0)
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(plat_w * 0.6, wall_h, 0.4)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plat_w * 0.6, wall_h, 0.4)
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.08, 0.08)   # red = hazard
	m.emission_enabled = true
	m.emission = Color(0.6, 0.03, 0.03)
	m.emission_energy_multiplier = 1.0
	mi.material_override = m
	body.add_child(mi)


func _make_moving_platform(pos: Vector3, pw: float, pd: float) -> void:
	var body := AnimatableBody3D.new()
	body.collision_layer = 1
	body.position = pos + Vector3(0, 0.3, 0)
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(pw * 0.7, 0.3, pd * 0.7)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(pw * 0.7, 0.3, pd * 0.7)
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.7, 0.95)   # cyan = moving (safe to stand on)
	m.emission_enabled = true
	m.emission = Color(0.15, 0.45, 0.7)
	m.emission_energy_multiplier = 1.0
	mi.material_override = m
	body.add_child(mi)
	var t := create_tween().set_loops()
	var offset := _rng.randf_range(2.0, 4.0)
	t.tween_property(body, "position:x", pos.x + offset, 2.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(body, "position:x", pos.x - offset, 2.0).set_trans(Tween.TRANS_SINE)


func get_start_pos() -> Vector3:
	if _platforms.is_empty():
		return Vector3(0, 2, 0)
	return _platforms[0]["pos"] + Vector3(0, 2, 0)


func get_checkpoint(index: int) -> Vector3:
	if index < 0 or index >= _checkpoints.size():
		return get_start_pos()
	return _checkpoints[index]


## Highest checkpoint index the local player has touched (progress tracking).
var _reached := 0


func _process(_delta: float) -> void:
	if not _active or _spawner == null:
		return
	var lp = _spawner.get("local_player")
	if lp == null or not is_instance_valid(lp):
		return

	# Advance the reached-checkpoint as the player nears the next one.
	if _reached + 1 < _checkpoints.size():
		var nxt: Vector3 = _checkpoints[_reached + 1]
		if lp.global_position.distance_to(nxt) < 3.5:
			_reached += 1

	# Fell off the course → respawn at the last reached checkpoint.
	if lp.global_position.y < KILL_Y:
		var cp: Vector3 = _checkpoints[_reached] if _reached < _checkpoints.size() else get_start_pos()
		lp.global_position = cp
		lp.velocity = Vector3.ZERO
		player_fell.emit(lp.peer_id)


func _on_finish_body(body: Node) -> void:
	var owner_node := body.get_parent() if body.get_parent() else body
	if "peer_id" in owner_node:
		course_finished.emit(owner_node.peer_id)
