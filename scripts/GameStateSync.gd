extends Node
## GameStateSync (autoload singleton)
##
## Mirrors *match* state (phase / timeRemaining / roles / captures) between the
## local GameManager and Firebase Realtime DB. High-frequency *position* data
## lives in PositionSync.gd, not here.
##
## Realtime DB schema:
##   games/<gameId>/
##     phase:          int                (GameManager.Phase)
##     timeRemaining:  int                (seconds)
##     map:            string
##     playerRoles/<peerId>: int          (GameManager.Role)
##     captures/<peerId>:    { by:int, at:int }
##
## Race-safety: the HOST is the single writer for phase/time/roles. Clients
## only ever READ those and call apply_* on GameManager — they never write
## them back, so there is no write-write race. Each client owns only its own
## position node (handled in PositionSync).

signal remote_phase(phase: int, time_remaining: int)
signal remote_roles(roles: Dictionary)
signal remote_capture(peer_id: int, by_peer_id: int)
signal remote_grab(hunted_id: int, ghost_id: int)
signal remote_escape(hunted_id: int)
signal remote_reveal(ghost_id: int)
## A ghost's lightning / fake-killer / grab landed on a runner. Fires on every
## client; the targeted runner's own client applies the damage + knockdown.
signal remote_grief(target_id: int, ghost_id: int, dmg: int, stun: float)

var game_id: String = ""
var _applying_remote: bool = false       # guards against echo loops


func _ready() -> void:
	FirebaseManager.db_value.connect(_on_db_value)


signal lobby_settings(settings: Dictionary)

func join_room(id: String) -> void:
	game_id = id
	if game_id == "":
		return
	FirebaseManager.db_listen(_path("phase"))
	FirebaseManager.db_listen(_path("timeRemaining"))
	FirebaseManager.db_listen(_path("playerRoles"))
	FirebaseManager.db_listen(_path("captures"))
	FirebaseManager.db_listen(_path("grabs"))
	FirebaseManager.db_listen(_path("reveals"))
	FirebaseManager.db_listen(_path("griefs"))
	FirebaseManager.db_listen(_path("lobby"), 2.0)


## --- Lobby settings sync (host → joiners) --------------------------------

func push_lobby_settings() -> void:
	if not _can_write():
		return
	FirebaseManager.db_put(_path("lobby"), {
		"map": GameManager.selected_map,
		"weapon": GameManager.selected_weapon,
		"time": GameManager.round_minutes,
		"killers": GameManager.killer_count,
	})


## --- Write side (host only; no-ops offline) ------------------------------

func push_phase(phase: int, time_remaining: int) -> void:
	if not _can_write():
		return
	FirebaseManager.db_patch(_root(), {
		"phase": phase,
		"timeRemaining": time_remaining,
		"map": GameManager.selected_map,
	})


func push_time_remaining(seconds: int) -> void:
	if not _can_write():
		return
	FirebaseManager.db_put(_path("timeRemaining"), seconds)


func push_roles(roles: Dictionary) -> void:
	if not _can_write():
		return
	var out := {}
	for k in roles:
		out[str(k)] = roles[k]
	FirebaseManager.db_put(_path("playerRoles"), out)


func push_capture(peer_id: int, by_peer_id: int) -> void:
	if not _can_write():
		return
	FirebaseManager.db_patch(_path("captures/%d" % peer_id), {
		"by": by_peer_id,
		"at": Time.get_unix_time_from_system(),
	})


## Ghost grabs a hunted player. Writes the grip so the hunted client reacts.
func push_grab(hunted_id: int, ghost_id: int) -> void:
	if game_id == "":
		return
	FirebaseManager.db_patch(_path("grabs/%d" % hunted_id), {
		"by": ghost_id,
		"at": Time.get_unix_time_from_system(),
	})


## Hunted escaped the grip — clear it.
func push_escape(hunted_id: int) -> void:
	if game_id == "":
		return
	FirebaseManager.db_delete(_path("grabs/%d" % hunted_id))


## Ghost reveal event (proximity scream) — drives directional audio + UI.
func push_ghost_reveal(ghost_id: int) -> void:
	if game_id == "":
		return
	FirebaseManager.db_patch(_path("reveals/%d" % ghost_id), {
		"at": Time.get_unix_time_from_system(),
	})


## A grief hit (lightning / fake killer / grab) aimed at a HUMAN runner so it
## lands on their own client. `n` forces the value to change every write so the
## listener always fires.
func push_grief(target_id: int, ghost_id: int, dmg: int, stun: float) -> void:
	if game_id == "":
		return
	FirebaseManager.db_patch(_path("griefs/%d" % target_id), {
		"by":   ghost_id,
		"dmg":  dmg,
		"stun": stun,
		"at":   Time.get_unix_time_from_system(),
		"n":    randi(),
	})


## --- Read side -----------------------------------------------------------

func _on_db_value(path: String, value: Variant) -> void:
	if game_id == "" or not path.begins_with("games/%s" % game_id):
		return
	if value == null:
		return
	_applying_remote = true

	if path.ends_with("/lobby") and typeof(value) == TYPE_DICTIONARY:
		lobby_settings.emit(value)
		return

	if path.ends_with("/phase"):
		var seconds := GameManager.get_seconds_left()
		remote_phase.emit(int(value), seconds)
		GameManager.force_phase(int(value))
	elif path.ends_with("/timeRemaining"):
		GameManager.apply_remote_time(int(value))
	elif path.ends_with("/playerRoles") and typeof(value) == TYPE_DICTIONARY:
		var parsed := {}
		for k in value:
			parsed[int(k)] = int(value[k])
		remote_roles.emit(parsed)
		GameManager.apply_remote_roles(parsed)
	elif path.find("/captures") != -1 and typeof(value) == TYPE_DICTIONARY:
		_apply_captures(value)
	elif path.find("/grabs") != -1 and typeof(value) == TYPE_DICTIONARY:
		_apply_grabs(value)
	elif path.find("/griefs") != -1 and typeof(value) == TYPE_DICTIONARY:
		_apply_griefs(value)
	elif path.find("/reveals") != -1 and typeof(value) == TYPE_DICTIONARY:
		for k in value:
			remote_reveal.emit(int(k))

	_applying_remote = false


func _apply_grabs(value: Dictionary) -> void:
	for k in value:
		var entry = value[k]
		if typeof(entry) == TYPE_DICTIONARY and entry.has("by"):
			remote_grab.emit(int(k), int(entry["by"]))


func _apply_griefs(value: Dictionary) -> void:
	# Only act on FRESH griefs so we don't replay stale ones when (re)joining.
	var now := Time.get_unix_time_from_system()
	for k in value:
		var e = value[k]
		if typeof(e) == TYPE_DICTIONARY and e.has("stun"):
			if absf(now - float(e.get("at", 0.0))) < 3.0:
				remote_grief.emit(int(k), int(e.get("by", -1)),
					int(e.get("dmg", 0)), float(e.get("stun", 0.0)))


func _apply_captures(value: Dictionary) -> void:
	# value may be the whole captures map or a single entry depending on path.
	for k in value:
		var entry = value[k]
		if typeof(entry) == TYPE_DICTIONARY and entry.has("by"):
			var peer_id := int(k)
			remote_capture.emit(peer_id, int(entry["by"]))
			if GameManager.get_role(peer_id) == GameManager.Role.HUNTED:
				GameManager.capture_player(peer_id, int(entry["by"]))


func _can_write() -> bool:
	return game_id != "" and not _applying_remote


func _root() -> String:
	return "games/%s" % game_id


func _path(sub: String) -> String:
	return "games/%s/%s" % [game_id, sub]
