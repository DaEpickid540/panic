extends Node3D
class_name ScopedGun
## ScopedGun — a scoped rifle pickup that appears once per round.
##
## Only the HUNTER can grab it. It grants a small clip of high-damage rounds:
## hold RMB to aim down the scope (zoomed view), LMB to fire. One shot per
## trigger pull, then a 15-second re-chamber cooldown (see GUN_FIRE_CD and
## _cooldown_remaining in PlayerController.gd, with a RELOADING/READY readout
## near the scope), and the rifle is discarded when empty.

const AMMO         := 3
const PICKUP_RANGE := 2.0
const BOB_HEIGHT   := 0.25
const BOB_SPEED    := 1.6
const SPIN_SPEED   := 0.9

var _spawner: Node
var _base_y := 1.2
var _t := 0.0
var _taken := false
var _visual: Node3D
var _glow: OmniLight3D


func setup(p_spawner: Node) -> void:
	_spawner = p_spawner
	_base_y = global_position.y
	_build_visual()


func _build_visual() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	# Barrel.
	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.035
	bm.bottom_radius = 0.045
	bm.height = 0.9
	barrel.mesh = bm
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.06, -0.35)
	barrel.material_override = _metal(Color(0.35, 0.36, 0.4))
	_visual.add_child(barrel)
	# Receiver.
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.09, 0.14, 0.55)
	body.mesh = bb
	body.position = Vector3(0, 0.02, 0.12)
	body.material_override = _metal(Color(0.22, 0.23, 0.26))
	_visual.add_child(body)
	# Stock.
	var stock := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(0.08, 0.16, 0.35)
	stock.mesh = sb
	stock.position = Vector3(0, -0.02, 0.5)
	stock.material_override = _metal(Color(0.3, 0.2, 0.12))
	_visual.add_child(stock)
	# Scope tube.
	var scope := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.045
	sc.bottom_radius = 0.045
	sc.height = 0.3
	scope.mesh = sc
	scope.rotation.x = PI * 0.5
	scope.position = Vector3(0, 0.16, 0.05)
	scope.material_override = _metal(Color(0.12, 0.13, 0.16))
	_visual.add_child(scope)
	# Lens glint so the rifle reads from across a dark room.
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.035
	lm.height = 0.07
	lens.mesh = lm
	lens.position = Vector3(0, 0.16, -0.11)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.4, 0.8, 1.0)
	lmat.emission_enabled = true
	lmat.emission = Color(0.3, 0.7, 1.0)
	lmat.emission_energy_multiplier = 1.6
	lens.material_override = lmat
	_visual.add_child(lens)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.3, 0.7, 1.0)
	_glow.light_energy = 0.9
	_glow.omni_range = 5.0
	add_child(_glow)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	global_position.y = _base_y + sin(_t * BOB_SPEED) * BOB_HEIGHT
	if _visual:
		_visual.rotation.y += SPIN_SPEED * delta
	if _spawner == null:
		return
	var lp = _spawner.get("local_player")
	if lp == null or not is_instance_valid(lp):
		return
	if lp.role != GameManager.Role.HUNTER:
		return
	if global_position.distance_to(lp.global_position) <= PICKUP_RANGE \
			and lp.has_method("give_scoped_gun"):
		_taken = true
		lp.give_scoped_gun(AMMO)
		AudioManager.play_sfx("phase_change", -4.0)
		queue_free()


func _metal(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.7
	m.roughness = 0.35
	return m
