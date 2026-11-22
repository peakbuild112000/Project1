extends SceneTree

const ROOT := "res://"

var failures: int = 0

func fail(msg: String) -> void:
	push_error(msg)
	failures += 1

func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)

func _initialize() -> void:
	await process_frame

	for scene_path in [
		"res://scenes/main_menu.tscn",
		"res://scenes/game.tscn",
		"res://scenes/climber.tscn",
	]:
		var packed := load(scene_path) as PackedScene
		check(packed != null, "Cannot load " + scene_path)
		if packed == null:
			continue
		var inst := packed.instantiate()
		check(inst != null, "Cannot instantiate " + scene_path)
		if inst != null:
			inst.free()

	var actions := [
		"arm_left", "arm_right", "jump", "move_forward", "move_back",
		"move_left", "move_right", "carry", "jetpack", "winch_up",
		"winch_down", "chat", "scoreboard",
	]
	for action in actions:
		check(InputMap.has_action(action), "Missing input action: " + action)

	var net := root.get_node_or_null("Net")
	check(net != null, "Net autoload missing")
	if net != null:
		for method in ["create_server", "join_server", "start_match", "leave", "set_ready", "send_chat", "player_data"]:
			check(net.has_method(method), "Net missing method: " + method)

	var climber_scene := load("res://scenes/climber.tscn") as PackedScene
	if climber_scene != null:
		var climber := climber_scene.instantiate() as Node
		root.add_child(climber)
		for method in ["configure", "respawn_at", "apply_hazard", "get_state"]:
			check(climber.has_method(method), "Climber missing method: " + method)
		for prop in ["peer_id", "display_name", "player_color", "current_stamina", "max_stamina", "stretch", "ragdoll_active", "highest_y", "checkpoint_y", "lives", "is_local"]:
			check(climber.get(prop) != null or climber.get_property_list().any(func(p): return p.name == prop), "Climber missing property: " + prop)
		for sig in ["stamina_changed", "stretch_changed", "ragdoll_started", "ragdoll_ended", "died", "checkpoint_reached", "summit_reached"]:
			check(climber.has_signal(sig), "Climber missing signal: " + sig)
		var sync: MultiplayerSynchronizer = null
		for child in climber.find_children("*", "MultiplayerSynchronizer", true, false):
			sync = child as MultiplayerSynchronizer
			break
		check(sync != null, "Climber missing MultiplayerSynchronizer")
		if sync != null:
			check(sync.replication_config.get_properties().size() >= 8, "Synchronizer has too few properties")

	for model in [
		"res://assets/models/jetpack.glb",
		"res://assets/models/trampoline.glb",
		"res://assets/models/plank.glb",
		"res://assets/models/crate.glb",
	]:
		check(ResourceLoader.exists(model), "Missing model: " + model)

	print("CLIMB VALIDATION failures=", failures)
	quit(0 if failures == 0 else 1)
