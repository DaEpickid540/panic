extends Node3D
## GhostLightning — a single lightning strike called down by a ghost.
##
## Spawned by PlayerController._fire_lightning() at the aimed ground point.
## It is the ghost's main griefing tool — on impact it:
##   • DAMAGES runners in radius (−1 HP)          → grief
##   • STUNS + SLOWS them                          → grief
##   • flashes a jumpscare on a hit runner's HUD   → visual scare
## plus the spectacle: a bright bolt, an expanding shock-ring, a light flash,
## and a loud thunder clap.

const RADIUS    := 8.5     # blast radius around the strike point (generous)
const DAMAGE    := 2       # HP removed from a directly-struck runner (2 of 3)
const STUN_TIME := 1.2     # seconds a struck runner is frozen
const SLOW_TIME := 5.0     # seconds a struck runner is slowed afterwards
const BOLT_TOP  := 30.0    # bolt reaches this high above the strike point
const LIFETIME  := 1.3     # node self-frees after this long

var _ghost_id := -1
var _bolt_root: Node3D   # holds just the bolt segments (for fading)


func strike(pos: Vector3, ghost_id: int) -> void:
	_ghost_id = ghost_id
	global_position = pos
	_build_bolt()
	_build_ring()
	_build_flash()
	AudioManager.play_sfx("thunder", 7.0)
	_apply_grief(pos, ghost_id)

	# Self-destruct after the effect plays out.
	var t := create_tween()
	t.tween_interval(LIFETIME)
	t.tween_callback(queue_free)


# ─────────────────────────────────────────────────────────────────────────────
# VISUALS
# ─────────────────────────────────────────────────────────────────────────────

## A jagged bright bolt built from a few offset segments.
func _build_bolt() -> void:
	_bolt_root = Node3D.new()
	add_child(_bolt_root)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.92, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var segments := 7
	var step := BOLT_TOP / float(segments)
	var prev := Vector3.ZERO
	for i in range(1, segments + 1):
		var jitter := 0.0 if i == 1 else 0.7
		var next := Vector3(
			randf_range(-jitter, jitter), step * i, randf_range(-jitter, jitter))
		_add_bolt_segment(prev, next, mat)
		prev = next

	# Quick fade-out of the whole bolt.
	var fade := create_tween()
	fade.tween_interval(0.18)
	fade.tween_method(_set_bolt_alpha, 1.0, 0.0, 0.45)


func _add_bolt_segment(a: Vector3, b: Vector3, mat: Material) -> void:
	var mid := (a + b) * 0.5
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.22
	cyl.height = (b - a).length()
	mi.mesh = cyl
	mi.material_override = mat
	mi.position = mid
	# Orient the cylinder (default +Y) along the segment direction. The bolt is
	# near-vertical, so pick an up vector that isn't colinear with the direction.
	var dir := (b - a).normalized()
	if dir.length() > 0.001:
		var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		mi.look_at_from_position(mid, mid + dir, up)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_bolt_root.add_child(mi)


func _set_bolt_alpha(a: float) -> void:
	if _bolt_root == null or not is_instance_valid(_bolt_root):
		return
	for c in _bolt_root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is StandardMaterial3D:
			var m := (c as MeshInstance3D).material_override as StandardMaterial3D
			m.emission_energy_multiplier = 6.0 * a


## Expanding shock-ring on the ground.
func _build_ring() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 1.0
	ring.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.85, 1.0, 0.8)
	m.emission_enabled = true
	m.emission = Color(0.55, 0.8, 1.0)
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = m
	ring.position = Vector3(0, 0.1, 0)
	add_child(ring)

	var t := create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector3(RADIUS, 1.0, RADIUS), 0.5)
	t.tween_property(m, "albedo_color:a", 0.0, 0.5)


## Bright point-light flash that decays fast.
func _build_flash() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 8.0
	light.omni_range = 24.0
	light.position = Vector3(0, 2.0, 0)
	add_child(light)
	var t := create_tween()
	t.tween_property(light, "light_energy", 0.0, 0.5)


# ─────────────────────────────────────────────────────────────────────────────
# GRIEF
# ─────────────────────────────────────────────────────────────────────────────

func _apply_grief(pos: Vector3, ghost_id: int) -> void:
	var sp := _find_spawner()
	if sp == null:
		return

	var lp = sp.get("local_player")
	if lp != null and is_instance_valid(lp) and lp.role == GameManager.Role.HUNTED:
		if lp.global_position.distance_to(pos) <= RADIUS:
			GameManager.grief_runner(lp, ghost_id, DAMAGE, STUN_TIME)

	if "remotes" in sp:
		for id in sp.remotes:
			var rp = sp.remotes[id]
			if is_instance_valid(rp) and rp.role == GameManager.Role.HUNTED:
				if rp.global_position.distance_to(pos) <= RADIUS:
					GameManager.grief_runner(rp, ghost_id, DAMAGE, STUN_TIME)


func _find_spawner() -> Node:
	var gc := get_tree().get_first_node_in_group("game_controller")
	if gc:
		return gc.get_node_or_null("PlayerSpawner")
	return null
