extends Node
## HuntedAudioController
##
## Attached to the local player when their role is HUNTED. The horror hook:
## hunted players navigate by AUDIO ONLY. They hear the continuous ambient
## loop (auto-advancing 1->2->...->8->1) plus exactly two gameplay sounds:
## the capture confirm and a ghost reveal. No UI sounds, no movement SFX.
##
## On capture / ghost grab the audio fades to silence (the player is "blind"
## and now deaf — pure panic). escape() restores it.

## Switch loops every 2-3 min (randomised per cycle for unpredictability).
const MIN_SWITCH_SEC := 120.0
const MAX_SWITCH_SEC := 180.0

var active := false
var _index := 0
var _switch_timer: Timer
var _muted := false


func _ready() -> void:
	_switch_timer = Timer.new()
	_switch_timer.one_shot = true
	_switch_timer.timeout.connect(_advance_loop)
	add_child(_switch_timer)


## Called when the HUNTING phase starts for a hunted player.
func start() -> void:
	active = true
	_muted = false
	_index = 0
	AudioManager.crossfade_to(_index)
	_arm_switch()


func stop() -> void:
	active = false
	_switch_timer.stop()
	AudioManager.stop_music(true)


func _arm_switch() -> void:
	_switch_timer.wait_time = randf_range(MIN_SWITCH_SEC, MAX_SWITCH_SEC)
	_switch_timer.start()


func _advance_loop() -> void:
	if not active or _muted:
		return
	_index = (_index + 1) % AudioManager.LOOP_PATHS.size()
	AudioManager.crossfade_to(_index)
	_arm_switch()


## --- The only two gameplay sounds a hunted player hears ------------------

func on_capture() -> void:
	# Caught: confirm sound then go silent.
	AudioManager.play_sfx("capture")
	mute()


func on_ghost_reveal() -> void:
	if not _muted:
		AudioManager.play_sfx("ghost_scream")


## --- Mute / restore (ghost grab) ----------------------------------------

func mute() -> void:
	_muted = true
	AudioManager.stop_music(true)


func escape() -> void:
	if not active:
		return
	_muted = false
	AudioManager.crossfade_to(_index)
	_arm_switch()
