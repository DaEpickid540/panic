extends Node3D
## Corpse — the dropped body + blood splatter left where a runner was killed.
## Purely cosmetic (no collision); persists for the rest of the round. Spawned by
## GameController when a hunted player is captured.

func setup(color: Color) -> void:
	# Toppled body, sprawled in a random direction.
	var mesh := Node3D.new()
	add_child(mesh)
	Avatar.build(mesh)
	Avatar.set_color(mesh, color.darkened(0.25))
	mesh.rotation.x = -PI * 0.5          # lie flat on the floor
	mesh.position.y = 0.34
	rotation.y = randf() * TAU           # random sprawl orientation
	_splatter()


## Blood pooling out across the floor around the body.
func _splatter() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.02, 0.02)
	mat.roughness = 0.22
	mat.metallic = 0.25

	# Spreading pool of overlapping discs (denser near the body).
	for i in 14:
		var ang := randf() * TAU
		var dist := randf() * 3.4
		var r := randf_range(0.35, 1.2) * (1.0 - dist / 5.5)
		if r < 0.15:
			continue
		var disc := CylinderMesh.new()
		disc.top_radius = r
		disc.bottom_radius = r
		disc.height = 0.02
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.material_override = mat
		mi.position = Vector3(cos(ang) * dist, 0.03, sin(ang) * dist)
		add_child(mi)

	# A few thin streaks flung outward.
	for i in 4:
		var a := randf() * TAU
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.4, randf_range(1.6, 3.6))
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(cos(a) * 1.1, 0.025, sin(a) * 1.1)
		mi.rotation.y = a
		add_child(mi)
