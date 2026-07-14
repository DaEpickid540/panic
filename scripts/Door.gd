extends Node3D
## Door — a swinging interior door spawned by MapBase at a doorway gap.
##
## MapBase records every doorway it carves ("door spots") while building a
## layout, then each round spawns doors at a random subset of those spots and
## LOCKS a few of them. Which doorways have doors — and which are locked —
## changes every match, so learned routes go stale between rounds.
##
## Unlocked doors swing open automatically when a player gets close and swing
## shut again once everyone leaves. Locked doors never open: they get a red
## emissive plate and a padlock so runners can read "locked" at a glance.

const DOOR_HEIGHT := 3.2
const OPEN_ANGLE  := deg_to_rad(104.0)
const OPEN_SPEED  := 6.0
const CLOSE_SPEED := 2.6
const SENSE_RANGE := 2.8

var locked := false

var _hinge: Node3D
var _sense: Area3D
var _bodies_near := 0


## Build the door. `along_x` = the doorway gap runs along the X axis
## (i.e. the wall it sits in runs along X). `width` = gap width in metres.
func setup(along_x: bool, width: float, p_locked: bool) -> void:
	locked = p_locked
	if not along_x:
		rotation.y = PI * 0.5

	var panel_w := width * 0.94
	var wood := Color(0.24, 0.16, 0.10)

	# Frame posts either side of the gap (cosmetic, sells the doorway).
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.18, DOOR_HEIGHT + 0.3, 0.34)
		post.mesh = pm
		post.position = Vector3(s * width * 0.5, (DOOR_HEIGHT + 0.3) * 0.5, 0)
		post.material_override = _mat(wood.darkened(0.25))
		add_child(post)

	# Hinged panel: a StaticBody3D hanging off a hinge pivot at one side.
	_hinge = Node3D.new()
	_hinge.position = Vector3(-width * 0.5, 0, 0)
	add_child(_hinge)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = Vector3(panel_w * 0.5, DOOR_HEIGHT * 0.5, 0)
	_hinge.add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(panel_w, DOOR_HEIGHT, 0.16)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	mi.material_override = _mat(wood)
	body.add_child(mi)

	# Handle.
	var handle := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.07
	hm.height = 0.14
	handle.mesh = hm
	handle.position = Vector3(panel_w * 0.82, DOOR_HEIGHT * 0.42, 0.14)
	handle.material_override = _mat(Color(0.75, 0.65, 0.35))
	body.add_child(handle)

	if locked:
		# Red warning plate + padlock block so "locked" reads instantly.
		var plate := MeshInstance3D.new()
		var plm := BoxMesh.new()
		plm.size = Vector3(0.6, 0.34, 0.04)
		plate.mesh = plm
		plate.position = Vector3(panel_w * 0.5, DOOR_HEIGHT * 0.62, 0.10)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.55, 0.05, 0.05)
		pmat.emission_enabled = true
		pmat.emission = Color(0.8, 0.05, 0.05)
		pmat.emission_energy_multiplier = 0.9
		plate.material_override = pmat
		body.add_child(plate)
		var lock := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.16, 0.22, 0.10)
		lock.mesh = lm
		lock.position = Vector3(panel_w * 0.86, DOOR_HEIGHT * 0.30, 0.12)
		lock.material_override = _mat(Color(0.55, 0.5, 0.4))
		body.add_child(lock)
		return   # locked doors never open — no sensor needed

	# Proximity sensor: door swings open while any player stands near it.
	_sense = Area3D.new()
	_sense.monitoring = true
	_sense.collision_layer = 0
	_sense.collision_mask = 1 << 1   # physics layer 2 = "players"
	add_child(_sense)
	var ss := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = SENSE_RANGE
	cyl.height = DOOR_HEIGHT
	ss.shape = cyl
	ss.position = Vector3(0, DOOR_HEIGHT * 0.5, 0)
	_sense.add_child(ss)
	_sense.body_entered.connect(func(_b: Node3D) -> void: _bodies_near += 1)
	_sense.body_exited.connect(func(_b: Node3D) -> void: _bodies_near = maxi(0, _bodies_near - 1))


func _process(delta: float) -> void:
	if locked or _hinge == null:
		return
	var want := OPEN_ANGLE if _bodies_near > 0 else 0.0
	var speed := OPEN_SPEED if _bodies_near > 0 else CLOSE_SPEED
	_hinge.rotation.y = lerp_angle(_hinge.rotation.y, want, minf(1.0, speed * delta))


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m
