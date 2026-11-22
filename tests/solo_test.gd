extends SceneTree

func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await process_frame
	var net: Node = root.get_node_or_null("Net")
	net.set("player_name", "Solo")
	net.call("start_solo")
	await process_frame
	await process_frame
	var game: Node = root.get_node_or_null("Game")
	var climbers: Node = game.get_node_or_null("Players") if game != null else null
	print("SOLO game=", game, " climbers=", climbers.get_child_count() if climbers != null else -1, " peer=", net.get("peer_id"), " host=", net.get("is_host"), " offline=", (net.get("multiplayer") as Node))
	quit(0)
