extends Control
## PauseMenu — Esc opens an overlay during a match: Resume / Leave / Quit.
## Pauses the tree while open and frees/recaptures the mouse appropriately.
##
## WEB GOTCHA: browsers reserve Esc to exit pointer-lock and do NOT forward that
## keypress to the game — so on the web build pressing Esc silently releases the
## cursor but never triggers our _input handler. To stay robust we ALSO watch for
## the pointer being released during an active hunt and surface the menu
## automatically (this doubles as auto-pause on alt-tab / focus loss on desktop).

@onready var _resume: Button = $Center/Panel/VBox/Resume
@onready var _leave: Button = $Center/Panel/VBox/Leave
@onready var _quit: Button = $Center/Panel/VBox/Quit

## Brief window after closing during which auto-reopen is suppressed (gives the
## browser time to actually re-engage pointer-lock after the Resume click).
var _reopen_guard := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep working while paused
	visible = false
	_resume.pressed.connect(func(): set_open(false))
	_leave.pressed.connect(_on_leave)
	_quit.pressed.connect(func(): get_tree().quit())
	# Suppress auto-open briefly at hunt start so the menu can't pop up in the
	# frame before the player controller captures the cursor. Also covers late
	# joiners who enter HUNTING via phase_changed (not hunting_started).
	GameManager.hunting_started.connect(func(): _reopen_guard = 2.0)
	GameManager.phase_changed.connect(func(p, _o):
		if p == GameManager.Phase.HUNTING:
			_reopen_guard = 2.0)
	UiFx.wire_buttons(self)


func _input(event: InputEvent) -> void:
	# _input (not _unhandled_input) so nothing — captured mouse, focused UI — can
	# swallow Esc before we get it.
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible or GameManager.current_phase == GameManager.Phase.HUNTING:
		set_open(not visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _reopen_guard > 0.0:
		_reopen_guard -= delta
	# Surface the menu if the pointer gets freed mid-hunt without us asking — the
	# main case being a browser eating Esc to release pointer-lock. Without this,
	# web players could never open the menu (and clicks would just re-lock).
	if TouchInput.enabled:
		return
	if visible or get_tree().paused or _reopen_guard > 0.0:
		return
	if GameManager.current_phase != GameManager.Phase.HUNTING:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		set_open(true)


func set_open(open: bool) -> void:
	visible = open
	get_tree().paused = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_reopen_guard = 0.6   # don't auto-reopen while pointer-lock re-engages
		if GameManager.current_phase == GameManager.Phase.HUNTING and not TouchInput.enabled:
			# All in-hunt roles (hunter, runner, ghost) are first-person now.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_leave() -> void:
	# Return to lobby first so phase != HUNTING, otherwise set_open()/_process would
	# immediately recapture the cursor on the way out.
	GameManager.return_to_lobby()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
