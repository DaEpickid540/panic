class_name UiFx
extends RefCounted
## Tiny UI animation helpers shared across screens. Keeps all motion <= 100 ms
## for a responsive feel (per the UX constraints).

## Press feedback: scale to 0.95 on down, back to 1.0 on release.
static func add_press_anim(b: BaseButton) -> void:
	b.button_down.connect(func(): _scale(b, 0.95))
	b.button_up.connect(func(): _scale(b, 1.0))


## Apply press feedback to every Button under `root`.
static func wire_buttons(root: Node) -> void:
	for n in root.find_children("*", "BaseButton", true, false):
		add_press_anim(n)


static func _scale(b: Control, s: float) -> void:
	b.pivot_offset = b.size * 0.5
	b.create_tween().tween_property(b, "scale", Vector2(s, s), 0.1)
