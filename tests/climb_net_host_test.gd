extends SceneTree

var net: Node
var step: int = 0
var timer: float = 0.0
var heartbeat: float = 0.0

func _report(tag: String) -> void:
	var game := root.get_node_or_null("Game")
	print(tag, " game=", game)
	if game == null:
		return
	var states: Dictionary = game.get("_players_state")
	print(tag, " states=", states.keys())
	var players_root: Node = game.get_node("Players")
	var names: Array[String] = []
	for child in players_root.get_children():
		names.append(child.name)
	print(tag, " climbers=", names)
	print(tag, " phase=", game.get("_phase"), " ready=", game.get("_ready_peers"))

func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(delta: float) -> bool:
	timer += delta
	heartbeat += delta
	if heartbeat >= 2.0:
		heartbeat = 0.0
		print("HOST heartbeat step=", step, " players=", (net.players.size() if net != null else -1))
	if net == null:
		var candidate := root.get_node_or_null("Net")
		if candidate != null and root.get_node_or_null("MainMenu") != null:
			net = candidate
			net.create_server("Host", 4, 7792)
			print("HOST peer=", net.peer_id, " host=", net.is_host)
			net.match_started.connect(func() -> void: print("HOST match_started"))
			net.lobby_changed.connect(func() -> void:
				for id in net.players.keys():
					print("HOST lobby ", id, "=", str(net.player_data(int(id)).get("name", "?"))))
			step = 1
		return false
	match step:
		1:
			if net.players.size() >= 2:
				print("HOST roster=", net.players.keys())
				for id in net.players.keys():
					print("HOST name ", id, "=", str(net.player_data(int(id)).get("name", "?")))
				net.start_match()
				step = 2
				timer = 0.0
		2:
			if timer > 8.0:
				for id in net.players.keys():
					print("HOST final name ", id, "=", str(net.player_data(int(id)).get("name", "?")))
				_report("HOST")
				var game := root.get_node_or_null("Game")
				if game != null:
					print("HOST race phase=", game.get("_phase"), " winner=", game.get("_winner_id"), " reason=", game.get("_end_reason"))
				quit(0)
	return false
