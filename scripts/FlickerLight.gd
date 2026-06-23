extends OmniLight3D
## FlickerLight — a light bulb that flickers like failing wiring.
##
## Used by MapBase for the eerie accent lights. It randomly dims, brightens,
## and occasionally cuts out for a beat, so the arena never feels statically lit.
## During the active hunt the flicker gets more agitated.

var _base_energy: float = 0.6   # the "normal" brightness, captured at startup
var _t: float = 0.0             # time since the last flicker change
var _next: float = 0.0          # how long to hold the current brightness


func _ready() -> void:
	_base_energy = light_energy
	_next = randf_range(0.1, 1.5)
	# Stagger each bulb so they don't all flicker in sync.
	_t = randf_range(0.0, _next)


func _process(delta: float) -> void:
	_t += delta
	if _t < _next:
		return
	_t = 0.0

	# Flicker harder/faster while a hunt is underway.
	var agitated := GameManager.current_phase == GameManager.Phase.HUNTING
	_next = randf_range(0.04, 1.2) if agitated else randf_range(0.2, 1.8)

	var roll := randf()
	var blackout_chance := 0.28 if agitated else 0.15
	if roll < blackout_chance:
		light_energy = _base_energy * randf_range(0.02, 0.25)   # near-blackout
	else:
		light_energy = _base_energy * randf_range(0.7, 1.2)     # normal-ish wobble
