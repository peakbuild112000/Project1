extends SceneTree

var net: Node
var step: int = 0
var timer: float = 0.0
var sample_timer: float = 0.0
var samples: int = 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(delta: float) -> bool:
	timer += delta
	if net == null:
		var candidate := root.get_node_or_null("Net")
		if candidate != null and root.get_node_or_null("MainMenu") != null:
			net = candidate
			net.join_server("Guest", "127.0.0.1", 7795)
			step = 1
		return false
	match step:
		1:
			if net.peer_id > 0 or timer > 8.0:
				step = 2
				timer = 0.0
		2:
			if root.get_node_or_null("Game") != null:
				step = 3
				timer = 0.0
		3:
			if timer > 1.0:
				sample_timer += delta
				if sample_timer >= 0.05:
					sample_timer = 0.0
					var game := root.get_node_or_null("Game")
					if game != null:
						var remote = game.get_node("Players").get_node_or_null("Climber_1")
						if remote != null:
							var p: Vector3 = remote.global_position
							var body = remote.get("body_mesh")
							var v: Vector3 = remote.linear_velocity
							var yaw: float = remote.replicated_yaw
							var target: Vector3 = remote.replicated_position
							print("VIS y=%.3f x=%.3f tgt=%.3f,%.3f vel=%.2f,%.2f yaw=%.2f peer=%d local=%s freeze=%s body=%s rag=%s dead=%s" % [
								p.y, p.x, target.y, target.x, v.x, v.z, yaw, int(remote.get("peer_id")), str(remote.get("is_local")),
								str(remote.get("freeze")), str(body.visible if body != null else false),
								str(remote.get("ragdoll_active")), str(remote.get("dead"))
							])
							samples += 1
							if samples >= 40:
								quit(0)
	return false
