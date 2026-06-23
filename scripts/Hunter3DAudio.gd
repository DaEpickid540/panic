extends Node3D
## Hunter3DAudio
##
## Attached to the local player when their role is HUNTER. The hunter hears
## the world in 3D: footsteps and ghost screams come from the *direction* of
## the source, scaled by distance (closer = louder). This is the hunter's only
## tracking sense beyond line of sight.
##
## Drive it by registering remote players (the things that make noise) and
## calling update each frame; it manages a pool of AudioStreamPlayer3D nodes.

const MAX_HEAR_DISTANCE := 25.0   # metres
const FOOTSTEP_INTERVAL := 0.45   # seconds between footstep ticks while moving

var _emitters: Dictionary = {}    # peer_id -> AudioStreamPlayer3D
var _footstep_clocks: Dictionary = {}  # peer_id -> float


func _ready() -> void:
	pass


## Register a noise source (a remote hunted/ghost). pos in world space.
func track(peer_id: int) -> void:
	if _emitters.has(peer_id):
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.max_distance = MAX_HEAR_DISTANCE
	p.unit_size = 4.0
	add_child(p)
	_emitters[peer_id] = p
	_footstep_clocks[peer_id] = 0.0


func untrack(peer_id: int) -> void:
	if _emitters.has(peer_id):
		_emitters[peer_id].queue_free()
		_emitters.erase(peer_id)
		_footstep_clocks.erase(peer_id)


## Call each frame with the moving sources so footsteps play positionally.
## moving_positions: { peer_id: Vector3 } for players that moved this frame.
func update(delta: float, moving_positions: Dictionary) -> void:
	for peer_id in moving_positions:
		if not _emitters.has(peer_id):
			track(peer_id)
		var p: AudioStreamPlayer3D = _emitters[peer_id]
		p.global_position = moving_positions[peer_id]
		_footstep_clocks[peer_id] += delta
		if _footstep_clocks[peer_id] >= FOOTSTEP_INTERVAL:
			_footstep_clocks[peer_id] = 0.0
			_play_at(p, AudioManager.get_sfx_stream("footstep"))


## One-shot positional event (capture / ghost scream) at a world position.
func play_event(sound_name: String, world_pos: Vector3) -> void:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.max_distance = MAX_HEAR_DISTANCE * 2.0
	add_child(p)
	p.global_position = world_pos   # must be in the tree before setting global pos
	p.stream = AudioManager.get_sfx_stream(sound_name)
	p.finished.connect(p.queue_free)
	if p.stream:
		p.play()
	else:
		p.queue_free()


func _play_at(p: AudioStreamPlayer3D, stream: AudioStream) -> void:
	if stream == null:
		return
	p.stream = stream
	p.play()
