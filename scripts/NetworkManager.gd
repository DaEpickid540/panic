extends Node
## NetworkManager (autoload singleton)
##
## Manages the local player's identity and the roster of peers in the room.
## Firebase Realtime DB is the transport (see GameStateSync / PositionSync),
## so this layer is intentionally light — no ENet/high-level multiplayer.

signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal local_id_assigned(peer_id: int)

const HB_INTERVAL := 3.0       # seconds between presence heartbeats
const PRESENCE_STALE := 9.0    # drop a remote peer we haven't heard from in this long

var local_peer_id: int = -1
var peers: Dictionary = {}   # peer_id -> { name: String, joined_at: int }
var current_room: String = ""
var _bot_ids: Dictionary = {}   # peer_id -> true (locally-simulated test players)
var _in_room := false
var _hb_accum := 0.0


func is_bot(peer_id: int) -> bool:
	return _bot_ids.has(peer_id)


func _ready() -> void:
	# Stable-ish client id; replace with hashed Firebase auth uid later.
	local_peer_id = abs(int(Time.get_unix_time_from_system() * 1000.0)) % 1000000
	register_peer(local_peer_id, "You")
	local_id_assigned.emit(local_peer_id)
	FirebaseManager.db_value.connect(_on_db_value)


func host_room() -> String:
	current_room = _generate_room_code()
	GameManager.set_host(true)
	GameStateSync.join_room(current_room)
	_enter_room()
	return current_room


func join_room(room_id: String, display_name: String = "Player") -> void:
	current_room = room_id
	GameManager.set_host(false)
	peers[local_peer_id]["name"] = display_name
	GameStateSync.join_room(room_id)
	_enter_room()


# ─────────────────────────────────────────────────────────────────────────────
# PRESENCE / PEER DISCOVERY  (Firebase room roster)
# ─────────────────────────────────────────────────────────────────────────────

## Register ourselves in the room and start watching the player roster.
func _enter_room() -> void:
	if current_room == "":
		return
	_in_room = true
	_hb_accum = 0.0
	_write_presence()
	FirebaseManager.db_listen(_players_path(), 1.0)


## Remove ourselves from the room (call when leaving back to the lobby).
func leave_room() -> void:
	if not _in_room:
		return
	_in_room = false
	FirebaseManager.db_delete("%s/%d" % [_players_path(), local_peer_id])
	FirebaseManager.db_unlisten(_players_path())
	# Forget remote humans; keep self + local bots.
	for pid in peers.keys():
		if pid != local_peer_id and not is_bot(pid):
			remove_peer(pid)
	current_room = ""


func _process(delta: float) -> void:
	if not _in_room:
		return
	_hb_accum += delta
	if _hb_accum >= HB_INTERVAL:
		_hb_accum = 0.0
		_write_presence()


func _write_presence() -> void:
	FirebaseManager.db_patch("%s/%d" % [_players_path(), local_peer_id], {
		"name": get_peer_name(local_peer_id),
		"t": Time.get_unix_time_from_system(),
	})


func _on_db_value(path: String, value: Variant) -> void:
	if not _in_room or path != _players_path() or typeof(value) != TYPE_DICTIONARY:
		return
	var now := Time.get_unix_time_from_system()
	var seen := {}
	# Register/refresh present remote players.
	for k in value:
		var pid := int(k)
		var entry = value[k]
		var t := float(entry.get("t", 0.0)) if typeof(entry) == TYPE_DICTIONARY else 0.0
		if now - t > PRESENCE_STALE:
			continue   # treat stale entries as gone
		seen[pid] = true
		if pid != local_peer_id and not peers.has(pid):
			register_peer(pid, str(entry.get("name", "Player")))
	# Drop remote humans who are no longer present.
	for pid in peers.keys():
		if pid == local_peer_id or is_bot(pid):
			continue
		if not seen.has(pid):
			remove_peer(pid)


func _players_path() -> String:
	return "games/%s/players" % current_room


func register_peer(peer_id: int, display_name: String) -> void:
	if peers.has(peer_id):
		return
	peers[peer_id] = {"name": display_name, "joined_at": Time.get_ticks_msec()}
	peer_joined.emit(peer_id)


func remove_peer(peer_id: int) -> void:
	if peer_id == local_peer_id:
		return
	_bot_ids.erase(peer_id)
	if peers.erase(peer_id):
		peer_left.emit(peer_id)


func get_peer_ids() -> Array:
	return peers.keys()


func get_peer_count() -> int:
	return peers.size()


func get_peer_name(peer_id: int) -> String:
	return peers.get(peer_id, {}).get("name", "Player %d" % peer_id)


## Editor/testing helper: fake N extra players so phase + role logic can be
## exercised solo with F5. Call from LobbyUI's "Add Bot" button.
func add_test_peer(display_name: String = "") -> int:
	var id := randi() % 900000 + 100000
	_bot_ids[id] = true
	register_peer(id, display_name if display_name != "" else "Bot %d" % (peers.size()))
	return id


func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in 6:
		code += CHARS[randi() % CHARS.length()]
	return code
