extends Node
## AudioManager — music crossfade + one-shot SFX. (autoload singleton)

signal loop_changed(index: int)

const FADE_TIME := 1.0

const LOOP_PATHS := [
	"res://assets/audio/loops/horror_01.mp3",
	"res://assets/audio/loops/horror_02.mp3",
	"res://assets/audio/loops/horror_03.mp3",
	"res://assets/audio/loops/horror_04.mp3",
	"res://assets/audio/loops/horror_05.mp3",
	"res://assets/audio/loops/horror_06.mp3",
	"res://assets/audio/loops/horror_07.mp3",
	"res://assets/audio/loops/horror_08.mp3",
]

const SFX_PATHS := {
	"countdown_beep": "res://assets/audio/sfx/countdown_beep.wav",
	"capture":        "res://assets/audio/sfx/capture.wav",
	"ghost_scream":   "res://assets/audio/sfx/ghost_scream.mp3",
	"phase_change":   "res://assets/audio/sfx/phase_change.wav",
	"footstep":       "res://assets/audio/sfx/footstep.wav",
	"demonic_growl":  "res://assets/audio/sfx/demonic_growl.mp3",
	"ghost_scratch":  "res://assets/audio/sfx/ghost_scratch.mp3",
	"creepy_tension": "res://assets/audio/sfx/creepy_tension.mp3",
	"entity_scream":  "res://assets/audio/sfx/entity_scream.mp3",
	"demonic_scream": "res://assets/audio/sfx/demonic_scream.mp3",
	"girl_scream":    "res://assets/audio/sfx/girl_scream.mp3",
	"thunder":        "res://assets/audio/sfx/thunder.mp3",
	"heartbeat":      "res://assets/audio/sfx/heartbeat.mp3",
	"footstep_concrete": "res://assets/audio/sfx/footstep_concrete.mp3",
}

## Ordered from most-scream-like to ambient fallback.
const CAPTURE_SCREAMS := [
	"entity_scream", "demonic_scream", "girl_scream",
	"ghost_scream",  "demonic_growl",  "ghost_scratch",
]

var loops: Array      = []
var sfx: Dictionary   = {}
var current_loop: int = -1

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_is_a := true
var _tween: Tween


func _ready() -> void:
	_player_a = _make_music_player()
	_player_b = _make_music_player()
	_preload()


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus       = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _preload() -> void:
	loops.clear()
	for path in LOOP_PATHS:
		var stream = load(path) if ResourceLoader.exists(path) else null
		if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
			stream.loop = true
		elif stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loops.append(stream)
	for name in SFX_PATHS:
		var path: String = SFX_PATHS[name]
		sfx[name] = load(path) if ResourceLoader.exists(path) else null


# ─────────────────────────────────────────────────────────────────────────────
# SFX
# ─────────────────────────────────────────────────────────────────────────────

func play_sfx(name: String, volume_db: float = 0.0) -> AudioStreamPlayer:
	var stream = sfx.get(name)
	if stream == null:
		return null
	var p := AudioStreamPlayer.new()
	p.bus       = "SFX"
	p.stream    = stream
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


func get_sfx_stream(name: String) -> AudioStream:
	return sfx.get(name)


## Play the scariest available scream at high volume (approx 150% louder than
## default). Falls back through the entire horror SFX pool so it ALWAYS plays
## something when the runner is captured — no more inconsistent silence.
func play_capture_scream() -> void:
	for key in CAPTURE_SCREAMS:
		if sfx.get(key) != null:
			play_sfx(key, 6.0)   # +6 dB ≈ 2× amplitude
			return


# ─────────────────────────────────────────────────────────────────────────────
# MUSIC
# ─────────────────────────────────────────────────────────────────────────────

func crossfade_to(index: int) -> void:
	if index < 0 or index >= loops.size():
		return
	current_loop = index
	loop_changed.emit(index)
	var stream = loops[index]
	if stream == null:
		return
	var incoming := _player_b if _active_is_a else _player_a
	var outgoing := _player_a if _active_is_a else _player_b
	_active_is_a = not _active_is_a
	incoming.stream    = stream
	incoming.volume_db = -80.0
	incoming.play()
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(incoming, "volume_db", 0.0,   FADE_TIME)
	_tween.tween_property(outgoing, "volume_db", -80.0, FADE_TIME)
	_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade := true) -> void:
	for p in [_player_a, _player_b]:
		if fade and p.playing:
			var t := create_tween()
			t.tween_property(p, "volume_db", -80.0, FADE_TIME)
			t.tween_callback(p.stop)
		else:
			p.stop()


func set_master_volume(linear: float) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))

func get_master_volume() -> float:
	var idx := AudioServer.get_bus_index("Master")
	return db_to_linear(AudioServer.get_bus_volume_db(idx)) if idx >= 0 else 1.0
