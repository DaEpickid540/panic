extends Node
## PositionSync
##
## Streams the local player's transform to Firebase every 100 ms and applies
## incoming transforms to RemotePlayer avatars (which interpolate). Designed to
## stay light for 4-12 players: one PATCH per tick (own node only), reads are
## fanned out by FirebaseManager's listener.
##
## DB schema:
##   games/<gameId>/positions/<peerId>: { p:[x,y,z], r:float, role:int, t:int }
##
## Disconnect handling: a peer whose node disappears (null) OR goes stale
## (no update for STALE_MS) is removed from the scene.

const SYNC_HZ := 10.0            # 100 ms
const STALE_MS := 5000

@export var spawner_path: NodePath = ^"../PlayerSpawner"

var _spawner: Node
var _accum := 0.0
var _hunter_audio: Node       # optional Hunter3DAudio for footsteps


func _ready() -> void:
	_spawner = get_node_or_null(spawner_path)
	FirebaseManager.db_value.connect(_on_db_value)
	if GameStateSync.game_id != "":
		FirebaseManager.db_listen("games/%s/positions" % GameStateSync.game_id)


func set_hunter_audio(node: Node) -> void:
	_hunter_audio = node


func _process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / SYNC_HZ:
		return
	_accum = 0.0
	_push_local()
	_cull_stale()


func _push_local() -> void:
	if _spawner == null:
		return
	var p = _spawner.local_player
	if p == null or not is_instance_valid(p):
		return
	if GameStateSync.game_id == "":
		return
	FirebaseManager.db_patch(
		"games/%s/positions/%d" % [GameStateSync.game_id, NetworkManager.local_peer_id],
		{
			"p": [p.global_position.x, p.global_position.y, p.global_position.z],
			"r": p.rotation.y,
			"role": GameManager.get_local_role(),
			"t": Time.get_ticks_msec(),
		}
	)


func _on_db_value(path: String, value: Variant) -> void:
	if GameStateSync.game_id == "":
		return
	if not path.begins_with("games/%s/positions" % GameStateSync.game_id):
		return
	if typeof(value) != TYPE_DICTIONARY:
		return
	# Whole-map update.
	for k in value:
		_apply_peer(int(k), value[k])


func _apply_peer(peer_id: int, data: Variant) -> void:
	if peer_id == NetworkManager.local_peer_id or typeof(data) != TYPE_DICTIONARY:
		return
	if not data.has("p"):
		return
	var arr: Array = data["p"]
	var pos := Vector3(arr[0], arr[1], arr[2])
	var yaw := float(data.get("r", 0.0))
	var role := int(data.get("role", GameManager.Role.HUNTED))

	var rp = _spawner.get_remote(peer_id)
	if rp == null:
		rp = _spawner.spawn_remote(peer_id, role)
	rp.receive(pos, yaw)

	# Feed the hunter's 3D audio (footsteps from moving sources).
	if _hunter_audio and GameManager.get_local_role() == GameManager.Role.HUNTER:
		_hunter_audio.update(get_process_delta_time(), {peer_id: pos})


func _cull_stale() -> void:
	if _spawner == null:
		return
	var now := Time.get_ticks_msec()
	for peer_id in _spawner.remotes.keys():
		var rp = _spawner.remotes[peer_id]
		if rp.last_seen_ms > 0 and now - rp.last_seen_ms > STALE_MS:
			_spawner.despawn_remote(peer_id)
			NetworkManager.remove_peer(peer_id)
