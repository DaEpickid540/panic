extends Control
## CountdownUI — large pulsing red number + a beep on each second.

@onready var _number: Label = $Center/Number
@onready var _bar: ProgressBar = $Bar
var _pulse: Tween
var _total := 5


func _ready() -> void:
	GameManager.countdown_started.connect(_on_started)
	GameManager.countdown_tick.connect(_on_tick)


func _on_started(seconds: int) -> void:
	_total = maxi(seconds, 1)
	_number.text = str(seconds)
	_set_bar(seconds)
	AudioManager.play_sfx("countdown_beep")
	_start_pulse()


func _on_tick(seconds_left: int) -> void:
	_number.text = str(maxi(seconds_left, 0))
	_set_bar(seconds_left)
	AudioManager.play_sfx("countdown_beep")
	_start_pulse()


## Fill the bar as the countdown elapses (a "preparing arena" loading feel).
func _set_bar(seconds_left: int) -> void:
	var target := 1.0 - float(maxi(seconds_left, 0)) / float(_total)
	create_tween().tween_property(_bar, "value", target, 0.3)


## Scale 1.0 -> 1.2 -> 1.0 each tick (<= 500 ms total).
func _start_pulse() -> void:
	if _pulse and _pulse.is_running():
		_pulse.kill()
	_number.pivot_offset = _number.size * 0.5
	_number.scale = Vector2.ONE
	_pulse = create_tween()
	_pulse.tween_property(_number, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_number, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)
