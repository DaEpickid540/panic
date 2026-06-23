extends Node3D
## ObjectiveController — scatters the hider GENERATORS for a match and reports
## progress. When all are powered it fires `all_complete` (the hiders escape).

signal all_complete
signal progress_changed(done: int, total: int)

const GEN_SCRIPT := preload("res://scripts/Generator.gd")

var total := 0
var required := 0
var done := 0


func setup(spawner: Node, bound: float, count: int, need: int = -1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var b := maxf(bound - 8.0, 12.0)
	var placed := 0
	var attempts := 0
	var used: Array[Vector3] = []
	while placed < count and attempts < 400:
		attempts += 1
		var pos := Vector3(rng.randf_range(-b, b), 0.0, rng.randf_range(-b, b))
		if pos.length() < 14.0:
			continue
		var too_close := false
		for u in used:
			if u.distance_to(pos) < 14.0:
				too_close = true
				break
		if too_close:
			continue
		used.append(pos)
		var g: Node3D = GEN_SCRIPT.new()
		add_child(g)
		g.global_position = pos
		g.setup(spawner)
		g.completed.connect(_on_done)
		placed += 1
	total = placed
	required = need if need > 0 else total
	progress_changed.emit(done, total)


func _on_done() -> void:
	done += 1
	progress_changed.emit(done, total)
	if done >= required and total > 0:
		all_complete.emit()


func fraction() -> float:
	return float(done) / float(total) if total > 0 else 0.0
