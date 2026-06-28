extends Node3D
## ObjectiveController — scatters the hider GENERATORS for a match and reports
## progress. When enough are powered it fires `all_complete` (the hiders escape).
##
## Placement is validated against the physics world: each candidate must sit in
## open space (not buried in a wall/obstacle) with solid floor beneath it, so a
## generator can never spawn somewhere unreachable.

signal all_complete
signal progress_changed(done: int, total: int)

const GEN_SCRIPT := preload("res://scripts/Generator.gd")

var total := 0
var required := 0
var done := 0


func setup(spawner: Node, bound: float, count: int, need: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Let the freshly-built map register its static bodies in the physics space
	# before we probe it for open spots.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state

	var b := maxf(bound - 8.0, 12.0)
	var used: Array[Vector3] = []

	# Pass 1: strict — validated open spots with comfortable spacing.
	_scatter(rng, space, b, count, 12.0, used)
	# Pass 2: relax spacing if the strict pass came up short (dense maps).
	if used.size() < count:
		_scatter(rng, space, b, count, 7.0, used)
	# Pass 3: last resort — any validated open spot, minimal spacing.
	if used.size() < count:
		_scatter(rng, space, b, count, 4.0, used)

	for pos in used:
		var g: Node3D = GEN_SCRIPT.new()
		add_child(g)
		g.global_position = pos
		g.setup(spawner)
		g.completed.connect(_on_done)

	total = used.size()
	# Never demand more generators than actually spawned, or the round is unwinnable.
	required = need if need > 0 else total
	required = clampi(required, 1, maxi(total, 1))
	progress_changed.emit(done, total)


## Try to add validated spots to `used` until it reaches `count` or we give up.
func _scatter(rng: RandomNumberGenerator, space: PhysicsDirectSpaceState3D,
		b: float, count: int, spacing: float, used: Array[Vector3]) -> void:
	var attempts := 0
	while used.size() < count and attempts < 400:
		attempts += 1
		var pos := Vector3(rng.randf_range(-b, b), 0.0, rng.randf_range(-b, b))
		if pos.length() < 14.0:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < spacing:
				too_close = true
				break
		if too_close:
			continue
		if not _is_open(space, pos):
			continue
		used.append(pos)


## True if `pos` has clearance for a generator (no wall/obstacle overlap) and
## solid floor beneath it.
func _is_open(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	# Clearance box at torso height — must NOT overlap any layer-1 geometry.
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.2, 2.4)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos + Vector3(0, 1.3, 0))
	q.collision_mask = 1
	if not space.intersect_shape(q, 1).is_empty():
		return false
	# Floor check — a ray straight down must hit something solid.
	var ray := PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 2.5, 0), pos + Vector3(0, -1.5, 0), 1)
	return not space.intersect_ray(ray).is_empty()


func _on_done() -> void:
	done += 1
	progress_changed.emit(done, total)
	if done >= required and total > 0:
		all_complete.emit()


func fraction() -> float:
	return float(done) / float(total) if total > 0 else 0.0
