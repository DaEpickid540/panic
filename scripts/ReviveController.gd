extends Node
## ReviveController — lets a living HUNTED revive a nearby (invisible) GHOST by
## staying close for 5 seconds. The ghost comes back as a slower hunted.

signal revive_progress(target_id: int, t01: float)

const REVIVE_RANGE := 3.5
const REVIVE_TIME := 5.0

var _spawner: Node
var _progress := 0.0
var _target := -1


func setup(spawner: Node) -> void:
	_spawner = spawner
	_reset()


func _physics_process(delta: float) -> void:
	if _spawner == null or GameManager.current_phase != GameManager.Phase.HUNTING:
		return
	if GameManager.get_local_role() != GameManager.Role.HUNTED:
		_reset()
		return
	var lp = _spawner.local_player
	if lp == null or not is_instance_valid(lp):
		_reset()
		return
	var g := _nearest_ghost(lp.global_position)
	if g == -1:
		_reset()
		return
	if g != _target:
		_target = g
		_progress = 0.0
	_progress += delta
	revive_progress.emit(_target, clampf(_progress / REVIVE_TIME, 0.0, 1.0))
	if _progress >= REVIVE_TIME:
		GameManager.revive_player(_target)
		_reset()


func _nearest_ghost(pos: Vector3) -> int:
	var best := -1
	var bd := REVIVE_RANGE
	for id in _spawner.remotes:
		var rp = _spawner.remotes[id]
		if rp.role == GameManager.Role.GHOST:
			var d: float = pos.distance_to(rp.global_position)
			if d < bd:
				bd = d
				best = id
	return best


func _reset() -> void:
	if _target != -1:
		revive_progress.emit(-1, 0.0)
	_target = -1
	_progress = 0.0
