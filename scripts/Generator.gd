extends Node3D
## Generator — a hider objective. Runners power it up by standing near it (no key
## press; multiple runners power it faster). When every generator is powered the
## hiders escape and win. The status orb reads RED (idle) → AMBER (powering) →
## GREEN (done), so the hunter can see which ones are being worked.

signal completed

const RANGE  := 4.5
const _NEAR2 := RANGE * RANGE

var repair_time := 12.0
var _repair_rate: float

var _spawner: Node
var progress := 0.0
var done := false

var _orb_mat: StandardMaterial3D
var _light: OmniLight3D
var _t := 0.0


func setup(spawner: Node) -> void:
	_spawner = spawner
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	repair_time = rng.randf_range(15.0, 30.0)
	_repair_rate = 1.0 / repair_time


func _ready() -> void:
	add_to_group("generator")   # so runner bots can find + power objectives
	# Body + collider.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.4, 1.6, 1.1)
	shape.shape = bx
	shape.position = Vector3(0, 0.8, 0)
	body.add_child(shape)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.23, 0.26)
	mat.metallic = 0.5
	mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.4, 1.6, 1.1)
	mi.mesh = bm
	mi.position = Vector3(0, 0.8, 0)
	mi.material_override = mat
	body.add_child(mi)
	# Exhaust pipe for a bit of read.
	var pipe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 1.0
	pipe.mesh = cm
	pipe.position = Vector3(0.45, 1.9, -0.3)
	pipe.material_override = mat
	add_child(pipe)
	# Status orb + light.
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.emission_enabled = true
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	orb.mesh = sm
	orb.position = Vector3(0, 1.78, 0)
	orb.material_override = _orb_mat
	add_child(orb)
	_light = OmniLight3D.new()
	_light.omni_range = 7.0
	_light.position = Vector3(0, 1.78, 0)
	add_child(_light)
	_set_status(Color(0.9, 0.12, 0.12), 2.0)


func _process(delta: float) -> void:
	if done or GameManager.current_phase != GameManager.Phase.HUNTING:
		return
	var n := _runners_near()
	if n > 0.01:
		progress = minf(1.0, progress + _repair_rate * n * delta)
		_t += delta
		var pulse := 0.5 + 0.5 * sin(_t * 9.0)
		_set_status(Color(1.0, 0.7, 0.12), 1.5 + pulse * 2.5)   # amber, pulsing
		if progress >= 1.0:
			_complete()
	else:
		_set_status(Color(0.9, 0.12, 0.12), 2.0)                 # idle red


func _complete() -> void:
	done = true
	_set_status(Color(0.2, 1.0, 0.35), 3.0)                      # powered green
	AudioManager.play_sfx("phase_change", 0.0)
	completed.emit()


func _set_status(c: Color, energy: float) -> void:
	_orb_mat.albedo_color = c
	_orb_mat.emission = c
	_orb_mat.emission_energy_multiplier = energy
	if _light:
		_light.light_color = c
		_light.light_energy = clampf(energy * 0.5, 0.6, 2.0)


func _runners_near() -> float:
	if _spawner == null:
		return 0.0
	var c := 0.0
	var lp = _spawner.get("local_player")
	if lp != null and is_instance_valid(lp) and lp.role == GameManager.Role.HUNTED \
			and lp.global_position.distance_squared_to(global_position) < _NEAR2:
		var rm: float = lp.repair_mult() if lp.has_method("repair_mult") else 1.0
		c += rm
	if "remotes" in _spawner:
		for id in _spawner.remotes:
			var rp = _spawner.remotes[id]
			if is_instance_valid(rp) and rp.role == GameManager.Role.HUNTED \
					and rp.global_position.distance_squared_to(global_position) < _NEAR2:
				if "is_bot" in rp and rp.is_bot:
					c += 0.35
				else:
					var rm: float = rp.repair_mult() if rp.has_method("repair_mult") else 1.0
					c += rm
	return c
