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
	print(tag, " phase=", game.get("_phase"))

func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")

func _process(delta: float) -> bool:
	timer += delta
	heartbeat += delta
	if heartbeat >= 2.0:
		heartbeat = 0.0
		print("CLIENT heartbeat step=", step, " peer=", (net.peer_id if net != null else -1))
	if net == null:
		var candidate := root.get_node_or_null("Net")
		if candidate != null and root.get_node_or_null("MainMenu") != null:
			net = candidate
			net.connection_failed.connect(func(msg: String) -> void: print("CLIENT failed=", msg))
			net.join_server("Guest", "127.0.0.1", 7792)
			print("CLIENT join requested")
			step = 1
		return false
	match step:
		1:
			if net.peer_id > 0 or timer > 8.0:
				print("CLIENT peer=", net.peer_id, " roster=", net.players.keys())
				for id in net.players.keys():
					print("CLIENT name ", id, "=", str(net.player_data(int(id)).get("name", "?")))
				step = 2
				timer = 0.0
		2:
			if root.get_node_or_null("Game") != null:
				print("CLIENT game loaded after=", timer)
				step = 3
				timer = 0.0
			elif timer > 15.0:
				print("CLIENT game NEVER loaded")
				_report("CLIENT")
				quit(1)
		3:
			if timer > 2.0:
				for id in net.players.keys():
					print("CLIENT final name ", id, "=", str(net.player_data(int(id)).get("name", "?")))
				var game := root.get_node_or_null("Game")
				var local_id: int = net.peer_id
				var climber = game.get_node("Players").get_node("Climber_%d" % local_id)
				print("CLIENT racer=", local_id, " altitude=", climber.get("highest_y"), " jetpack=", climber.get("has_jetpack"))
				print("CLIENT race phase=", game.get("_phase"))
				_report("CLIENT")
				quit(0)
	return false
