extends Node3D
## GameController — orchestrates a live match.
## Loads the map, spawns avatars, and manages all horror entities
## (shadow entities, mirages, lockers) alongside the existing pickups.

const MAP_SCENES := {
	"Urban":     "res://scenes/maps/Urban.tscn",
	"Forest":    "res://scenes/maps/Forest.tscn",
	"Warehouse": "res://scenes/maps/Warehouse.tscn",
	"Mansion":   "res://scenes/maps/Mansion.tscn",
	"Neon":      "res://scenes/maps/Neon.tscn",
	"Graveyard": "res://scenes/maps/Graveyard.tscn",
	"Maze":      "res://scenes/maps/Maze.tscn",
	"Dungeon":   "res://scenes/maps/Dungeon.tscn",
	"School":    "res://scenes/maps/School.tscn",
	"Cave":      "res://scenes/maps/Cave.tscn",
	"Lab":       "res://scenes/maps/Lab.tscn",
}

const SHADOW_COUNT  := 2    # shadow entities per match
const MIRAGE_COUNT  := 1    # fake hunters per match
const LOCKER_COUNT  := 5    # hiding lockers per match

const CAMP_RADIUS   := 10.0
const CAMP_TIME     := 18.0
const CAMP_RUNNER_CHECK := 20.0

## Killer "scan": every SCAN_INTERVAL the hunter sees a brief ping over every
## runner (Fortnite-style). PING_DURATION is how long the markers linger.
const SCAN_INTERVAL := 90.0
const PING_DURATION := 3.0
var _scan_timer := SCAN_INTERVAL

@onready var _map_root: Node3D = $MapRoot
@onready var _spawner: Node    = $PlayerSpawner
@onready var _position_sync: Node = $PositionSync
@onready var _proximity: Node  = $ProximityDetector
@onready var _ghost: Node      = $GhostController
@onready var _end: Node        = $EndCondition
@onready var _revive: Node     = $ReviveController

var _hunted_audio: Node
var _hunter_audio: Node
var _capture_detector: Node
var _pickups: Node
var _objectives: Node      # ObjectiveController (generators)
var _parkour: Node         # ParkourCourse (parkour mode)
var _parkour_lives: Dictionary = {}
var _horrors: Array = []   # shadow entities + mirages
var _active := false
var _obj_shown := -1       # last objective count pushed to the HUD
var _camp_timer := 0.0

# Reference to the HuntingUI so we can wire scare signals.
var _hunting_ui: Node


func _ready() -> void:
	GameManager.hunting_started.connect(_on_hunting_started)
	GameManager.role_assigned.connect(_on_role_assigned)
	GameManager.player_captured.connect(_on_player_captured)
	GameManager.game_ended.connect(_on_game_ended)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameStateSync.remote_grief.connect(_on_remote_grief)


func _on_phase_changed(new_phase: int, _old: int) -> void:
	# The HOST reaches HUNTING via the hunting_started signal; a JOINED client only
	# gets the synced phase change, so kick off the match setup here too.
	if new_phase == GameManager.Phase.HUNTING and not _active:
		_on_hunting_started()
	elif new_phase == GameManager.Phase.LOBBY and _active:
		_teardown()


func _on_hunting_started() -> void:
	if _active:
		return   # already set up (host fires both phase_changed and hunting_started)
	_load_map(GameManager.selected_map)
	var role := GameManager.get_local_role()
	_spawner.spawn_local(role)
	for peer_id in NetworkManager.get_peer_ids():
		if peer_id != NetworkManager.local_peer_id:
			_spawner.spawn_remote(peer_id, GameManager.get_role(peer_id))

	_setup_audio(role)
	_proximity.setup(_spawner)
	_ghost.setup(_spawner, _proximity, _hunted_audio, _hunter_audio)
	_revive.setup(_spawner)
	_position_sync.set_hunter_audio(_hunter_audio)
	if GameManager.game_mode == GameManager.Mode.PARKOUR:
		_spawn_parkour()
	else:
		_spawn_pickups()
		_spawn_horrors()
		_spawn_lockers()
		_spawn_objectives()
	_scan_timer = SCAN_INTERVAL
	_obj_shown = -1
	_active = true

	# Cache HuntingUI reference for wiring horror signals.
	await get_tree().process_frame
	_hunting_ui = get_tree().get_first_node_in_group("hunting_ui")
	# Register already-spawned lockers so HuntingUI can show the overlay.
	for h in _horrors:
		if h.has_method("is_occupied") and _hunting_ui and _hunting_ui.has_method("register_locker"):
			_hunting_ui.register_locker(h)


func _spawn_pickups() -> void:
	if _pickups and is_instance_valid(_pickups):
		_pickups.queue_free()
	_pickups = preload("res://scripts/PickupManager.gd").new()
	_map_root.add_child(_pickups)
	_pickups.setup(_spawner, _arena_bound())


func _spawn_parkour() -> void:
	_parkour = preload("res://scripts/ParkourCourse.gd").new()
	_map_root.add_child(_parkour)
	_parkour.setup(_spawner, randi())
	_parkour.player_fell.connect(_on_parkour_fall)
	_parkour.course_finished.connect(_on_parkour_finish)
	_parkour_lives.clear()
	for pid in NetworkManager.get_peer_ids():
		_parkour_lives[pid] = GameManager.gen_count
	if _spawner.local_player and is_instance_valid(_spawner.local_player):
		_spawner.local_player.global_position = _parkour.get_start_pos()


func _on_parkour_fall(pid: int) -> void:
	if not _parkour_lives.has(pid):
		return
	_parkour_lives[pid] -= 1
	if _hunting_ui and _hunting_ui.has_method("show_pickup_effect"):
		_hunting_ui.show_pickup_effect("FELL — %d LIVES LEFT" % _parkour_lives[pid], false)
	if _parkour_lives[pid] <= 0:
		GameManager.capture_player(pid, -1)


func _on_parkour_finish(pid: int) -> void:
	if _hunting_ui and _hunting_ui.has_method("show_pickup_effect"):
		_hunting_ui.show_pickup_effect("COURSE COMPLETE!", true)
	GameManager.end_game("escaped")


## Generators the hiders power up to escape (their win condition).
func _spawn_objectives() -> void:
	_objectives = preload("res://scripts/ObjectiveController.gd").new()
	_map_root.add_child(_objectives)
	_objectives.setup(_spawner, _arena_bound(), GameManager.gen_count, GameManager.gen_required)
	_objectives.all_complete.connect(_on_objectives_done)


func _on_objectives_done() -> void:
	# Every generator powered — the hiders escape and win.
	GameManager.end_game("escaped")


## Spawn shadow entities and mirages into the map.
func _spawn_horrors() -> void:
	_horrors.clear()
	var bound := _arena_bound()
	var shadow_script := preload("res://scripts/ShadowEntity.gd")
	var mirage_script  := preload("res://scripts/Mirage.gd")

	for i in SHADOW_COUNT:
		var s: Node3D = shadow_script.new()
		_map_root.add_child(s)
		s.setup(_spawner, bound)
		# Wire the scare signal to HuntingUI (connected after frame).
		s.triggered_scare.connect(_on_shadow_scare)
		_horrors.append(s)

	for i in MIRAGE_COUNT:
		var m: Node3D = mirage_script.new()
		_map_root.add_child(m)
		m.setup(_spawner, bound)
		m.vanished.connect(_on_mirage_vanish)
		_horrors.append(m)


## Scatter hiding lockers around the arena edges, clear of the spawn centre.
func _spawn_lockers() -> void:
	var locker_script := preload("res://scripts/Locker.gd")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bound := _arena_bound() - 10.0
	var centre_clear := 18.0
	var placed := 0
	var attempts := 0
	var positions: Array[Vector3] = []
	while placed < LOCKER_COUNT and attempts < 200:
		attempts += 1
		var pos := Vector3(
			rng.randf_range(-bound, bound), 0.0,
			rng.randf_range(-bound, bound))
		if pos.length() < centre_clear:
			continue
		var too_close := false
		for p in positions:
			if p.distance_to(pos) < 14.0:
				too_close = true
				break
		if too_close:
			continue
		positions.append(pos)
		var l: Node3D = locker_script.new()
		_map_root.add_child(l)
		l.global_position = pos
		l.setup(_spawner)
		_horrors.append(l)   # store so teardown queue-frees them
		placed += 1


func _on_shadow_scare() -> void:
	if _hunting_ui and _hunting_ui.has_method("force_jumpscare"):
		_hunting_ui.force_jumpscare()


func _on_mirage_vanish() -> void:
	if _hunting_ui and _hunting_ui.has_method("trigger_glitch"):
		_hunting_ui.trigger_glitch("scare")


## A remote ghost's grief reached us — apply it to the local runner.
func _on_remote_grief(target_id: int, ghost_id: int, dmg: int, stun: float) -> void:
	if target_id != NetworkManager.local_peer_id:
		return
	var lp = _spawner.local_player
	if lp == null or not is_instance_valid(lp) or lp.role != GameManager.Role.HUNTED:
		return
	if dmg > 0 and lp.has_method("take_damage"):
		lp.take_damage(dmg, ghost_id)   # this already flashes damage locally
	if stun > 0.0 and lp.has_method("apply_stun"):
		lp.apply_stun(stun)
	# Only the heavy griefs (lightning / knockdowns) jumpscare; a melee chip just flashes.
	if stun >= 1.0 and _hunting_ui and _hunting_ui.has_method("force_jumpscare"):
		_hunting_ui.force_jumpscare()


# ─────────────────────────────────────────────────────────────────────────────
# KILLER SCAN  (periodic location ping, Fortnite-style)
# ─────────────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active or GameManager.current_phase != GameManager.Phase.HUNTING:
		return

	# ── Endgame escalation: tension rises with time elapsed AND objectives done ──
	var total_secs := maxi(GameManager.get_round_seconds(), 1)
	var time_pressure := 1.0 - float(GameManager.get_seconds_left()) / float(total_secs)
	var obj_frac: float = _objectives.fraction() if _objectives else 0.0
	GameManager.tension = clampf(maxf(time_pressure, obj_frac), 0.0, 1.0)

	# ── Objective counter on the HUD ──
	if _objectives and _hunting_ui and _hunting_ui.has_method("show_objectives"):
		if _objectives.done != _obj_shown:
			_obj_shown = _objectives.done
			_hunting_ui.show_objectives(_objectives.done, _objectives.total)

	# ── Killer scan: fires faster as tension climbs (90 s → 35 s) ──
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = lerpf(SCAN_INTERVAL, 35.0, GameManager.tension)
		_do_scan()

	# ── Anti-camp: teleport killer away from generators if camping ──
	_check_camp(delta)


## Runs on every client; each acts on its OWN local role.
func _do_scan() -> void:
	var role := GameManager.get_local_role()
	if role == GameManager.Role.HUNTER:
		# Ping every runner so the hunter glimpses their location.
		for r in _all_hunted():
			_spawn_ping(r)
		AudioManager.play_sfx("countdown_beep", 2.0)
		if _hunting_ui and _hunting_ui.has_method("show_scan_alert"):
			_hunting_ui.show_scan_alert(true)
	elif role == GameManager.Role.HUNTED:
		# The runner feels the sweep — a warning, but no map.
		if _hunting_ui and _hunting_ui.has_method("show_scan_alert"):
			_hunting_ui.show_scan_alert(false)


## Every HUNTED player/bot currently in the match.
func _all_hunted() -> Array:
	var out: Array = []
	if _spawner.local_player and is_instance_valid(_spawner.local_player) \
			and _spawner.local_player.role == GameManager.Role.HUNTED:
		out.append(_spawner.local_player)
	for id in _spawner.remotes:
		var rp = _spawner.remotes[id]
		if is_instance_valid(rp) and rp.role == GameManager.Role.HUNTED:
			out.append(rp)
	return out


## A floating, see-through-walls chevron over a runner that fades after a moment.
func _spawn_ping(runner: Node3D) -> void:
	if runner == null or not is_instance_valid(runner):
		return
	if not runner.is_inside_tree():
		return
	var ping := Label3D.new()
	ping.text = "▼"
	ping.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	ping.no_depth_test = true
	ping.fixed_size = true
	ping.pixel_size = 0.0014
	ping.font_size = 64
	ping.modulate = Color(1.0, 0.15, 0.15)
	ping.outline_modulate = Color(0, 0, 0, 0.9)
	ping.outline_size = 16
	ping.render_priority = 20
	ping.position = Vector3(0, 2.8, 0)
	runner.add_child(ping)

	var t := create_tween()
	t.set_loops(int(PING_DURATION / 0.5))
	t.tween_property(ping, "position:y", 3.4, 0.25)
	t.tween_property(ping, "position:y", 2.8, 0.25)
	var fade := create_tween()
	fade.tween_interval(PING_DURATION - 0.4)
	fade.tween_property(ping, "modulate:a", 0.0, 0.4)
	fade.tween_callback(func():
		if is_instance_valid(ping):
			ping.queue_free())


func _check_camp(delta: float) -> void:
	if _objectives == null:
		return
	var hunters := _all_hunters()
	if hunters.is_empty():
		return
	var gens := get_tree().get_nodes_in_group("generator")
	for hunter in hunters:
		if not is_instance_valid(hunter):
			continue
		var near_gen := false
		for g in gens:
			if is_instance_valid(g) and not ("done" in g and g.done):
				if hunter.global_position.distance_to(g.global_position) < CAMP_RADIUS:
					near_gen = true
					break
		if not near_gen:
			_camp_timer = 0.0
			return
		var runner_nearby := false
		for r in _all_hunted():
			if is_instance_valid(r) and hunter.global_position.distance_to(r.global_position) < CAMP_RUNNER_CHECK:
				runner_nearby = true
				break
		if runner_nearby:
			_camp_timer = 0.0
			return
		_camp_timer += delta
		if _camp_timer >= CAMP_TIME:
			_camp_timer = 0.0
			_teleport_hunter_away(hunter)


func _teleport_hunter_away(hunter: Node3D) -> void:
	var bound := _arena_bound() - 10.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var gens := get_tree().get_nodes_in_group("generator")
	for _try in 30:
		var pos := Vector3(rng.randf_range(-bound, bound), 0.0, rng.randf_range(-bound, bound))
		var far_enough := true
		for g in gens:
			if is_instance_valid(g) and pos.distance_to(g.global_position) < 25.0:
				far_enough = false
				break
		if far_enough:
			hunter.global_position = Vector3(pos.x, hunter.global_position.y, pos.z)
			if _hunting_ui and _hunting_ui.has_method("show_pickup_effect"):
				_hunting_ui.show_pickup_effect("⚠ NO CAMPING — RELOCATED", false)
			return


func _all_hunters() -> Array:
	var out: Array = []
	if _spawner.local_player and is_instance_valid(_spawner.local_player) \
			and _spawner.local_player.role == GameManager.Role.HUNTER:
		out.append(_spawner.local_player)
	for id in _spawner.remotes:
		var rp = _spawner.remotes[id]
		if is_instance_valid(rp) and rp.role == GameManager.Role.HUNTER:
			out.append(rp)
	return out


func _arena_bound() -> float:
	if _spawner and _spawner.has_method("_arena_bound"):
		return _spawner._arena_bound()
	return 90.0


func _load_map(map_name: String) -> void:
	for c in _map_root.get_children():
		c.queue_free()
	var path: String  = MAP_SCENES.get(map_name, MAP_SCENES["Urban"])
	var scene: PackedScene = load(path)
	var map := scene.instantiate()
	_map_root.add_child(map)
	_spawner.bind_spawns(map.get_node_or_null("SpawnPoints"))


func _setup_audio(role: int) -> void:
	_free_audio_nodes()
	_hunted_audio = preload("res://scripts/HuntedAudioController.gd").new()
	add_child(_hunted_audio)
	_hunter_audio = preload("res://scripts/Hunter3DAudio.gd").new()
	add_child(_hunter_audio)
	if role == GameManager.Role.HUNTED:
		_hunted_audio.start()
	elif role == GameManager.Role.HUNTER:
		_attach_capture_detector()


func _attach_capture_detector() -> void:
	if _capture_detector and is_instance_valid(_capture_detector):
		return
	_capture_detector = preload("res://scripts/CaptureDetector.gd").new()
	_spawner.local_player.add_child(_capture_detector)
	_capture_detector.setup(_spawner.local_player)


func _on_role_assigned(peer_id: int, role: int) -> void:
	if not _active:
		return
	var was_revived: bool = GameManager.revived.has(peer_id)
	if peer_id == NetworkManager.local_peer_id:
		if _spawner.local_player and is_instance_valid(_spawner.local_player):
			_spawner.local_player.configure_for_role(role)
			_spawner.local_player.slowed = was_revived
	else:
		var rp = _spawner.get_remote(peer_id)
		if rp:
			rp.slowed = was_revived
			rp.apply_role(role)


func _on_player_captured(peer_id: int, _by: int) -> void:
	AudioManager.play_sfx("capture")
	if GameManager.get_local_role() == GameManager.Role.HUNTER and _hunter_audio:
		var rp = _spawner.get_remote(peer_id)
		if rp:
			_hunter_audio.play_event("capture", rp.global_position)
	# Drop a body + blood splatter where they died.
	_spawn_corpse(peer_id)
	if peer_id == NetworkManager.local_peer_id:
		if _hunted_audio:
			_hunted_audio.on_capture()
		_hunted_audio.stop()


## Leave a corpse + blood where the captured runner fell.
func _spawn_corpse(peer_id: int) -> void:
	var pos := Vector3.ZERO
	var col := Color(0.8, 0.8, 0.85)
	if peer_id == NetworkManager.local_peer_id and _spawner.local_player \
			and is_instance_valid(_spawner.local_player):
		pos = _spawner.local_player.global_position
		col = GameManager.local_color
	else:
		var rp = _spawner.get_remote(peer_id)
		if rp == null or not is_instance_valid(rp):
			return
		pos = rp.global_position
		col = RemotePlayer.id_color(peer_id)
	var corpse: Node3D = preload("res://scripts/Corpse.gd").new()
	_map_root.add_child(corpse)
	corpse.global_position = Vector3(pos.x, 0.0, pos.z)
	corpse.setup(col)


func _on_game_ended(_results: Dictionary) -> void:
	_teardown()


func _teardown() -> void:
	if not _active:
		return
	_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _hunted_audio:
		_hunted_audio.stop()
	_pickups = null
	_objectives = null
	_parkour = null
	_parkour_lives.clear()
	_horrors.clear()
	_hunting_ui = null
	for c in _map_root.get_children():
		c.queue_free()
	if _spawner.local_player and is_instance_valid(_spawner.local_player):
		_spawner.local_player.queue_free()
		_spawner.local_player = null
	for peer_id in _spawner.remotes.keys():
		_spawner.despawn_remote(peer_id)
	_free_audio_nodes()


func _free_audio_nodes() -> void:
	for n in [_hunted_audio, _hunter_audio, _capture_detector]:
		if n and is_instance_valid(n):
			n.queue_free()
	_hunted_audio     = null
	_hunter_audio     = null
	_capture_detector = null
