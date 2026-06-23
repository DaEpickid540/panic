extends RefCounted
class_name Avatar
## Builds a low-poly but genuinely human-looking figure: pelvis + rounded torso,
## shoulders, neck, ovoid head with hair/ears/nose/eyes, capsule arms & legs with
## hands and shoes. Limbs hang from pivot nodes named LegL/LegR/ArmL/ArmR so the
## existing walk-cycle animation keeps working unchanged.
##
## set_monster() reskins the same figure into a scary creature (dark flesh,
## glowing eyes, horns) for hunters / fake killers.

const LEG_LEN := 0.86
const ARM_LEN := 0.62

# Parts that keep their own material when set_material/set_color is called.
const FIXED_PARTS := ["EyeL", "EyeR", "Hair"]


static func build(root: Node3D) -> void:
	for c in root.get_children():
		c.queue_free()

	# ── Lower body ──
	_box(root, "Pelvis", Vector3(0.34, 0.24, 0.25), Vector3(0, 0.10, 0))
	# ── Torso (rounded) + shoulders for a human silhouette ──
	_capsule_mesh(root, "Torso", 0.21, 0.52, Vector3(0, 0.46, 0))
	_box(root, "Shoulders", Vector3(0.52, 0.15, 0.26), Vector3(0, 0.66, 0))
	# ── Neck + head ──
	_cylinder(root, "Neck", 0.07, 0.12, Vector3(0, 0.76, 0))
	var head := _sphere(root, "Head", 0.205, Vector3(0, 0.92, 0))
	head.scale = Vector3(0.96, 1.14, 1.02)   # ovoid, slightly taller than wide

	# ── Hair (dark cap, kept dark via FIXED_PARTS) ──
	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.10, 0.08, 0.07)
	hair_mat.roughness = 0.9
	var hair := _sphere_mat(root, "Hair", 0.215, Vector3(0, 0.965, -0.02), hair_mat)
	hair.scale = Vector3(1.02, 0.78, 1.04)

	# ── Ears + nose for a real face ──
	_sphere(root, "EarL", 0.045, Vector3(-0.195, 0.92, 0.0))
	_sphere(root, "EarR", 0.045, Vector3( 0.195, 0.92, 0.0))
	_box(root, "Nose", Vector3(0.05, 0.06, 0.06), Vector3(0, 0.90, 0.205))

	# ── Eyes (dark; kept via FIXED_PARTS) ──
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.05, 0.07)
	eye_mat.roughness = 0.2
	_sphere_mat(root, "EyeL", 0.042, Vector3(-0.082, 0.95, 0.18), eye_mat)
	_sphere_mat(root, "EyeR", 0.042, Vector3( 0.082, 0.95, 0.18), eye_mat)

	# ── Legs (pivot at hip; capsule hangs down — used by animate_walk) ──
	_limb(root, "LegL", 0.11, LEG_LEN, Vector3(-0.12, 0.0, 0))
	_limb(root, "LegR", 0.11, LEG_LEN, Vector3( 0.12, 0.0, 0))
	_box(root, "ShoeL", Vector3(0.16, 0.09, 0.30), Vector3(-0.12, -0.85, 0.06))
	_box(root, "ShoeR", Vector3(0.16, 0.09, 0.30), Vector3( 0.12, -0.85, 0.06))

	# ── Arms (pivot at shoulder — used by animate_walk) ──
	_limb(root, "ArmL", 0.075, ARM_LEN, Vector3(-0.31, 0.62, 0))
	_limb(root, "ArmR", 0.075, ARM_LEN, Vector3( 0.31, 0.62, 0))
	var wrist_y := 0.62 - ARM_LEN
	_sphere(root, "HandL", 0.075, Vector3(-0.31, wrist_y, 0))
	_sphere(root, "HandR", 0.075, Vector3( 0.31, wrist_y, 0))


# ─────────────────────────────────────────────────────────────────────────────
# MATERIALS
# ─────────────────────────────────────────────────────────────────────────────

## Apply one material to every mesh EXCEPT the fixed parts (eyes, hair).
static func set_material(root: Node3D, mat: Material) -> void:
	_apply(root, mat)


static func _apply(node: Node, mat: Material) -> void:
	if node.name in FIXED_PARTS:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_apply(c, mat)


static func set_color(root: Node3D, body: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = body
	m.roughness = 0.6
	set_material(root, m)


## Reskin the figure as a terrifying creature. `variant`:
##   0 Wraith   — pitch black, blazing red eyes, horns
##   1 Pallid   — sickly grey flesh, sunken yellow eyes
##   2 Ember    — charred body glowing with orange cracks, fiery eyes
##   3 Flayed   — raw red sinew, white bulging eyes
static func set_monster(root: Node3D, variant: int) -> void:
	var body := StandardMaterial3D.new()
	body.roughness = 0.85
	var eye := StandardMaterial3D.new()
	eye.emission_enabled = true
	var horn_col := Color(0.06, 0.05, 0.05)

	match variant % 4:
		0:
			body.albedo_color = Color(0.05, 0.05, 0.07)
			body.emission_enabled = true
			body.emission = Color(0.15, 0.0, 0.0)
			body.emission_energy_multiplier = 0.35
			eye.albedo_color = Color(1.0, 0.05, 0.05)
			eye.emission = Color(1.0, 0.1, 0.1)
			eye.emission_energy_multiplier = 6.0
		1:
			body.albedo_color = Color(0.50, 0.50, 0.44)
			eye.albedo_color = Color(0.9, 0.85, 0.2)
			eye.emission = Color(1.0, 0.9, 0.25)
			eye.emission_energy_multiplier = 4.0
			horn_col = Color(0.4, 0.38, 0.32)
		2:
			body.albedo_color = Color(0.07, 0.06, 0.05)
			body.emission_enabled = true
			body.emission = Color(1.0, 0.32, 0.05)
			body.emission_energy_multiplier = 0.55
			eye.albedo_color = Color(1.0, 0.5, 0.1)
			eye.emission = Color(1.0, 0.4, 0.0)
			eye.emission_energy_multiplier = 7.0
		3:
			body.albedo_color = Color(0.45, 0.06, 0.07)
			body.roughness = 0.45
			body.metallic = 0.15
			eye.albedo_color = Color(0.95, 0.95, 0.95)
			eye.emission = Color(0.9, 0.9, 0.9)
			eye.emission_energy_multiplier = 3.0

	# Body (everything incl. hair so the whole creature is one menacing skin).
	for n in root.get_children():
		_force_apply(n, body)
	# Glowing eyes (bigger + bulging for dread).
	for n in FIXED_PARTS:
		if n == "Hair":
			continue
		var e := root.get_node_or_null(n)
		if e:
			(e as MeshInstance3D).material_override = eye
			(e as Node3D).scale = Vector3(1.5, 1.5, 1.5)
	_add_horns(root, horn_col)


static func _force_apply(node: Node, mat: Material) -> void:
	if node is MeshInstance3D and not (node.name in ["EyeL", "EyeR"]):
		(node as MeshInstance3D).material_override = mat
	for c in node.get_children():
		_force_apply(c, mat)


## Two curved horns on the head (idempotent — won't duplicate on reskin).
static func _add_horns(root: Node3D, col: Color) -> void:
	if root.get_node_or_null("HornL") != null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	for side in [["HornL", -1.0], ["HornR", 1.0]]:
		var mi := MeshInstance3D.new()
		mi.name = side[0]
		var cone := CylinderMesh.new()
		cone.top_radius = 0.005
		cone.bottom_radius = 0.06
		cone.height = 0.28
		mi.mesh = cone
		mi.material_override = mat
		mi.position = Vector3(0.11 * side[1], 1.08, -0.02)
		mi.rotation = Vector3(deg_to_rad(-18), 0, deg_to_rad(22.0 * side[1]))
		root.add_child(mi)


# ─────────────────────────────────────────────────────────────────────────────
# WALK ANIMATION (unchanged API)
# ─────────────────────────────────────────────────────────────────────────────

static func animate_walk(root: Node3D, phase: float, amp: float) -> void:
	var s := sin(phase) * amp
	_set_swing(root, "LegL",  s)
	_set_swing(root, "LegR", -s)
	_set_swing(root, "ArmL", -s)
	_set_swing(root, "ArmR",  s)


static func _set_swing(root: Node3D, n: String, ang: float) -> void:
	var p := root.get_node_or_null(n)
	if p:
		(p as Node3D).rotation.x = ang


# ─────────────────────────────────────────────────────────────────────────────
# MESH HELPERS
# ─────────────────────────────────────────────────────────────────────────────

static func _box(root: Node3D, n: String, size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	root.add_child(mi)
	return mi


static func _sphere(root: Node3D, n: String, r: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	mi.mesh = m
	mi.position = pos
	root.add_child(mi)
	return mi


static func _sphere_mat(root: Node3D, n: String, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := _sphere(root, n, r, pos)
	mi.material_override = mat
	return mi


static func _cylinder(root: Node3D, n: String, r: float, h: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	mi.mesh = m
	mi.position = pos
	root.add_child(mi)
	return mi


static func _capsule_mesh(root: Node3D, n: String, r: float, h: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	mi.mesh = m
	mi.position = pos
	root.add_child(mi)
	return mi


## A limb: a pivot Node3D (for swing animation) with a capsule hanging below it.
static func _limb(root: Node3D, n: String, r: float, length: float, joint: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.name = n
	pivot.position = joint
	root.add_child(pivot)
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = length
	mi.mesh = cap
	mi.position = Vector3(0, -length * 0.5, 0)
	pivot.add_child(mi)
