extends Node
## GameManager — the brain of the match. (autoload singleton)
##
## Phases: LOBBY → COUNTDOWN → HUNTING → END

signal phase_changed(new_phase: int, old_phase: int)
signal countdown_started(seconds: int)
signal countdown_tick(seconds_left: int)
signal hunting_started()
signal hunting_tick(seconds_left: int)
signal game_ended(results: Dictionary)
signal role_assigned(peer_id: int, role: int)
signal player_captured(peer_id: int, by_peer_id: int)
signal player_revived(peer_id: int)

enum Phase { LOBBY, COUNTDOWN, HUNTING, END }
enum Role  { HUNTER, HUNTED, GHOST }
enum Mode  { STANDARD, PARKOUR, INFECTION }

var game_mode: int = Mode.STANDARD

const ROLE_NAMES := {
	Role.HUNTER: "hunter",
	Role.HUNTED: "hunted",
	Role.GHOST:  "ghost",
}

const COUNTDOWN_SECONDS     := 5
const MIN_ROUND_MINUTES     := 3
const MAX_ROUND_MINUTES     := 20
const DEFAULT_ROUND_MINUTES := 5

var current_phase: int = Phase.LOBBY
var round_minutes: int = DEFAULT_ROUND_MINUTES

## Endgame escalation 0..1 (driven by GameController from time + objectives).
## Ramps the hunter's speed and the scan frequency as the round heats up.
var tension: float = 0.0

func hunter_speed_mult() -> float:
	return 1.0 + 0.30 * clampf(tension, 0.0, 1.0)

var selected_map:    String = "Urban"
const WEAPONS := ["knife", "cleaver", "axe", "katana", "sword", "hammer", "pickaxe", "baseballbat"]
var selected_weapon: String = "knife"

var local_display_name: String = "PLAYER"
var local_color: Color = Color(0.82, 0.82, 0.9)

var role_preference: int = -1   # -1=AUTO, 0=HUNTER, 1=HUNTED

var settings_sensitivity: float = 1.0
var settings_master: float = 1.0
var settings_fog: float = 1.0
var debug_overlay: bool = false
var killer_count: int = 1
var gen_count: int = 6
var gen_required: int = 5

## Set to true in the Godot editor (or from the console) to silence all
## jumpscares during development — won't get committed by accident.
var dev_disable_jumpscares: bool = false

const SETTINGS_PATH := "user://settings.cfg"
const STATS_PATH    := "user://stats.cfg"


func weapon_path() -> String:
	return "res://assets/models/weapons/%s.fbx" % selected_weapon

var roles: Dictionary          = {}
var capture_times: Dictionary  = {}
var capture_counts: Dictionary = {}
var revived: Dictionary        = {}

var _phase_timer: Timer
var _seconds_left: int = 0
var _is_host: bool = true


func _ready() -> void:
	_phase_timer = Timer.new()
	_phase_timer.one_shot   = false
	_phase_timer.wait_time  = 1.0
	_phase_timer.timeout.connect(_on_tick)
	add_child(_phase_timer)
	load_settings()
	game_ended.connect(_record_stats)


# ─────────────────────────────────────────────────────────────────────────────
# SETTINGS
# ─────────────────────────────────────────────────────────────────────────────

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		settings_sensitivity = float(cfg.get_value("controls", "sensitivity", 1.0))
		settings_master      = float(cfg.get_value("audio",    "master",      1.0))
		settings_fog         = float(cfg.get_value("video",    "fog",         1.0))
		debug_overlay        = bool(cfg.get_value("debug",     "overlay",     false))
		killer_count         = int(cfg.get_value("match",      "killers",     1))
	AudioManager.set_master_volume(settings_master)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "sensitivity", settings_sensitivity)
	cfg.set_value("audio",    "master",      settings_master)
	cfg.set_value("video",    "fog",         settings_fog)
	cfg.set_value("debug",    "overlay",     debug_overlay)
	cfg.set_value("match",    "killers",     killer_count)
	cfg.save(SETTINGS_PATH)

func set_sensitivity(value: float) -> void:
	settings_sensitivity = clampf(value, 0.2, 3.0)
	save_settings()

func set_master_volume(value: float) -> void:
	settings_master = clampf(value, 0.0, 1.0)
	AudioManager.set_master_volume(settings_master)
	save_settings()


# ─────────────────────────────────────────────────────────────────────────────
# STATS
# ─────────────────────────────────────────────────────────────────────────────

func _record_stats(results: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(STATS_PATH)
	var games: int      = int(cfg.get_value("stats", "games_played",   0)) + 1
	var best: int       = int(cfg.get_value("stats", "best_survival",  0))
	var total_caps: int = int(cfg.get_value("stats", "total_captures", 0))
	var me := NetworkManager.local_peer_id
	for s in results.get("stats", []):
		if s.get("peer_id") == me:
			best       = maxi(best, int(s.get("survival_time", 0)))
			total_caps += int(s.get("captures", 0))
	cfg.set_value("stats", "games_played",   games)
	cfg.set_value("stats", "best_survival",  best)
	cfg.set_value("stats", "total_captures", total_caps)
	cfg.save(STATS_PATH)

func get_best_survival() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(STATS_PATH) == OK:
		return int(cfg.get_value("stats", "best_survival", 0))
	return 0


# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────

func set_round_minutes(minutes: int) -> void:
	round_minutes = clampi(minutes, MIN_ROUND_MINUTES, MAX_ROUND_MINUTES)

func set_host(is_host: bool) -> void:
	_is_host = is_host

func get_round_seconds() -> int:
	return round_minutes * 60


# ─────────────────────────────────────────────────────────────────────────────
# PHASE STATE MACHINE
# ─────────────────────────────────────────────────────────────────────────────

func force_phase(phase: int) -> void:
	_enter_phase(phase)

func start_game() -> void:
	if current_phase != Phase.LOBBY:
		return
	# Only the host drives the match start; joined clients follow via GameStateSync.
	if not _is_host:
		return
	start_countdown()

func start_countdown() -> void:
	_seconds_left = COUNTDOWN_SECONDS
	_enter_phase(Phase.COUNTDOWN)
	countdown_started.emit(COUNTDOWN_SECONDS)
	_phase_timer.start()

func start_hunting() -> void:
	if _is_host:
		assign_roles(NetworkManager.get_peer_ids())
	_seconds_left = get_round_seconds()
	tension = 0.0
	_enter_phase(Phase.HUNTING)
	hunting_started.emit()
	_phase_timer.start()

func end_game(reason: String = "timer") -> void:
	_phase_timer.stop()
	_enter_phase(Phase.END)
	game_ended.emit(build_results(reason))

func return_to_lobby() -> void:
	_phase_timer.stop()
	roles.clear()
	capture_times.clear()
	capture_counts.clear()
	force_phase(Phase.LOBBY)

func _enter_phase(phase: int) -> void:
	if phase == current_phase:
		return
	var old := current_phase
	current_phase = phase
	phase_changed.emit(phase, old)
	if _is_host:
		GameStateSync.push_phase(phase, _seconds_left)

func _on_tick() -> void:
	_seconds_left -= 1
	match current_phase:
		Phase.COUNTDOWN:
			countdown_tick.emit(_seconds_left)
			if _seconds_left <= 0:
				start_hunting()
		Phase.HUNTING:
			hunting_tick.emit(_seconds_left)
			if _is_host:
				GameStateSync.push_time_remaining(_seconds_left)
			if _seconds_left <= 0:
				end_game("timer")

func get_seconds_left() -> int:
	return _seconds_left

func apply_remote_time(seconds_left: int) -> void:
	if not _is_host:
		_seconds_left = seconds_left


# ─────────────────────────────────────────────────────────────────────────────
# ROLES
# ─────────────────────────────────────────────────────────────────────────────

func assign_roles(peer_ids: Array) -> void:
	roles.clear()
	capture_times.clear()
	capture_counts.clear()
	revived.clear()
	if peer_ids.is_empty():
		return
	var pool := peer_ids.duplicate()
	pool.shuffle()
	var want_killers := clampi(killer_count, 1, maxi(1, pool.size() - 1))
	var hunter_ids: Array[int] = []
	var humans := pool.filter(func(id): return not NetworkManager.is_bot(id))
	var bots   := pool.filter(func(id): return NetworkManager.is_bot(id))

	var local := NetworkManager.local_peer_id
	if local in peer_ids and role_preference == Role.HUNTER:
		hunter_ids.append(local)
	elif local in peer_ids and role_preference == Role.HUNTED:
		pass

	for h in humans:
		if hunter_ids.size() >= want_killers:
			break
		if h not in hunter_ids and h != local:
			hunter_ids.append(h)
	for b in bots:
		if hunter_ids.size() >= want_killers:
			break
		if b not in hunter_ids:
			hunter_ids.append(b)
	if hunter_ids.is_empty():
		hunter_ids.append(pool[0])

	for id in peer_ids:
		var r: int = Role.HUNTER if id in hunter_ids else Role.HUNTED
		roles[id] = r
		if r == Role.HUNTER:
			capture_counts[id] = 0
		role_assigned.emit(id, r)
	GameStateSync.push_roles(roles)

func apply_remote_roles(remote_roles: Dictionary) -> void:
	for id in remote_roles:
		var r: int = remote_roles[id]
		if roles.get(id) != r:
			roles[id] = r
			role_assigned.emit(id, r)

func get_role(peer_id: int) -> int:
	return roles.get(peer_id, Role.HUNTED)

func get_local_role() -> int:
	return get_role(NetworkManager.local_peer_id)


const GRIEF_TARGET_CD := 12.0
var _grief_history: Dictionary = {}

func grief_runner(node: Object, ghost_id: int, dmg: int, stun: float, hit_type: String = "melee") -> void:
	if node == null or not is_instance_valid(node):
		return
	var pid: int = node.peer_id if ("peer_id" in node) else -1
	if ghost_id >= 0 and pid >= 0 and get_role(ghost_id) == Role.GHOST:
		var key := "%d_%d" % [ghost_id, pid]
		var now := Time.get_unix_time_from_system()
		if _grief_history.has(key) and now - _grief_history[key] < GRIEF_TARGET_CD:
			return
		_grief_history[key] = now
	if pid != -1 and pid != NetworkManager.local_peer_id and not NetworkManager.is_bot(pid):
		GameStateSync.push_grief(pid, ghost_id, dmg, stun)
		return
	if dmg > 0 and node.has_method("take_damage"):
		node.take_damage(dmg, ghost_id, hit_type)
	if stun > 0.0 and node.has_method("apply_stun"):
		node.apply_stun(stun)


func capture_player(peer_id: int, by_peer_id: int) -> void:
	if get_role(peer_id) != Role.HUNTED:
		return
	var new_role: int
	if game_mode == Mode.INFECTION:
		new_role = Role.HUNTER
		capture_counts[peer_id] = 0
	else:
		new_role = Role.GHOST
	roles[peer_id] = new_role
	capture_times[peer_id] = get_round_seconds() - _seconds_left
	if capture_counts.has(by_peer_id):
		capture_counts[by_peer_id] += 1
	role_assigned.emit(peer_id, new_role)
	player_captured.emit(peer_id, by_peer_id)
	AudioManager.play_capture_scream()
	GameStateSync.push_capture(peer_id, by_peer_id)
	if _is_host:
		GameStateSync.push_roles(roles)
		_check_end_condition()

func revive_player(peer_id: int) -> void:
	if get_role(peer_id) != Role.GHOST:
		return
	roles[peer_id] = Role.HUNTED
	revived[peer_id] = true
	role_assigned.emit(peer_id, Role.HUNTED)
	player_revived.emit(peer_id)
	if _is_host:
		GameStateSync.push_roles(roles)

func _check_end_condition() -> void:
	var hunted_left := 0
	for id in roles:
		if roles[id] == Role.HUNTED:
			hunted_left += 1
	if hunted_left == 0:
		end_game("all_captured")


# ─────────────────────────────────────────────────────────────────────────────
# RESULTS
# ─────────────────────────────────────────────────────────────────────────────

func build_results(reason: String = "timer") -> Dictionary:
	var survivors: Array = []
	var stats:     Array = []
	var longest := 0
	for id in roles:
		var survived: int     = capture_times.get(id, get_round_seconds() - _seconds_left)
		var role_name: String = ROLE_NAMES[roles[id]]
		if roles[id] == Role.HUNTED:
			survivors.append(id)
			survived = get_round_seconds() - _seconds_left
		longest = maxi(longest, survived)
		stats.append({
			"peer_id":       id,
			"name":          NetworkManager.get_peer_name(id),
			"role":          role_name,
			"survival_time": survived,
			"captures":      capture_counts.get(id, 0),
		})
	return {
		"reason":           reason,
		"survivors":        survivors,
		"survivor_count":   survivors.size(),
		"longest_survival": longest,
		"stats":            stats,
	}
