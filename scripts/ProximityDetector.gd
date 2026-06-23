extends Node
## ProximityDetector  (world node, configured by GameController)
##
## Computes distances between the local player and remote avatars each physics
## frame and answers "who is near?". Used by:
##   - GhostController: nearest hunted within 3 m (grab range).
##   - HUD indicators:  hunter within 1 m of a hunted (danger pulse).
##
## Distances come straight from synced transforms (no extra physics queries),
## so this scales fine for 4-12 players.

signal hunted_in_grab_range(peer_id: int, in_range: bool)

const GHOST_GRAB_RANGE := 3.0
const HUNTER_CAPTURE_RANGE := 1.0

var spawner: Node
var _grab_target := -1


func setup(p_spawner: Node) -> void:
	spawner = p_spawner


func _physics_process(_delta: float) -> void:
	if spawner == null or spawner.local_player == null:
		return
	if GameManager.get_local_role() == GameManager.Role.GHOST:
		_update_ghost_grab_target()


func _update_ghost_grab_target() -> void:
	var nearest := nearest_remote_of_role(GameManager.Role.HUNTED, GHOST_GRAB_RANGE)
	var new_target: int = nearest.get("peer_id", -1)
	if new_target != _grab_target:
		if _grab_target != -1:
			hunted_in_grab_range.emit(_grab_target, false)
		_grab_target = new_target
		if new_target != -1:
			hunted_in_grab_range.emit(new_target, true)


## Returns { peer_id, distance } of the closest remote with `role` within
## `max_range`, or {} if none.
func nearest_remote_of_role(role: int, max_range: float) -> Dictionary:
	var origin: Vector3 = spawner.local_player.global_position
	var best := {}
	var best_dist := max_range
	for peer_id in spawner.remotes:
		var rp = spawner.remotes[peer_id]
		if rp.role != role:
			continue
		var d: float = origin.distance_to(rp.global_position)
		if d <= best_dist:
			best_dist = d
			best = {"peer_id": peer_id, "distance": d}
	return best


func current_grab_target() -> int:
	return _grab_target
