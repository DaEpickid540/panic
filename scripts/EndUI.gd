extends Control
## EndUI — survivor list + stats table (name, role, survival time, captures).

@onready var _headline: Label = $Panel/VBox/Headline
@onready var _survivors: Label = $Panel/VBox/Survivors
@onready var _rows: VBoxContainer = $Panel/VBox/StatsTable/Rows
@onready var _play_again: Button = $Panel/VBox/PlayAgain


func _ready() -> void:
	GameManager.game_ended.connect(_on_ended)


func _on_ended(results: Dictionary) -> void:
	var reason: String = results.get("reason", "timer")
	var survivor_count: int = results.get("survivor_count", 0)
	var hiders_win := reason == "escaped" or (reason != "all_captured" and survivor_count > 0)
	var i_survived: bool = NetworkManager.local_peer_id in results.get("survivors", [])

	# Headline + colour from the outcome (and personalised for the local player).
	var text := ""
	if hiders_win:
		if reason == "escaped":
			text = "YOU ESCAPED!" if i_survived else "THE HIDERS ESCAPED!"
		else:
			text = "YOU SURVIVED!" if i_survived else "THE HIDERS SURVIVED!"
		_headline.add_theme_color_override("font_color", Color(0.45, 0.7, 0.42))
	else:
		text = "THE HUNTER WINS"
		_headline.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))
	_headline.text = text

	# GameManager records stats on game_ended too, so by now best reflects this match.
	var best := GameManager.get_best_survival()
	_survivors.text = "SURVIVORS: %d        BEST: %02d:%02d" % [
		survivor_count, best / 60, best % 60]
	for c in _rows.get_children():
		c.queue_free()
	for s in results.get("stats", []):
		_rows.add_child(_make_row(s))


func _make_row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_cell(row, s.get("name", "?"), 160)
	_cell(row, str(s.get("role", "")).to_upper(), 90)
	var t: int = s.get("survival_time", 0)
	_cell(row, "%02d:%02d" % [t / 60, t % 60], 80)
	_cell(row, "x%d" % s.get("captures", 0), 60)
	return row


func _cell(row: HBoxContainer, text: String, width: int) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	row.add_child(l)


func _on_play_again_pressed() -> void:
	GameManager.force_phase(GameManager.Phase.LOBBY)
