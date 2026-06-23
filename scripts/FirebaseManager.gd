extends Node
## FirebaseManager (autoload singleton)
##
## Thin client for Firebase Realtime Database over the REST API. Works the same
## on desktop and in the HTML5 export (plain HTTPS GET/PUT/PATCH/DELETE on the
## `<path>.json` endpoints), so no native SDK or JS bridge is required.
##
## Realtime updates are delivered by POLLING: db_listen() registers a path that
## is re-fetched on an interval and re-emitted through db_value. That keeps the
## whole stack identical online/offline and avoids fragile SSE streaming. It's
## plenty for a small hide-and-seek lobby (a handful of players).
##
## SECURITY NOTE: the values below are *client* config (safe to ship) — the
## Realtime DB is protected by Security Rules, NOT by hiding this config.
## Replace the placeholders with your project's values, or drop a
## `firebase_config.json` next to the project so they aren't committed.

signal ready_changed(is_ready: bool)
signal db_value(path: String, value: Variant)
signal db_error(path: String, code: int)

# ---------------------------------------------------------------------------
# CONFIG — replace with your Firebase project credentials.
# ---------------------------------------------------------------------------
var CONFIG := {
	"apiKey": "YOUR_API_KEY",
	"authDomain": "panic-game.firebaseapp.com",
	"databaseURL": "https://panic-game-default-rtdb.firebaseio.com",
	"projectId": "panic-game",
	"storageBucket": "panic-game.appspot.com",
	"messagingSenderId": "YOUR_SENDER_ID",
	"appId": "YOUR_APP_ID",
}

var is_ready: bool = false
## False while CONFIG still holds placeholder credentials — all DB calls no-op
## so the full game is playable in the editor with NO Firebase project.
var enabled: bool = false
## Human-readable connection state for the lobby UI / debugging:
## "offline" | "connecting" | "online" | "auth_failed"
var status: String = "offline"

var _id_token: String = ""
var _refresh_token: String = ""
var _token_exp: float = 0.0          # unix time the id token expires
var _uid: String = ""
var _running_in_browser: bool = false

# Polling listeners: path -> { "interval": float, "accum": float }
var _listens: Dictionary = {}
var _inflight: Dictionary = {}       # path -> true while a poll GET is pending


func _ready() -> void:
	_running_in_browser = OS.has_feature("web")
	_load_config_override()
	enabled = CONFIG.get("apiKey", "") != "" and CONFIG.get("apiKey") != "YOUR_API_KEY"
	if enabled:
		status = "connecting"
		print("[FirebaseManager] Config loaded (%s) — authenticating…" % str(CONFIG.databaseURL))
		initialize()
	else:
		status = "offline"
		print("[FirebaseManager] Placeholder credentials — running OFFLINE (local play only).")


## Optionally load credentials from res:// so they are not baked into source.
func _load_config_override() -> void:
	var path := "res://firebase_config.json"
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			CONFIG[k] = parsed[k]


func initialize() -> void:
	_authenticate_anonymous()


# ─────────────────────────────────────────────────────────────────────────────
# AUTH (anonymous)
# ─────────────────────────────────────────────────────────────────────────────

func _authenticate_anonymous() -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + str(CONFIG.apiKey)
	var req := HTTPRequest.new()
	req.accept_gzip = false
	add_child(req)
	req.request_completed.connect(_on_auth_done.bind(req))
	var body := JSON.stringify({"returnSecureToken": true})
	var err := req.request(url, PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		push_warning("[FirebaseManager] auth request failed to start: %d" % err)


func _on_auth_done(_result: int, code: int, _headers: PackedStringArray,
		data: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if code < 200 or code >= 300:
		status = "auth_failed"
		var detail := data.get_string_from_utf8()
		push_warning("[FirebaseManager] anonymous auth failed (HTTP %d). Enable Anonymous sign-in in the Firebase console. %s" % [code, detail])
		ready_changed.emit(false)
		return
	var d: Variant = JSON.parse_string(data.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY or not d.has("idToken"):
		status = "auth_failed"
		push_warning("[FirebaseManager] auth response malformed.")
		ready_changed.emit(false)
		return
	_id_token = str(d["idToken"])
	_refresh_token = str(d.get("refreshToken", ""))
	_uid = str(d.get("localId", ""))
	_token_exp = Time.get_unix_time_from_system() + float(str(d.get("expiresIn", "3600")).to_int())
	is_ready = true
	status = "online"
	ready_changed.emit(true)
	print("[FirebaseManager] Online — anonymous auth OK (uid %s)." % _uid)


func _refresh_auth() -> void:
	if _refresh_token == "":
		return
	_token_exp = Time.get_unix_time_from_system() + 3600.0   # avoid re-firing while in flight
	var url := "https://securetoken.googleapis.com/v1/token?key=" + str(CONFIG.apiKey)
	var req := HTTPRequest.new()
	req.accept_gzip = false
	add_child(req)
	req.request_completed.connect(_on_refresh_done.bind(req))
	var body := "grant_type=refresh_token&refresh_token=" + _refresh_token.uri_encode()
	req.request(url, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]),
		HTTPClient.METHOD_POST, body)


func _on_refresh_done(_result: int, code: int, _headers: PackedStringArray,
		data: PackedByteArray, req: HTTPRequest) -> void:
	req.queue_free()
	if code < 200 or code >= 300:
		return
	var d: Variant = JSON.parse_string(data.get_string_from_utf8())
	if typeof(d) == TYPE_DICTIONARY and d.has("id_token"):
		_id_token = str(d["id_token"])
		_refresh_token = str(d.get("refresh_token", _refresh_token))
		_token_exp = Time.get_unix_time_from_system() + float(str(d.get("expires_in", "3600")).to_int())


# ─────────────────────────────────────────────────────────────────────────────
# POLLING DRIVER
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not enabled or not is_ready:
		return
	if _refresh_token != "" and Time.get_unix_time_from_system() > _token_exp - 300.0:
		_refresh_auth()
	for path in _listens:
		var L: Dictionary = _listens[path]
		L.accum += delta
		if L.accum >= L.interval and not _inflight.has(path):
			L.accum = 0.0
			_inflight[path] = true
			db_get(path)


# ─────────────────────────────────────────────────────────────────────────────
# Realtime DB helpers. Paths are relative to databaseURL, e.g. "rooms/AB/p/12".
# ─────────────────────────────────────────────────────────────────────────────

func db_put(path: String, value: Variant) -> void:
	_request(HTTPClient.METHOD_PUT, path, value)

func db_patch(path: String, value: Dictionary) -> void:
	_request(HTTPClient.METHOD_PATCH, path, value)

func db_get(path: String) -> void:
	_request(HTTPClient.METHOD_GET, path, null)

func db_delete(path: String) -> void:
	_request(HTTPClient.METHOD_DELETE, path, null)


## Subscribe to a path: it gets re-fetched every `interval` seconds and the
## result is re-emitted via db_value (so existing handlers just work).
func db_listen(path: String, interval := 0.5) -> void:
	if not _listens.has(path):
		_listens[path] = {"interval": interval, "accum": interval}   # poll ~immediately


func db_unlisten(path: String) -> void:
	_listens.erase(path)
	_inflight.erase(path)


func clear_listens() -> void:
	_listens.clear()
	_inflight.clear()


func _request(method: int, path: String, body: Variant) -> void:
	if not enabled:
		return   # offline mode — no network traffic
	var url := "%s/%s.json" % [CONFIG.databaseURL, path]
	if _id_token != "":
		url += "?auth=" + _id_token
	var req := HTTPRequest.new()
	req.accept_gzip = false
	add_child(req)
	req.request_completed.connect(
		func(_r, code, _h, data): _on_response(req, path, code, data))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var payload := "" if body == null else JSON.stringify(body)
	var err := req.request(url, headers, method, payload)
	if err != OK:
		_inflight.erase(path)
		db_error.emit(path, err)
		req.queue_free()


func _on_response(req: HTTPRequest, path: String, code: int, data: PackedByteArray) -> void:
	req.queue_free()
	_inflight.erase(path)
	if code < 200 or code >= 300:
		# code 0 in-browser usually means the request was blocked (CORS/COEP).
		push_warning("[FirebaseManager] DB %s -> HTTP %d %s" % [path, code, data.get_string_from_utf8()])
		db_error.emit(path, code)
		return
	var text := data.get_string_from_utf8()
	var value: Variant = JSON.parse_string(text) if text != "" else null
	db_value.emit(path, value)
