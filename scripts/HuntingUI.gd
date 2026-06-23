extends Control
## HuntingUI — the heads-up display during the hunt phase.
##
## Manages:
##   • Role label + round timer
##   • Dash / throw / battery / stamina / HP bars
##   • Vignette blindness shader (hunters close = red edges)
##   • Red danger flash (very-close hunter)
##   • Procedural jumpscare (fires for ALL roles — no reason needed)
##   • Glitch overlay (screen tear + scan lines)
##   • Locker overlay (dark panel when runner is hiding)
##   • Kill-feed toast ("NAME WAS CAUGHT")
##   • Pickup effect toast ("HEAL!" / "SLOWED!")
##   • Mobile controls + look region

# ─────────────────────────────────────────────────────────────────────────────
# BLINDNESS / VIGNETTE
# ─────────────────────────────────────────────────────────────────────────────
const DANGER_DIST     := 28.0    # was 18 — more gradual reddening
const BLIND_INTENSITY := 1.0
const CLEAR_INTENSITY := 0.45
const BLIND_RADIUS    := 0.08
const CLEAR_RADIUS    := 0.42
const CLEAR_HOLD      := 5.0

# ─────────────────────────────────────────────────────────────────────────────
# JUMPSCARE TIMING
# ─────────────────────────────────────────────────────────────────────────────
const SCARE_MIN := 14.0    # seconds between random jumpscares (min)
const SCARE_MAX := 40.0    # seconds between random jumpscares (max)
const SCARE_SOUNDS := ["ghost_scream", "ghost_scratch", "demonic_growl",
					   "entity_scream", "demonic_scream"]

# ─────────────────────────────────────────────────────────────────────────────
# NODE REFERENCES
# ─────────────────────────────────────────────────────────────────────────────
@onready var _role:          Label       = $TopBar/RoleLabel
@onready var _timer:         Label       = $TopBar/TimerLabel
@onready var _timer_bar:     ProgressBar = $TopBar/TimerBar
@onready var _minimap:       Control     = $MiniMap
@onready var _joystick:      Control     = $VirtualJoystick
@onready var _grip_banner:   Label       = $GripBanner
@onready var _crosshair:     Label       = $Crosshair
@onready var _hint:          Label       = $ControlsHint
@onready var _vignette:      ColorRect   = $Vignette
@onready var _battery:       ProgressBar = $BatteryBar
@onready var _battery_label: Label       = $BatteryLabel
@onready var _dash_bar:      ProgressBar = $DashBar
@onready var _dash_label:    Label       = $DashLabel
@onready var _throw_bar:     ProgressBar = $ThrowBar
@onready var _throw_label:   Label       = $ThrowLabel
@onready var _stamina_bar:   ProgressBar = $StaminaBar
@onready var _stamina_label: Label       = $StaminaLabel
@onready var _mobile_btns:   HBoxContainer = $MobileButtons
@onready var _jumpscare:     TextureRect = $Jumpscare   # kept for legacy textures

# In-code UI elements (created in _ready).
var _hp_bar:      ProgressBar
var _hp_label:    Label
var _red_flash:   ColorRect
var _killfeed:    Label
var _pickup_toast: Label
var _obj_label: Label
var _gen_panel: VBoxContainer
var _gen_bars: Array[ProgressBar] = []
var _gen_labels: Array[Label] = []
var _locker_panel: Control
var _locker_count: Label
var _locker_hint:  Label

# Interact / lore reading overlay.
var _interact_prompt: Label
var _interact_panel: Control
var _interact_title: Label
var _interact_body: Label
var _reading := false

# Feature nodes.
var _glitch: Node    # GlitchOverlay
var _scare:  Node    # ProceduralJumpscare

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL STATE
# ─────────────────────────────────────────────────────────────────────────────
var _spawner:      Node
var _shader_mat:   ShaderMaterial
var _clearing    := false
var _cycle       := 0.0
var _next_clear  := 10.0

## Real-photo jumpscares loaded from assets/textures/jumpscares/
var _scare_photos: Array[Texture2D] = []

var _scare_timer := 0.0    # counts down to next random jumpscare
var _red_flash_a := 0.0    # current red flash alpha

# Lockers this UI is tracking.
var _tracked_lockers: Array = []
var _in_locker: bool = false

var _timer_panel: Panel
var _bars_panel: Panel


# ─────────────────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	add_to_group("hunting_ui")   # lets GameController / Pickup find this node
	GameManager.hunting_tick.connect(_on_tick)
	GameManager.hunting_started.connect(_refresh_role)
	GameManager.role_assigned.connect(func(id, _r):
		if id == NetworkManager.local_peer_id:
			_refresh_role())
	GameManager.player_captured.connect(_on_player_captured)

	_joystick.visible    = TouchInput.enabled
	_grip_banner.visible = false
	_mobile_btns.visible = TouchInput.enabled
	if TouchInput.enabled:
		_wire_mobile_buttons()
		_add_look_region()

	# Blindness vignette shader.
	var sh := load("res://assets/blindness.gdshader")
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	_shader_mat.set_shader_parameter("intensity",    BLIND_INTENSITY)
	_shader_mat.set_shader_parameter("clear_radius", BLIND_RADIUS)
	_shader_mat.set_shader_parameter("tint",         Vector3.ZERO)
	_vignette.material = _shader_mat

	var gc := get_tree().get_first_node_in_group("game_controller")
	if gc:
		_spawner = gc.get_node_or_null("PlayerSpawner")

	_next_clear  = randf_range(8.0, 14.0)
	_scare_timer = randf_range(SCARE_MIN, SCARE_MAX)

	# ── HUD panel backdrops ──
	_build_hud_panels()

	# ── Build in-code UI ──
	_build_hp_bar()
	_build_red_flash()
	_build_killfeed()
	_build_pickup_toast()
	_build_objective_label()
	_build_locker_panel()
	_build_interact_ui()

	# ── Horror subsystems ──
	_scare = load("res://scripts/ProceduralJumpscare.gd").new()
	add_child(_scare)
	_glitch = load("res://scripts/GlitchOverlay.gd").new()
	add_child(_glitch)

	_jumpscare.visible = false
	_jumpscare.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_jumpscare.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	# Load real-photo jumpscares from assets/textures/jumpscares/
	_load_scare_photos()

	# ── Mobile: shift bars above joystick to avoid overlap ──
	if TouchInput.enabled:
		_mobile_adjust_layout()


# ─────────────────────────────────────────────────────────────────────────────
# IN-CODE UI CONSTRUCTION
# ─────────────────────────────────────────────────────────────────────────────

func _build_hp_bar() -> void:
	_hp_label = Label.new()
	_hp_label.layout_mode  = 1
	_hp_label.anchors_preset = 2   # bottom-left
	_hp_label.anchor_top   = 1.0
	_hp_label.anchor_bottom = 1.0
	_hp_label.offset_left  = 28.0
	_hp_label.offset_right = 240.0
	_hp_label.offset_top   = -210.0
	_hp_label.offset_bottom = -190.0
	_hp_label.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))
	_hp_label.add_theme_font_size_override("font_size", 14)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.text = "HP"
	add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.layout_mode  = 1
	_hp_bar.anchors_preset = 2
	_hp_bar.anchor_top   = 1.0
	_hp_bar.anchor_bottom = 1.0
	_hp_bar.offset_left  = 28.0
	_hp_bar.offset_right = 188.0
	_hp_bar.offset_top   = -190.0
	_hp_bar.offset_bottom = -176.0
	_hp_bar.custom_minimum_size = Vector2(160, 14)
	_hp_bar.max_value   = 5.0
	_hp_bar.value       = 5.0
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bar)


func _build_red_flash() -> void:
	_red_flash = ColorRect.new()
	_red_flash.layout_mode  = 1
	_red_flash.anchors_preset = 15
	_red_flash.anchor_right = 1.0
	_red_flash.anchor_bottom = 1.0
	_red_flash.color = Color(0.8, 0.0, 0.0, 1.0)
	_red_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red_flash.modulate.a = 0.0
	add_child(_red_flash)


func _build_killfeed() -> void:
	_killfeed = Label.new()
	_killfeed.layout_mode  = 1
	_killfeed.anchor_left  = 0.5
	_killfeed.anchor_right = 0.5
	_killfeed.offset_left  = -200.0
	_killfeed.offset_right =  200.0
	_killfeed.offset_top   =  96.0
	_killfeed.offset_bottom = 124.0
	_killfeed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_killfeed.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))
	_killfeed.add_theme_font_size_override("font_size", 22)
	_killfeed.modulate.a = 0.0
	_killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_killfeed)


func _build_pickup_toast() -> void:
	_pickup_toast = Label.new()
	_pickup_toast.layout_mode  = 1
	_pickup_toast.anchor_left  = 0.5
	_pickup_toast.anchor_right = 0.5
	_pickup_toast.anchor_top   = 0.5
	_pickup_toast.anchor_bottom = 0.5
	_pickup_toast.offset_left  = -180.0
	_pickup_toast.offset_right  =  180.0
	_pickup_toast.offset_top    = -220.0
	_pickup_toast.offset_bottom = -180.0
	_pickup_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_toast.add_theme_font_size_override("font_size", 28)
	_pickup_toast.modulate.a = 0.0
	_pickup_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pickup_toast)


## Generator objective panel — individual progress bars per generator.
func _build_objective_label() -> void:
	_obj_label = Label.new()
	_obj_label.layout_mode  = 1
	_obj_label.anchor_left  = 0.5
	_obj_label.anchor_right = 0.5
	_obj_label.offset_left  = -200.0
	_obj_label.offset_right =  200.0
	_obj_label.offset_top   =  84.0
	_obj_label.offset_bottom = 110.0
	_obj_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_obj_label.add_theme_color_override("font_color", Color(0.45, 0.7, 0.42))
	_obj_label.add_theme_font_size_override("font_size", 18)
	_obj_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_obj_label.visible = false
	add_child(_obj_label)

	_gen_panel = VBoxContainer.new()
	_gen_panel.layout_mode = 1
	_gen_panel.anchor_left = 1.0
	_gen_panel.anchor_right = 1.0
	_gen_panel.offset_left = -170.0
	_gen_panel.offset_top = 100.0
	_gen_panel.offset_right = -12.0
	_gen_panel.offset_bottom = 400.0
	_gen_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gen_panel.add_theme_constant_override("separation", 3)
	_gen_panel.visible = false
	add_child(_gen_panel)


func _build_locker_panel() -> void:
	_locker_panel = Control.new()
	_locker_panel.layout_mode  = 1
	_locker_panel.anchors_preset = 15
	_locker_panel.anchor_right = 1.0
	_locker_panel.anchor_bottom = 1.0
	_locker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locker_panel.visible = false
	add_child(_locker_panel)

	var bg := ColorRect.new()
	bg.layout_mode  = 1
	bg.anchors_preset = 15
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.03, 0.02, 0.01, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locker_panel.add_child(bg)

	var title := Label.new()
	title.layout_mode  = 1
	title.anchor_left  = 0.5
	title.anchor_right = 0.5
	title.anchor_top   = 0.5
	title.anchor_bottom = 0.5
	title.offset_left  = -220.0
	title.offset_right  = 220.0
	title.offset_top    = -60.0
	title.offset_bottom = -20.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))
	title.add_theme_font_size_override("font_size", 22)
	title.text = "HIDING"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locker_panel.add_child(title)

	_locker_count = Label.new()
	_locker_count.layout_mode  = 1
	_locker_count.anchor_left  = 0.5
	_locker_count.anchor_right = 0.5
	_locker_count.anchor_top   = 0.5
	_locker_count.anchor_bottom = 0.5
	_locker_count.offset_left  = -120.0
	_locker_count.offset_right  = 120.0
	_locker_count.offset_top    = -20.0
	_locker_count.offset_bottom = 40.0
	_locker_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locker_count.add_theme_color_override("font_color", Color(0.95, 0.75, 0.2))
	_locker_count.add_theme_font_size_override("font_size", 44)
	_locker_count.text = "30"
	_locker_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locker_panel.add_child(_locker_count)

	_locker_hint = Label.new()
	_locker_hint.layout_mode  = 1
	_locker_hint.anchor_left  = 0.5
	_locker_hint.anchor_right = 0.5
	_locker_hint.anchor_top   = 0.5
	_locker_hint.anchor_bottom = 0.5
	_locker_hint.offset_left  = -180.0
	_locker_hint.offset_right  = 180.0
	_locker_hint.offset_top    = 40.0
	_locker_hint.offset_bottom = 80.0
	_locker_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_locker_hint.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))
	_locker_hint.add_theme_font_size_override("font_size", 14)
	_locker_hint.text = "PRESS E TO LEAVE EARLY"
	_locker_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_locker_panel.add_child(_locker_hint)


func _build_interact_ui() -> void:
	_interact_prompt = Label.new()
	_interact_prompt.layout_mode = 1
	_interact_prompt.anchor_left = 0.5
	_interact_prompt.anchor_right = 0.5
	_interact_prompt.anchor_top = 0.5
	_interact_prompt.anchor_bottom = 0.5
	_interact_prompt.offset_left = -100.0
	_interact_prompt.offset_right = 100.0
	_interact_prompt.offset_top = 40.0
	_interact_prompt.offset_bottom = 65.0
	_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_interact_prompt.add_theme_font_size_override("font_size", 16)
	_interact_prompt.text = "[E] READ"
	_interact_prompt.visible = false
	_interact_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_prompt)

	_interact_panel = Control.new()
	_interact_panel.layout_mode = 1
	_interact_panel.anchors_preset = 15
	_interact_panel.anchor_right = 1.0
	_interact_panel.anchor_bottom = 1.0
	_interact_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.visible = false
	add_child(_interact_panel)

	var bg := ColorRect.new()
	bg.layout_mode = 1
	bg.anchors_preset = 15
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.04, 0.03, 0.02, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.add_child(bg)

	_interact_title = Label.new()
	_interact_title.layout_mode = 1
	_interact_title.anchor_left = 0.5
	_interact_title.anchor_right = 0.5
	_interact_title.anchor_top = 0.5
	_interact_title.anchor_bottom = 0.5
	_interact_title.offset_left = -300.0
	_interact_title.offset_right = 300.0
	_interact_title.offset_top = -180.0
	_interact_title.offset_bottom = -140.0
	_interact_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_title.add_theme_color_override("font_color", Color(0.85, 0.15, 0.1))
	_interact_title.add_theme_font_size_override("font_size", 24)
	_interact_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.add_child(_interact_title)

	_interact_body = Label.new()
	_interact_body.layout_mode = 1
	_interact_body.anchor_left = 0.5
	_interact_body.anchor_right = 0.5
	_interact_body.anchor_top = 0.5
	_interact_body.anchor_bottom = 0.5
	_interact_body.offset_left = -320.0
	_interact_body.offset_right = 320.0
	_interact_body.offset_top = -120.0
	_interact_body.offset_bottom = 120.0
	_interact_body.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	_interact_body.add_theme_font_size_override("font_size", 16)
	_interact_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_interact_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.add_child(_interact_body)

	var close_hint := Label.new()
	close_hint.layout_mode = 1
	close_hint.anchor_left = 0.5
	close_hint.anchor_right = 0.5
	close_hint.anchor_top = 0.5
	close_hint.anchor_bottom = 0.5
	close_hint.offset_left = -100.0
	close_hint.offset_right = 100.0
	close_hint.offset_top = 140.0
	close_hint.offset_bottom = 170.0
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
	close_hint.add_theme_font_size_override("font_size", 14)
	close_hint.text = "[E] CLOSE"
	close_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interact_panel.add_child(close_hint)


func show_interact_doc(title: String, body: String) -> void:
	_interact_title.text = title
	_interact_body.text = body
	_interact_panel.visible = true
	_reading = true


func hide_interact_doc() -> void:
	_interact_panel.visible = false
	_reading = false


func set_interact_prompt(show: bool) -> void:
	_interact_prompt.visible = show


# ─────────────────────────────────────────────────────────────────────────────
# HUD PANEL BACKDROPS  (horror-styled backing behind timer & status bars)
# ─────────────────────────────────────────────────────────────────────────────

func _build_hud_panels() -> void:
	# Role label backdrop (top-left, behind role text).
	var role_bg := Panel.new()
	role_bg.layout_mode = 1
	role_bg.offset_left = 18.0
	role_bg.offset_top = 14.0
	role_bg.offset_right = 370.0
	role_bg.offset_bottom = 70.0
	role_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_bg.add_theme_stylebox_override("panel", _hud_panel_style(0.55))
	$TopBar.add_child(role_bg)
	$TopBar.move_child(role_bg, 0)

	# Timer backdrop (top-center, behind countdown).
	_timer_panel = Panel.new()
	_timer_panel.layout_mode = 1
	_timer_panel.anchor_left = 0.5
	_timer_panel.anchor_right = 0.5
	_timer_panel.offset_left = -100.0
	_timer_panel.offset_top = 10.0
	_timer_panel.offset_right = 100.0
	_timer_panel.offset_bottom = 86.0
	_timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer_panel.add_theme_stylebox_override("panel", _hud_panel_style(0.7))
	$TopBar.add_child(_timer_panel)
	$TopBar.move_child(_timer_panel, 1)

	# Status bars backdrop (bottom-left, behind HP/stamina/dash/battery bars).
	_bars_panel = Panel.new()
	_bars_panel.layout_mode = 1
	_bars_panel.anchor_top = 1.0
	_bars_panel.anchor_bottom = 1.0
	_bars_panel.offset_left = 18.0
	_bars_panel.offset_top = -220.0
	_bars_panel.offset_right = 240.0
	_bars_panel.offset_bottom = -50.0
	_bars_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars_panel.add_theme_stylebox_override("panel", _hud_panel_style(0.5))
	add_child(_bars_panel)
	move_child(_bars_panel, 2)


static func _hud_panel_style(alpha: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.04, 0.05, alpha)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.85, 0.08, 0.08, 0.3)
	sb.set_corner_radius_all(3)
	return sb


# ─────────────────────────────────────────────────────────────────────────────
# MOBILE LAYOUT ADJUSTMENT
# ─────────────────────────────────────────────────────────────────────────────

const MOBILE_BAR_SHIFT := -175.0

func _mobile_adjust_layout() -> void:
	for node in [_battery, _battery_label, _dash_bar, _dash_label,
				 _throw_bar, _throw_label, _stamina_bar, _stamina_label,
				 _hp_bar, _hp_label]:
		if node != null:
			node.offset_top += MOBILE_BAR_SHIFT
			node.offset_bottom += MOBILE_BAR_SHIFT
	if _bars_panel:
		_bars_panel.offset_top += MOBILE_BAR_SHIFT
		_bars_panel.offset_bottom += MOBILE_BAR_SHIFT
	_hint.visible = false


# ─────────────────────────────────────────────────────────────────────────────
# ROLE REFRESH
# ─────────────────────────────────────────────────────────────────────────────

func _refresh_role() -> void:
	var role := GameManager.get_local_role()
	match role:
		GameManager.Role.HUNTER:
			_role.text = "HUNTER"
			_minimap.visible       = false   # only ghosts get a minimap now
			_crosshair.visible     = true
			_battery.visible       = true
			_battery_label.visible = true
			_dash_bar.visible      = true
			_dash_label.visible    = true
			_throw_bar.visible     = true
			_throw_label.visible   = true
			_stamina_bar.visible   = false
			_stamina_label.visible = false
			_hp_bar.visible        = false
			_hp_label.visible      = false
			_hint.text = "WASD move · LMB stab · RMB throw · Shift dash · Space jump · F light"

		GameManager.Role.HUNTED:
			_role.text = "HUNTED — RUN"
			_minimap.visible       = false
			_crosshair.visible     = false
			_battery.visible       = true
			_battery_label.visible = true
			_dash_bar.visible      = false
			_dash_label.visible    = false
			_throw_bar.visible     = false
			_throw_label.visible   = false
			_stamina_bar.visible   = true
			_stamina_label.visible = true
			_hp_bar.visible        = true
			_hp_label.visible      = true
			_hint.text = "WASD move · Shift sprint · F flashlight · E hide · stand by GENERATORS to escape"

		GameManager.Role.GHOST:
			# Ghosts use the same first-person HUD as runners, but the bottom-left
			# bar is repurposed as the lightning-strike charge / cooldown gauge.
			_role.text = "GHOST — GRIEF THE LIVING"
			_minimap.visible       = true    # ghosts keep the radar to hunt the living
			_crosshair.visible     = true
			_battery.visible       = false
			_battery_label.visible = false
			_dash_bar.visible      = false
			_dash_label.visible    = false
			_throw_bar.visible     = true
			_throw_label.visible   = true
			_stamina_bar.visible   = false
			_stamina_label.visible = false
			_hp_bar.visible        = false
			_hp_label.visible      = false
			_hint.text = "WASD fly · Space up · Shift fall · 2×Space slam down · RMB LIGHTNING · E grab · F summon fake killer"


func _on_tick(seconds_left: int) -> void:
	_timer.text = "%02d:%02d" % [seconds_left / 60, seconds_left % 60]
	var total := GameManager.get_round_seconds()
	_timer_bar.value = float(seconds_left) / float(total) if total > 0 else 0.0


# ─────────────────────────────────────────────────────────────────────────────
# FRAME UPDATE
# ─────────────────────────────────────────────────────────────────────────────

const DASH_DISPLAY_MAX  := 2.0
const THROW_DISPLAY_MAX := 4.0

func _process(delta: float) -> void:
	var player = _spawner.local_player if _spawner else null
	var player_ok := player != null and is_instance_valid(player)

	# ── Bars ──
	if _battery.visible and player_ok and "flash_battery" in player:
		_battery.value = player.flash_battery
		if GameManager.get_local_role() == GameManager.Role.HUNTED:
			_battery_label.text = "LIGHT" if player.flash_battery > 0.15 else "LIGHT — DYING"
		else:
			_battery_label.text = "BATTERY"

	if _dash_bar.visible and player_ok and "_dash_cd" in player:
		var cd: float = player._dash_cd
		_dash_bar.value = clampf(1.0 - cd / DASH_DISPLAY_MAX, 0.0, 1.0)
		_dash_label.text = "DASH — READY" if cd <= 0.0 else "DASH — %.1fs" % cd

	if _throw_bar.visible and player_ok:
		if GameManager.get_local_role() == GameManager.Role.GHOST and "lightning_cd" in player:
			# Ghost: bottom-left bar = lightning charge (when ready) / cooldown.
			var lcd: float = player.lightning_cd
			if lcd > 0.0:
				_throw_bar.value = clampf(1.0 - lcd / 45.0, 0.0, 1.0)
				_throw_label.text = "LIGHTNING — %.0fs" % lcd
			else:
				var charge: float = player.lightning_charge
				_throw_bar.value = charge
				_throw_label.text = "LIGHTNING — DRAWING" if charge > 0.01 else "LIGHTNING — READY"
		elif "throw_cd" in player:
			var tcd: float = player.throw_cd
			_throw_bar.value = clampf(1.0 - tcd / THROW_DISPLAY_MAX, 0.0, 1.0)
			_throw_label.text = "THROW — READY" if tcd <= 0.0 else "THROW — %.1fs" % tcd

	if _stamina_bar.visible and player_ok and "stamina" in player:
		_stamina_bar.value = player.stamina
		_stamina_label.text = "STAMINA" if player.stamina > 0.05 else "STAMINA — EXHAUSTED"

	if _hp_bar.visible and player_ok and "hp" in player:
		_hp_bar.value = float(player.hp)
		var hearts := ""
		for _i in player.hp:
			hearts += "♥"
		_hp_label.text = "HP " + hearts if player.hp > 0 else "HP"

	# ── Generator progress bars ──
	if _gen_panel and _gen_panel.visible:
		_update_gen_progress()

	# ── Interact prompt ──
	if _interact_prompt and not _reading and player_ok:
		var show_prompt := false
		for n in get_tree().get_nodes_in_group("interactable"):
			if is_instance_valid(n) and n.global_position.distance_to(player.global_position) < 3.5:
				show_prompt = true
				break
		_interact_prompt.visible = show_prompt

	# ── Locker check ──
	_update_locker(player, delta)

	# If the player is hiding, skip the scare/vignette processing.
	if _in_locker:
		return

	# ── Random jumpscares (fire for ALL roles, no reason needed) ──
	var hunting := GameManager.current_phase == GameManager.Phase.HUNTING
	if hunting and not GameManager.dev_disable_jumpscares:
		_scare_timer -= delta
		if _scare_timer <= 0.0:
			_scare_timer = randf_range(SCARE_MIN, SCARE_MAX)
			_do_jumpscare()

	# ── Vignette (hunted only) ──
	if _shader_mat == null:
		return
	var role := GameManager.get_local_role()
	if not hunting or role != GameManager.Role.HUNTED:
		_vignette.visible = false
		_set_red_flash(0.0, delta)
		return
	_vignette.visible = true

	_cycle += delta
	if not _clearing and _cycle >= _next_clear:
		_clearing = true
		_cycle    = 0.0
	elif _clearing and _cycle >= CLEAR_HOLD:
		_clearing  = false
		_cycle     = 0.0
		_next_clear = randf_range(8.0, 14.0)

	var redness := _hunter_proximity()
	if player_ok and "fear" in player:
		player.fear = 0.0 if _clearing else redness

	# More gradual approach: vignette starts appearing at full DANGER_DIST
	# and only reaches max darkness when very close.
	var target_int: float = CLEAR_INTENSITY if _clearing \
		else lerpf(BLIND_INTENSITY * 0.5, 0.99, redness)
	var target_rad: float = CLEAR_RADIUS if _clearing \
		else lerpf(CLEAR_RADIUS * 0.7, BLIND_RADIUS, redness)

	var cur_i: float = _shader_mat.get_shader_parameter("intensity")
	var cur_r: float = _shader_mat.get_shader_parameter("clear_radius")
	_shader_mat.set_shader_parameter("intensity",    lerpf(cur_i, target_int, delta * 3.0))
	_shader_mat.set_shader_parameter("clear_radius", lerpf(cur_r, target_rad, delta * 3.0))
	_shader_mat.set_shader_parameter("tint",         Vector3(0.6 * redness, 0.0, 0.0))

	# ── Red danger flash (very close hunter) ──
	var flash_target := clampf((redness - 0.7) / 0.3, 0.0, 1.0) * 0.35
	_set_red_flash(flash_target, delta)

	# ── Glitch when hunter is dangerously close ──
	if redness > 0.82 and _glitch and _glitch.has_method("trigger_burst"):
		if not _glitch._burst_timer > 0.0:
			_glitch.trigger_burst("danger")


func _set_red_flash(target: float, delta: float) -> void:
	_red_flash_a = lerpf(_red_flash_a, target, delta * 5.0)
	if _red_flash:
		_red_flash.modulate.a = _red_flash_a


# ─────────────────────────────────────────────────────────────────────────────
# LOCKER SYSTEM
# ─────────────────────────────────────────────────────────────────────────────

## Register a locker so HuntingUI can track its state (called by MapBase/GameController).
func register_locker(locker: Node) -> void:
	_tracked_lockers.append(locker)
	locker.player_entered.connect(_on_locker_enter)
	locker.player_exited.connect(_on_locker_exit)


func _update_locker(_player, _delta: float) -> void:
	if _in_locker:
		# Update countdown.
		for l in _tracked_lockers:
			if is_instance_valid(l) and l.is_occupied():
				_locker_count.text = "%d" % ceili(l.get_hide_timer())
				break


func _on_locker_enter() -> void:
	_in_locker = true
	_locker_panel.visible = true
	_vignette.visible = false


func _on_locker_exit() -> void:
	_in_locker = false
	_locker_panel.visible = false


# ─────────────────────────────────────────────────────────────────────────────
# JUMPSCARE
# ─────────────────────────────────────────────────────────────────────────────

func _load_scare_photos() -> void:
	const FOLDER := "res://assets/textures/jumpscares"
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var ext := fname.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				var tex := load(FOLDER + "/" + fname) as Texture2D
				if tex != null:
					_scare_photos.append(tex)
		fname = dir.get_next()
	dir.list_dir_end()


func _do_jumpscare() -> void:
	# Always flash a real photo when we have them; fall back to the drawn face.
	if not _scare_photos.is_empty():
		_show_photo_scare(_scare_photos[randi() % _scare_photos.size()])
	else:
		if _scare != null:
			_scare.trigger()
	trigger_glitch("scare")
	# Play a horror SFX at full blast.
	var pool := SCARE_SOUNDS.duplicate()
	pool.shuffle()
	for key in pool:
		var ok := AudioManager.play_sfx(key, 8.0)
		if ok != null:
			break


func _show_photo_scare(tex: Texture2D) -> void:
	_jumpscare.texture = tex
	_jumpscare.modulate.a = 0.0
	_jumpscare.visible = true
	var t := create_tween()
	t.tween_property(_jumpscare, "modulate:a", 1.0, 0.06)
	t.tween_interval(0.38)
	t.tween_property(_jumpscare, "modulate:a", 0.0, 0.22)
	t.tween_callback(func(): _jumpscare.visible = false)


## Called externally (GameController / ShadowEntity) to force an instant scare.
func force_jumpscare() -> void:
	_do_jumpscare()
	_scare_timer = randf_range(SCARE_MIN * 0.8, SCARE_MAX * 0.8)


## Trigger the glitch overlay from outside (mirage vanish, shadow entity, etc.)
func trigger_glitch(kind: String = "ambient") -> void:
	if _glitch and _glitch.has_method("trigger_burst"):
		_glitch.trigger_burst(kind)


# ─────────────────────────────────────────────────────────────────────────────
# PICKUP TOAST
# ─────────────────────────────────────────────────────────────────────────────

func show_pickup_effect(effect: String, good: bool) -> void:
	if _pickup_toast == null:
		return
	_pickup_toast.text = ("✓ " if good else "✗ ") + effect
	_pickup_toast.add_theme_color_override("font_color",
		Color(0.45, 0.7, 0.42) if good else Color(0.85, 0.08, 0.08))
	_pickup_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_pickup_toast, "modulate:a", 0.0, 0.6)


## Red pain pulse when the runner takes a hit; warns harder at low HP.
func flash_damage(hp_left: int) -> void:
	_red_flash_a = maxf(_red_flash_a, 0.55 + (5 - hp_left) * 0.08)
	if hp_left <= 2:
		show_pickup_effect("CRIPPLED — %d HP" % hp_left, false)
	elif hp_left <= 3:
		show_pickup_effect("INJURED — %d HP" % hp_left, false)


## Update the generator objective counter (shown to everyone during the hunt).
func show_objectives(done: int, total: int) -> void:
	if _obj_label == null:
		return
	if total <= 0:
		_obj_label.visible = false
		_gen_panel.visible = false
		return
	_obj_label.visible = true
	_gen_panel.visible = true
	var need: int = GameManager.gen_required
	if done >= need:
		_obj_label.text = "⚙ GENERATORS POWERED — ESCAPE!"
	else:
		_obj_label.text = "⚙ GENERATORS  %d / %d needed  (%d total)" % [done, need, total]
	_ensure_gen_bars(total)


func _ensure_gen_bars(count: int) -> void:
	if _gen_bars.size() >= count:
		return
	for c in _gen_panel.get_children():
		c.queue_free()
	_gen_bars.clear()
	_gen_labels.clear()
	for i in count:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = 0.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(100, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.12, 0.08, 0.08, 0.7)
		bg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		var pct := Label.new()
		pct.text = "0%"
		pct.custom_minimum_size = Vector2(34, 0)
		pct.add_theme_font_size_override("font_size", 10)
		pct.add_theme_color_override("font_color", Color(0.5, 0.42, 0.42))
		pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)
		_gen_panel.add_child(row)
		_gen_bars.append(bar)
		_gen_labels.append(pct)


func _update_gen_progress() -> void:
	var gens := get_tree().get_nodes_in_group("generator")
	for i in mini(gens.size(), _gen_bars.size()):
		var g = gens[i]
		var p: float = g.progress if "progress" in g else 0.0
		var d: bool = g.done if "done" in g else false
		_gen_bars[i].value = p
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(2)
		if d:
			_gen_labels[i].text = "OK"
			_gen_labels[i].add_theme_color_override("font_color", Color(0.35, 0.85, 0.4))
			sb.bg_color = Color(0.12, 0.42, 0.16)
		elif p > 0.01:
			_gen_labels[i].text = "%d%%" % int(p * 100.0)
			_gen_labels[i].add_theme_color_override("font_color", Color(0.9, 0.7, 0.15))
			sb.bg_color = Color(0.75, 0.5, 0.06)
		else:
			_gen_labels[i].text = "--"
			_gen_labels[i].add_theme_color_override("font_color", Color(0.4, 0.3, 0.3))
			sb.bg_color = Color(0.35, 0.08, 0.08)
		_gen_bars[i].add_theme_stylebox_override("fill", sb)


## Killer scan feedback. is_hunter=true → "TARGETS PINGED"; false → runner warning.
func show_scan_alert(is_hunter: bool) -> void:
	if _pickup_toast == null:
		return
	if is_hunter:
		_pickup_toast.text = "◎ TARGETS PINGED"
		_pickup_toast.add_theme_color_override("font_color", Color(0.85, 0.18, 0.18))
	else:
		_pickup_toast.text = "⚠ YOU'VE BEEN SPOTTED"
		_pickup_toast.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))
		_set_red_flash(0.4, 1.0)   # brief panic flash for the runner
	_pickup_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.5)
	t.tween_property(_pickup_toast, "modulate:a", 0.0, 0.6)


# ─────────────────────────────────────────────────────────────────────────────
# PROXIMITY
# ─────────────────────────────────────────────────────────────────────────────

func _hunter_proximity() -> float:
	if _spawner == null or _spawner.local_player == null:
		return 0.0
	var here: Vector3 = _spawner.local_player.global_position
	var best := 9999.0
	for id in _spawner.remotes:
		var rp = _spawner.remotes[id]
		if rp.role == GameManager.Role.HUNTER:
			best = minf(best, here.distance_to(rp.global_position))
	if best >= DANGER_DIST:
		return 0.0
	return clampf(1.0 - best / DANGER_DIST, 0.0, 1.0)


# ─────────────────────────────────────────────────────────────────────────────
# MOBILE CONTROLS
# ─────────────────────────────────────────────────────────────────────────────

func _wire_mobile_buttons() -> void:
	var light_btn:  Button = _mobile_btns.get_node("FlashlightBtn")
	var jump_btn:   Button = _mobile_btns.get_node("JumpBtn")
	var sprint_btn: Button = _mobile_btns.get_node("SprintBtn")
	var dash_btn:   Button = _mobile_btns.get_node("DashBtn")
	var throw_btn:  Button = _mobile_btns.get_node("ThrowBtn")

	light_btn.button_down.connect(func(): Input.action_press("flashlight"))
	light_btn.button_up.connect(func():   Input.action_release("flashlight"))
	jump_btn.button_down.connect(func(): Input.action_press("jump"))
	jump_btn.button_up.connect(func():   Input.action_release("jump"))
	sprint_btn.button_down.connect(func(): Input.action_press("sprint"))
	sprint_btn.button_up.connect(func():   Input.action_release("sprint"))
	dash_btn.button_down.connect(func(): Input.action_press("dash"))
	dash_btn.button_up.connect(func():   Input.action_release("dash"))
	throw_btn.button_down.connect(func(): Input.action_press("throw"))
	throw_btn.button_up.connect(func():   Input.action_release("throw"))

	GameManager.role_assigned.connect(func(id, r):
		if id != NetworkManager.local_peer_id:
			return
		var is_hunter: bool = (r == GameManager.Role.HUNTER)
		var is_ghost: bool = (r == GameManager.Role.GHOST)
		light_btn.visible  = not is_ghost
		dash_btn.visible   = is_hunter
		throw_btn.visible  = is_hunter
		sprint_btn.visible = not is_hunter and not is_ghost)


func _add_look_region() -> void:
	var region: Control = load("res://scripts/MobileLookRegion.gd").new()
	add_child(region)


# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC (called from other scripts)
# ─────────────────────────────────────────────────────────────────────────────

func show_grip(active: bool) -> void:
	_grip_banner.visible = active
	_grip_banner.text = "GRABBED — RUN!" if active else ""


func show_revive(active: bool, t01: float) -> void:
	_grip_banner.visible = active
	if active:
		_grip_banner.text = "REVIVING SURVIVOR…  %d%%" % int(t01 * 100.0)


# ─────────────────────────────────────────────────────────────────────────────
# KILL-FEED
# ─────────────────────────────────────────────────────────────────────────────

func _on_player_captured(peer_id: int, _by_peer_id: int) -> void:
	if _killfeed == null:
		return
	var who := NetworkManager.get_peer_name(peer_id).to_upper()
	_killfeed.text = "%s WAS CAUGHT" % who
	_killfeed.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_killfeed, "modulate:a", 0.0, 0.8)
