extends Node
## GhostController  (world node, configured by GameController)
##
## Owns the ghost grab / reveal interaction across the network. Runs on every
## client but acts according to the LOCAL role:
##
##   As GHOST  — press "grab" while a hunted player is within 3 m to grip them:
##               emit a scream (all hear direction) and write the grip to Firebase.
##   As HUNTED — when gripped, audio mutes; you have 5 s to break line of sight.
##               Stay > 3 m from the ghost for 1 s and you escape (audio resumes).
##
## (Ghost *movement* — 2 m/s, no collision — lives in PlayerController; this is
## the interaction layer.)

signal ghost_grabbed(hunted_id: int)      # local ghost grabbed someone (UI arm)
signal local_gripped(ghost_id: int)       # local hunted is being held (UI)
signal local_escaped()

const GRAB_RANGE := 3.0
const ESCAPE_DISTANCE := 3.0
const ESCAPE_HOLD_SEC := 1.0
const GRIP_WINDOW_SEC := 5.0

var spawner: Node
var proximity: Node
var hunted_audio: Node
var hunter_audio: Node

# Hunted-side grip state.
var _gripped_by := -1
var _escape_accum := 0.0
var _grip_elapsed := 0.0


func _ready() -> void:
	# Connect once; setup() (called each round) only refreshes node refs.
	GameStateSync.remote_grab.connect(_on_remote_grab)
	GameStateSync.remote_escape.connect(_on_remote_escape)
	GameStateSync.remote_reveal.connect(_on_remote_reveal)


func setup(p_spawner: Node, p_proximity: Node, p_hunted_audio: Node, p_hunter_audio: Node) -> void:
	spawner = p_spawner
	proximity = p_proximity
	hunted_audio = p_hunted_audio
	hunter_audio = p_hunter_audio
	_gripped_by = -1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("grab") and GameManager.get_local_role() == GameManager.Role.GHOST:
		try_grab()


## --- Ghost side ----------------------------------------------------------

const GRAB_STUN := 2.0   # seconds the grabbed runner is held in place

func try_grab() -> void:
	if proximity == null or spawner == null:
		return
	var nearest = proximity.nearest_remote_of_role(GameManager.Role.HUNTED, GRAB_RANGE)
	if nearest.is_empty():
		return
	var target: int = nearest["peer_id"]
	var ghost_id := NetworkManager.local_peer_id

	# Grab freezes the runner in place + chips a heart. grief_runner applies it
	# to bots/local immediately and routes it over the network to human runners.
	var rp = spawner.get_remote(target)
	if rp:
		GameManager.grief_runner(rp, ghost_id, 1, GRAB_STUN)

	GameStateSync.push_grab(target, ghost_id)
	GameStateSync.push_ghost_reveal(ghost_id)
	AudioManager.play_sfx("ghost_scream", 4.0)   # the ghost hears its own scream
	ghost_grabbed.emit(target)


## --- Hunted side ---------------------------------------------------------

func _on_remote_grab(hunted_id: int, ghost_id: int) -> void:
	if hunted_id != NetworkManager.local_peer_id:
		return
	if GameManager.get_local_role() != GameManager.Role.HUNTED:
		return
	if _gripped_by == ghost_id:
		return
	_gripped_by = ghost_id
	_escape_accum = 0.0
	_grip_elapsed = 0.0
	if hunted_audio:
		hunted_audio.mute()             # caught hunted go deaf
	local_gripped.emit(ghost_id)


func _on_remote_escape(hunted_id: int) -> void:
	if hunted_id == NetworkManager.local_peer_id:
		_clear_grip()


func _on_remote_reveal(ghost_id: int) -> void:
	if spawner == null:
		return
	# Hunter hears the scream positionally; hunted hears the reveal cue.
	if GameManager.get_local_role() == GameManager.Role.HUNTER and hunter_audio:
		var rp = spawner.get_remote(ghost_id)
		if rp:
			hunter_audio.play_event("ghost_scream", rp.global_position)
	elif GameManager.get_local_role() == GameManager.Role.HUNTED and hunted_audio:
		hunted_audio.on_ghost_reveal()


func _physics_process(delta: float) -> void:
	if _gripped_by == -1:
		return
	_grip_elapsed += delta
	var ghost = spawner.get_remote(_gripped_by)
	if ghost == null or spawner.local_player == null:
		return
	var dist: float = spawner.local_player.global_position.distance_to(ghost.global_position)
	if dist > ESCAPE_DISTANCE:
		_escape_accum += delta
		if _escape_accum >= ESCAPE_HOLD_SEC:
			GameStateSync.push_escape(NetworkManager.local_peer_id)
			_clear_grip()
	else:
		_escape_accum = 0.0


func _clear_grip() -> void:
	if _gripped_by == -1:
		return
	_gripped_by = -1
	if hunted_audio:
		hunted_audio.escape()
	local_escaped.emit()
