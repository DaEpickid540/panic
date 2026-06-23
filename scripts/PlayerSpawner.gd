extends Node3D
## PlayerSpawner
##
## Owns the live avatars in a match: one local player (role-configured) plus a
## RemotePlayer per other peer. Spawns at the map's spawn points:
##   hunter -> centre, hunted/ghost -> random perimeter point.
##
## Visual rules:
##   Hunter — FPS camera, no visible body (handled in PlayerController).
##   Hunted — solid low-poly capsule, isometric.
##   Ghost  — semi-transparent, isometric.

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const REMOTE_SCENE := preload("res://scenes/RemotePlayer.tscn")

var local_player: CharacterBody3D
var remotes: Dictionary = {}     # peer_id -> RemotePlayer

var _hunter_spawn: Vector3 = Vector3.ZERO
var _perimeter: Array = []
var _perimeter_cursor := 0


## Read spawn points from a map's "SpawnPoints" node. Call after the map is
## instanced (maps are loaded at runtime by GameController).
func bind_spawns(root: Node) -> void:
	_perimeter.clear()
	_hunter_spawn = Vector3.ZERO
	if root == null:
		return
	for child in root.get_children():
		if child.name.to_lower().contains("hunter") or child.name.to_lower() == "center":
			_hunter_spawn = child.global_position
		else:
			_perimeter.append(child.global_position)
	_perimeter.shuffle()


func spawn_local(role: int) -> CharacterBody3D:
	if local_player and is_instance_valid(local_player):
		local_player.queue_free()
	local_player = PLAYER_SCENE.instantiate()
	local_player.is_local = true
	local_player.role = role
	add_child(local_player)
	local_player.global_position = _spawn_for(role)
	local_player.configure_for_role(role)
	return local_player


func spawn_remote(peer_id: int, role: int) -> Node3D:
	if remotes.has(peer_id):
		remotes[peer_id].apply_role(role)
		return remotes[peer_id]
	var rp := REMOTE_SCENE.instantiate()
	add_child(rp)
	rp.setup(peer_id, role)
	rp.global_position = _spawn_for(role)
	rp.global_position.y = 0.0   # feet on the floor (no physics on remotes)
	# Offline test players wander on their own so there's something to hunt.
	if NetworkManager.is_bot(peer_id):
		rp.enable_bot(_arena_bound())
	remotes[peer_id] = rp
	return rp


func despawn_remote(peer_id: int) -> void:
	if remotes.has(peer_id):
		remotes[peer_id].queue_free()
		remotes.erase(peer_id)


func get_remote(peer_id: int) -> Node3D:
	return remotes.get(peer_id)


## Approximate arena half-extent from the perimeter spawn ring, so bots stay
## inside the walls regardless of map size.
func _arena_bound() -> float:
	var b := 20.0
	for p in _perimeter:
		b = maxf(b, maxf(absf(p.x), absf(p.z)))
	return b


func _spawn_for(role: int) -> Vector3:
	if role == GameManager.Role.HUNTER:
		return _hunter_spawn
	if _perimeter.is_empty():
		return Vector3(randf_range(-20, 20), 1, randf_range(-20, 20))
	var p: Vector3 = _perimeter[_perimeter_cursor % _perimeter.size()]
	_perimeter_cursor += 1
	return p
