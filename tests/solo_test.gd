extends SceneTree

var failures: int = 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		push_error(msg)
		failures += 1


func _initialize() -> void:
	change_scene_to_file("res://scenes/main_menu.tscn")
	await process_frame
	var net: Node = root.get_node_or_null("Net")
	check(net != null, "Net autoload missing")
	check(net != null and not net.has_method("start_solo"), "Solo match entry point must be removed")
	for button in root.find_children("*", "Button", true, false):
		var label := str((button as Button).text).to_upper()
		check(not label.contains("SOLO"), "Menu still exposes a solo button: " + label)
	print("NO SOLO failures=", failures)
	quit(0 if failures == 0 else 1)
