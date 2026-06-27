extends Control
## LobbyUI — two-column horror lobby.
##
## LEFT:   Players → Room/Join → Profile → Settings   (personal / connection)
## RIGHT:  Map → Weapon → Round time → Game mode      (match config, host-only)
## BOTTOM: HOST GAME · ADD BOT | START GAME            (actions)

const MAPS := ["Urban", "Forest", "Warehouse", "Mansion", "Neon", "Graveyard",
	"Maze", "Dungeon", "School", "Cave", "Lab"]

@onready var _count: Label = $Left/V/Head/PlayerCount
@onready var _list: VBoxContainer = $Left/V/PlayerList
@onready var _map_grid: GridContainer = $Right/V/MapGrid
@onready var _weapon_grid: GridContainer = $Right/V/WeaponGrid
@onready var _timer_slider: HSlider = $Right/V/TimerRow/TimerSlider
@onready var _timer_label: Label = $Right/V/TimerRow/TimerValue

var _menu_v: VBoxContainer
@onready var _net_status: Label = $Header/NetStatus
var _room_label: Label
var _last_status := ""
var _swatch_buttons: Array[Button] = []
var _role_buttons: Array[Button] = []
var _is_joined := false
var _host_controls: Array[Control] = []
var _lobby_sync_accum := 0.0
var _swatch_colors: Array[Color] = [
	Color(0.82, 0.82, 0.9),
	Color(0.3, 0.75, 0.9),
	Color(0.9, 0.4, 0.4),
	Color(0.35, 0.9, 0.4),
	Color(0.95, 0.7, 0.2),
	Color(0.8, 0.4, 0.95),
	Color(0.95, 0.55, 0.85),
	Color(0.95, 0.95, 0.95),
]


func _ready() -> void:
	_style_panels()

	_menu_v = $Left/V
	var scroll := ScrollContainer.new()
	scroll.layout_mode = 2
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	$Left.add_child(scroll)
	_menu_v.reparent(scroll)
	_menu_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_v.add_theme_constant_override("separation", 6)

	var rv := $Right/V
	var std_btn: Button = rv.get_node("ModeRow/StandardBtn")
	var pkr_btn: Button = rv.get_node("ModeRow/ParkourBtn")
	var inf_btn: Button = rv.get_node("ModeRow/InfectionBtn")
	var rscroll := ScrollContainer.new()
	rscroll.layout_mode = 2
	rscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	$Right.add_child(rscroll)
	rv.reparent(rscroll)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	NetworkManager.peer_joined.connect(func(_id): _refresh())
	NetworkManager.peer_left.connect(func(_id): _refresh())
	GameStateSync.lobby_settings.connect(_on_lobby_settings)

	_timer_slider.min_value = GameManager.MIN_ROUND_MINUTES
	_timer_slider.max_value = 10
	_timer_slider.step = 1
	_timer_slider.value = GameManager.round_minutes
	_timer_slider.value_changed.connect(_on_timer_changed)

	_build_map_cards()
	_build_weapon_buttons()
	# Left panel dynamic sections (appended after PlayerList).
	_build_room_section()
	_build_profile_section()
	_build_settings_section()
	_highlight_map(GameManager.selected_map)
	_refresh()
	UiFx.wire_buttons(self)

	_host_controls.append($Bottom/HostBtn)
	_host_controls.append($Bottom/AddBotBtn)
	_host_controls.append($Bottom/StartBtn)
	_host_controls.append(_timer_slider)
	for b in _map_grid.get_children():
		_host_controls.append(b)
	for b in _weapon_grid.get_children():
		_host_controls.append(b)

	var mode_btns: Array[Button] = [std_btn, pkr_btn, inf_btn]
	var mode_vals: Array[int] = [
		GameManager.Mode.STANDARD, GameManager.Mode.PARKOUR, GameManager.Mode.INFECTION]
	for i in mode_btns.size():
		var btn := mode_btns[i]
		var mode_val: int = mode_vals[i]
		_host_controls.append(btn)
		_apply_sel_style(btn, GameManager.game_mode == mode_val)
		btn.button_pressed = (GameManager.game_mode == mode_val)
		btn.pressed.connect(func():
			GameManager.game_mode = mode_val
			for j in mode_btns.size():
				var sel: bool = (mode_vals[j] == mode_val)
				mode_btns[j].button_pressed = sel
				_apply_sel_style(mode_btns[j], sel))


func _process(delta: float) -> void:
	if _net_status != null and FirebaseManager.status != _last_status:
		_last_status = FirebaseManager.status
		_update_net_status()
	if GameManager._is_host and NetworkManager._in_room:
		_lobby_sync_accum += delta
		if _lobby_sync_accum >= 2.0:
			_lobby_sync_accum = 0.0
			GameStateSync.push_lobby_settings()


# ─────────────────────────────────────────────────────────────────────────────
# PLAYER ROSTER
# ─────────────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	var n := NetworkManager.get_peer_count()
	_count.text = str(n)
	for c in _list.get_children():
		c.queue_free()
	for id in NetworkManager.get_peer_ids():
		_list.add_child(_make_player_row(id))
	if _room_label and NetworkManager.current_room != "":
		_room_label.text = NetworkManager.current_room


func _make_player_row(id: int) -> HBoxContainer:
	var local := id == NetworkManager.local_peer_id
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(20, 20)
	sw.color = GameManager.local_color if local else RemotePlayer.id_color(id)
	row.add_child(sw)
	var nm := Label.new()
	nm.text = ("YOU" if local else NetworkManager.get_peer_name(id).to_upper())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 14)
	row.add_child(nm)
	if local:
		_add_tag(row, "YOU", Color(0.7, 0.5, 0.8), Color(0.25, 0.15, 0.3))
	if local and GameManager._is_host:
		_add_tag(row, "HOST", Color(0.95, 0.75, 0.2), Color(0.3, 0.22, 0.05))
	_add_tag(row, "READY", Color(0.35, 0.85, 0.4), Color(0.06, 0.22, 0.1))
	return row


func _add_tag(row: HBoxContainer, text: String, fg: Color, bg: Color) -> void:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", fg)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	tag.add_theme_stylebox_override("normal", sb)
	row.add_child(tag)


# ─────────────────────────────────────────────────────────────────────────────
# ROOM / JOIN  (connection)
# ─────────────────────────────────────────────────────────────────────────────

func _build_room_section() -> void:
	var v := _menu_v
	_add_section_sep(v)
	_add_section_title(v, "ROOM")

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	var cl := Label.new()
	cl.text = "CODE"
	cl.add_theme_font_size_override("font_size", 12)
	cl.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))
	cl.custom_minimum_size = Vector2(44, 0)
	code_row.add_child(cl)
	_room_label = Label.new()
	_room_label.text = "------"
	_room_label.add_theme_font_size_override("font_size", 18)
	_room_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	code_row.add_child(_room_label)
	v.add_child(code_row)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	var code := LineEdit.new()
	code.placeholder_text = "ENTER CODE"
	code.max_length = 6
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(code)
	var join := Button.new()
	join.text = "JOIN"
	join.custom_minimum_size = Vector2(60, 0)
	join.pressed.connect(func():
		var c := code.text.strip_edges().to_upper()
		if c.length() >= 4:
			NetworkManager.join_room(c, GameManager.local_display_name)
			_lock_for_joiner()
			_refresh())
	join_row.add_child(join)
	v.add_child(join_row)

	_update_net_status()
	FirebaseManager.ready_changed.connect(func(_r): _update_net_status())


func _update_net_status() -> void:
	if _net_status == null:
		return
	match FirebaseManager.status:
		"online":
			_net_status.text = "● ONLINE"
			_net_status.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))
		"connecting":
			_net_status.text = "● CONNECTING…"
			_net_status.add_theme_color_override("font_color", Color(0.85, 0.8, 0.3))
		"auth_failed":
			_net_status.text = "● AUTH FAILED"
			_net_status.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25))
		_:
			_net_status.text = "● OFFLINE"
			_net_status.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))


# ─────────────────────────────────────────────────────────────────────────────
# PROFILE  (name / color / role preference)
# ─────────────────────────────────────────────────────────────────────────────

func _build_profile_section() -> void:
	var v := _menu_v
	_add_section_sep(v)
	_add_section_title(v, "YOUR PROFILE")

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	_add_row_label(name_row, "NAME")
	var ne := LineEdit.new()
	ne.placeholder_text = "ENTER NAME..."
	ne.text = GameManager.local_display_name
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.text_changed.connect(func(t: String) -> void:
		var n := t.to_upper().strip_edges()
		GameManager.local_display_name = n if n != "" else "PLAYER"
		NetworkManager.peers[NetworkManager.local_peer_id]["name"] = GameManager.local_display_name
		_refresh())
	name_row.add_child(ne)
	v.add_child(name_row)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 4)
	_add_row_label(color_row, "COLOR")
	_swatch_buttons.clear()
	for c in _swatch_colors:
		var cc := c
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(24, 24)
		btn.flat = true
		btn.pressed.connect(func():
			GameManager.local_color = cc
			_update_swatches()
			_refresh())
		color_row.add_child(btn)
		_swatch_buttons.append(btn)
	v.add_child(color_row)
	_update_swatches()

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 4)
	_add_row_label(role_row, "ROLE")
	_role_buttons.clear()
	var options := [["AUTO", -1], ["HUNTER", GameManager.Role.HUNTER], ["RUNNER", GameManager.Role.HUNTED]]
	for opt in options:
		var label: String = opt[0]
		var value: int = opt[1]
		var b := Button.new()
		b.text = label
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			GameManager.role_preference = value
			_update_role_buttons())
		role_row.add_child(b)
		_role_buttons.append(b)
	v.add_child(role_row)
	_update_role_buttons()


func _update_role_buttons() -> void:
	var values := [-1, GameManager.Role.HUNTER, GameManager.Role.HUNTED]
	for i in _role_buttons.size():
		var sel: bool = values[i] == GameManager.role_preference
		_role_buttons[i].button_pressed = sel
		_apply_sel_style(_role_buttons[i], sel)


# ─────────────────────────────────────────────────────────────────────────────
# SETTINGS  (volume / sensitivity / debug)
# ─────────────────────────────────────────────────────────────────────────────

func _build_settings_section() -> void:
	var v := _menu_v
	_add_section_sep(v)
	_add_section_title(v, "SETTINGS")

	# Audio
	v.add_child(_make_slider_row("VOLUME", 0.0, 1.0, 0.05,
		GameManager.settings_master,
		func(val: float) -> void: GameManager.set_master_volume(val)))

	# Controls
	v.add_child(_make_slider_row("LOOK", 0.2, 3.0, 0.1,
		GameManager.settings_sensitivity,
		func(val: float) -> void: GameManager.set_sensitivity(val)))

	# Video — fog strength
	var fog_row := _make_slider_row("FOG", 0.1, 1.0, 0.05,
		GameManager.settings_fog,
		func(val: float) -> void:
			GameManager.settings_fog = clampf(val, 0.1, 1.0)
			GameManager.save_settings())
	v.add_child(fog_row)

	# Match — killer count
	var kill_row := HBoxContainer.new()
	kill_row.add_theme_constant_override("separation", 4)
	_add_row_label(kill_row, "KILLERS")
	var _kill_btns: Array[Button] = []
	for n in [1, 2, 3]:
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_pressed = (GameManager.killer_count == n)
		b.custom_minimum_size = Vector2(36, 28)
		var nn: int = n
		b.pressed.connect(func():
			GameManager.killer_count = nn
			GameManager.save_settings()
			for bb in _kill_btns:
				bb.button_pressed = (str(GameManager.killer_count) == bb.text)
				_apply_sel_style(bb, bb.button_pressed))
		kill_row.add_child(b)
		_kill_btns.append(b)
		_apply_sel_style(b, b.button_pressed)
	v.add_child(kill_row)
	_host_controls.append_array(_kill_btns)

	# Debug toggle
	var dbg_row := HBoxContainer.new()
	dbg_row.add_theme_constant_override("separation", 4)
	_add_row_label(dbg_row, "DEBUG")
	var dbg_btn := Button.new()
	dbg_btn.toggle_mode = true
	dbg_btn.text = "ON" if GameManager.debug_overlay else "OFF"
	dbg_btn.button_pressed = GameManager.debug_overlay
	dbg_btn.custom_minimum_size = Vector2(60, 28)
	dbg_btn.pressed.connect(func():
		GameManager.debug_overlay = dbg_btn.button_pressed
		dbg_btn.text = "ON" if GameManager.debug_overlay else "OFF"
		GameManager.save_settings())
	dbg_row.add_child(dbg_btn)
	v.add_child(dbg_row)

	# Stats
	var best := GameManager.get_best_survival()
	var best_label := Label.new()
	best_label.text = "BEST SURVIVAL: %02d:%02d" % [best / 60, best % 60]
	best_label.add_theme_color_override("font_color", Color(0.45, 0.7, 0.45))
	best_label.add_theme_font_size_override("font_size", 12)
	v.add_child(best_label)


# ─────────────────────────────────────────────────────────────────────────────
# MATCH SETTINGS  (map / weapon — right panel, built from tscn nodes)
# ─────────────────────────────────────────────────────────────────────────────

func _build_map_cards() -> void:
	for map_name in MAPS:
		var b := Button.new()
		b.text = map_name.to_upper()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _select_map(map_name))
		_map_grid.add_child(b)


func _build_weapon_buttons() -> void:
	for w in GameManager.WEAPONS:
		var b := Button.new()
		b.text = w.to_upper()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): _select_weapon(w))
		_weapon_grid.add_child(b)
	_highlight_weapon(GameManager.selected_weapon)


func _select_map(map_name: String) -> void:
	GameManager.selected_map = map_name
	_highlight_map(map_name)
	if NetworkManager._in_room:
		GameStateSync.push_lobby_settings()


func _highlight_map(map_name: String) -> void:
	for b in _map_grid.get_children():
		var btn := b as Button
		var sel := btn.text == map_name.to_upper()
		btn.button_pressed = sel
		_apply_sel_style(btn, sel)


func _select_weapon(w: String) -> void:
	GameManager.selected_weapon = w
	_highlight_weapon(w)
	if NetworkManager._in_room:
		GameStateSync.push_lobby_settings()


func _highlight_weapon(w: String) -> void:
	for b in _weapon_grid.get_children():
		var btn := b as Button
		var sel := btn.text == w.to_upper()
		btn.button_pressed = sel
		_apply_sel_style(btn, sel)


func _on_timer_changed(v: float) -> void:
	GameManager.set_round_minutes(int(v))
	_timer_label.text = "%d MIN" % GameManager.round_minutes
	if NetworkManager._in_room:
		GameStateSync.push_lobby_settings()


# ─────────────────────────────────────────────────────────────────────────────
# LOBBY SYNC  (host → joiner)
# ─────────────────────────────────────────────────────────────────────────────

func _on_lobby_settings(settings: Dictionary) -> void:
	if GameManager._is_host:
		return
	if settings.has("map"):
		GameManager.selected_map = str(settings["map"])
		_highlight_map(GameManager.selected_map)
	if settings.has("weapon"):
		GameManager.selected_weapon = str(settings["weapon"])
		_highlight_weapon(GameManager.selected_weapon)
	if settings.has("time"):
		GameManager.round_minutes = int(settings["time"])
		_timer_slider.value = GameManager.round_minutes
		_timer_label.text = "%d MIN" % GameManager.round_minutes
	if settings.has("killers"):
		GameManager.killer_count = int(settings["killers"])
	if settings.has("mode"):
		GameManager.game_mode = int(settings["mode"])


func _lock_for_joiner() -> void:
	_is_joined = true
	for c in _host_controls:
		if c is BaseButton:
			c.disabled = true
		elif c is HSlider:
			c.editable = false
	$Bottom/StartBtn.text = "WAITING FOR HOST…"
	$Bottom/HostBtn.text = "IN ROOM"
	_refresh()


# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS  (bottom bar)
# ─────────────────────────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	NetworkManager.host_room()
	GameStateSync.push_lobby_settings()
	_refresh()


func _on_add_bot_pressed() -> void:
	NetworkManager.add_test_peer()


func _on_start_pressed() -> void:
	GameManager.start_game()


# ─────────────────────────────────────────────────────────────────────────────
# UI HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _style_panels() -> void:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.05, 0.03, 0.03, 0.65)
	flat.set_corner_radius_all(6)
	flat.set_border_width_all(1)
	flat.border_color = Color(0.25, 0.05, 0.05, 0.4)
	flat.content_margin_left = 16
	flat.content_margin_right = 16
	flat.content_margin_top = 14
	flat.content_margin_bottom = 14
	$Left.add_theme_stylebox_override("panel", flat)
	$Right.add_theme_stylebox_override("panel", flat.duplicate())

	$Bottom/HostBtn.add_theme_font_size_override("font_size", 16)
	$Bottom/AddBotBtn.add_theme_font_size_override("font_size", 16)


func _add_section_sep(parent: Control) -> void:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.04, 0.04, 0.5)
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	sep.add_theme_stylebox_override("separator", sb)
	parent.add_child(sep)


func _add_section_title(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.12, 0.12))
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)


func _add_row_label(row: HBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(50, 0)
	l.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)


func _make_slider_row(label_text: String, lo: float, hi: float, step: float,
		start: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_add_row_label(row, label_text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = start
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(on_change)
	row.add_child(s)
	return row


func _apply_sel_style(btn: Button, selected: bool) -> void:
	if selected:
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6))
		btn.modulate = Color(1.2, 0.9, 0.9)
	else:
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_color_override("font_hover_color")
		btn.modulate = Color(0.7, 0.65, 0.65)


func _update_swatches() -> void:
	for i in _swatch_buttons.size():
		var btn := _swatch_buttons[i]
		var c := _swatch_colors[i]
		var selected := c.is_equal_approx(GameManager.local_color)
		btn.modulate = c
		if selected:
			btn.modulate = c.lightened(0.2)
			btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.3))
			btn.text = "●"
		else:
			btn.remove_theme_color_override("font_color")
			btn.text = ""
