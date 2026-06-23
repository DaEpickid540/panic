extends Node3D
## CaptureDetector  (attached to the local HUNTER player by GameController)
##
## Raycasts forward from the FPS camera (5 m). On the "capture" action, if the
## ray hits a hunted player's body, the capture is instant: hunted -> ghost.
## The capture SFX is heard by ALL players (each client plays it when it sees
## the role flip via GameManager.player_captured -> GameController).

const RANGE := 5.0
const PLAYERS_MASK := 1 << 1   # physics layer 2 = "players"

var player: CharacterBody3D
var camera: Camera3D


func setup(local_player: CharacterBody3D) -> void:
	player = local_player
	camera = player.get_node_or_null("Head/FPSCamera")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("capture"):
		# Swing the blade first; the capture only lands if the swing was off
		# cooldown, so the hit is paced by the swing animation.
		if player and player.has_method("swing_blade"):
			if player.swing_blade():
				try_capture()
		else:
			try_capture()


func try_capture() -> void:
	if camera == null or GameManager.get_local_role() != GameManager.Role.HUNTER:
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to, PLAYERS_MASK)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var rp = hit.collider.get_parent()    # Body -> RemotePlayer
	if rp == null or not ("peer_id" in rp):
		return
	if rp.role == GameManager.Role.HUNTED:
		# Deal ONE hit (3 to down a runner) — routed so it works on bots locally
		# and on human runners over the network. No more one-shot captures.
		GameManager.grief_runner(rp, NetworkManager.local_peer_id, 1, 0.0)
