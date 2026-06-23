extends Node
## Main — top-level glue. Connects the gameplay world (GhostController) to the
## HUD (HuntingUI grip banner) so the two subtrees stay decoupled otherwise.

@onready var _ghost: Node = $World/GhostController
@onready var _revive: Node = $World/ReviveController
@onready var _hunting_ui: Control = $UI/UIManager/HuntingUI


func _ready() -> void:
	_ghost.local_gripped.connect(func(_id): _hunting_ui.show_grip(true))
	_ghost.local_escaped.connect(func(): _hunting_ui.show_grip(false))
	_revive.revive_progress.connect(func(target, t): _hunting_ui.show_revive(target != -1, t))
