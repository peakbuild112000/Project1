extends SceneTree

var net: Node
var step: int = 0
var timer: float = 0.0
var t: float = 0.0
var sample_timer: float = 0.0
var samples: int = 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(delta: float) -> bool:
	timer += delta
	t += delta
	if net == null:
		var candidate := root.get_node_or_null("Net")
		if candidate != null and root.get_node_or_null("MainMenu") != null:
			net = candidate
			net.create_server("Host", 4, 7795)
			step = 1
		return false
	match step:
		1:
			if net.players.size() >= 2 or timer > 8.0:
				net.start_match()
				step = 2
				timer = 0.0
		2:
			if root.get_node_or_null("Game") != null:
				var sync = root.get_node_or_null("Game/Players/Climber_1/StateSync")
				if sync != null:
					var cfg = sync.get("replication_config")
					print("HOST SYNC props=", cfg.get_properties(), " authority=", sync.get_multiplayer_authority(), " enabled=", (sync.call("is_enabled") if sync.has_method("is_enabled") else true))
				step = 3
				timer = 0.0
		3:
			var game := root.get_node_or_null("Game")
			if game != null:
				var climber = game.get_node("Players").get_node_or_null("Climber_1")
				if climber != null:
					climber.linear_velocity = Vector3(sin(t * 1.3) * 3.0, 0.0, cos(t * 1.1) * 1.5)
					climber.replicated_yaw = sin(t)
					climber.current_stamina = 50.0 + sin(t) * 20.0
					sample_timer += delta
					if sample_timer >= 0.05:
						sample_timer = 0.0
						var p: Vector3 = climber.global_position
						print("HOST y=%.3f x=%.3f z=%.3f" % [p.y, p.x, p.z])
						samples += 1
			if timer > 14.0:
				quit(0)
	return false
