extends CanvasLayer
## Debug overlay — shows Firebase/network state on screen.
## Toggled via GameManager.debug_overlay setting.

var _label: Label
var _errors: Array[String] = []


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.position = Vector2(10, 4)
	_label.size = Vector2(1200, 200)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0, 1, 0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_label)
	FirebaseManager.db_error.connect(func(path, code):
		_errors.append("ERR %d on %s" % [code, path.get_file()])
		if _errors.size() > 4:
			_errors.pop_front())


func _process(_delta: float) -> void:
	visible = GameManager.debug_overlay
	if not visible:
		return
	var key: String = str(FirebaseManager.CONFIG.get("apiKey", ""))
	var lines := PackedStringArray()
	lines.append("FB: %s | auth=%s token=%d | key=%s" % [
		FirebaseManager.status,
		"yes" if FirebaseManager.is_ready else "no",
		FirebaseManager._id_token.length(),
		key.left(10) + "..." if key.length() > 10 else key])
	lines.append("Room: %s | peers=%d | in_room=%s | host=%s" % [
		NetworkManager.current_room if NetworkManager.current_room != "" else "(none)",
		NetworkManager.get_peer_count(),
		str(NetworkManager._in_room),
		str(GameManager._is_host)])
	lines.append("Listens: %d | Inflight: %d" % [
		FirebaseManager._listens.size(),
		FirebaseManager._inflight.size()])
	if _errors.size() > 0:
		lines.append("Errors: " + " | ".join(_errors))
	_label.text = "\n".join(lines)
