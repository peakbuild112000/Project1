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
		"move_left", "move_right", "carry", "fix_prop", "jetpack", "bandage",
		"drop_jetpack", "winch_up", "winch_down", "tail_stretch", "chat", "scoreboard",
	]
	for action in actions:
		check(InputMap.has_action(action), "Missing input action: " + action)

	var net := root.get_node_or_null("Net")
	check(net != null, "Net autoload missing")
	if net != null:
		check(not net.has_method("start_solo"), "Solo match entry point must be removed")
		for method in ["create_server", "join_server", "create_web_room", "join_web_room", "start_match", "leave", "set_ready", "send_chat", "player_data", "set_character_type"]:
			check(net.has_method(method), "Net missing method: " + method)
		var rtc := net.get_node_or_null("WebRTCRoom")
		check(rtc != null, "Net missing WebRTCRoom transport")
		if rtc != null:
			for method in ["start_host", "start_client", "close_room", "get_multiplayer_peer"]:
				check(rtc.has_method(method), "WebRTCRoom missing method: " + method)

	var climber_scene := load("res://scenes/climber.tscn") as PackedScene
	if climber_scene != null:
		var climber := climber_scene.instantiate() as Node
		root.add_child(climber)
		for method in ["configure", "respawn_at", "apply_hazard", "get_state", "add_bandage", "use_bandage", "use_bandage_on_target", "find_bandage_target", "revive_with_bandage", "set_persistent_unconscious", "apply_fall_impact", "usable_max_stamina", "set_stamina_lock", "get_total_weight", "remove_jetpack", "find_fix_target", "is_critically_damaged", "get_death_time_left", "is_strong", "is_elastic", "can_carry_climber", "launch_from_carry"]:
			check(climber.has_method(method), "Climber missing method: " + method)
		for prop in ["peer_id", "display_name", "player_color", "character_type", "current_stamina", "max_stamina", "stamina_lock", "stretch", "ragdoll_active", "unconscious", "persistent_unconscious", "unconscious_time", "death_progress", "fall_time", "highest_y", "checkpoint_y", "is_local", "injury", "bandages"]:
			check(climber.get(prop) != null or climber.get_property_list().any(func(p): return p.name == prop), "Climber missing property: " + prop)
		for sig in ["stamina_changed", "stamina_lock_changed", "stretch_changed", "ragdoll_started", "ragdoll_ended", "unconscious_changed", "revived", "died", "checkpoint_reached", "summit_reached", "bandages_changed", "injury_changed", "fall_damage", "notice_requested"]:
			check(climber.has_signal(sig), "Climber missing signal: " + sig)
		check(int(climber.get("bandages")) == 0, "Climbers must start without bandages")
		check(float(climber.get("harpoon_reach")) <= 14.0, "Arm reach must stay reduced")
		check(climber.find_child("LeftFoot", true, false) != null, "Climber missing left foot")
		check(climber.find_child("RightFoot", true, false) != null, "Climber missing right foot")
		var tail: Node = null
		for node in climber.find_children("*", "", true, false):
			if node.has_method("set_carrier") and node.has_method("can_be_grappled"):
				tail = node
				break
		check(tail != null, "Climber missing grappling tail")
		if tail != null:
			check(tail.has_method("set_carrier"), "Tail cannot be carried")
			check(tail.has_method("can_be_grappled"), "Tail cannot be grappled")
		check(climber.has_method("_hands_full_with_bucket"), "Bucket two-hand hold missing")
		check(float(climber.get("unconscious_death_time")) > 0.0, "Unconscious death timer missing")
		check(int(climber.get("character_type")) == CharacterType.STRONG, "Climbers default to Strong")
		check(bool(climber.call("is_strong")), "Default climber is not Strong")
		check(not bool(climber.call("is_elastic")), "Default climber is Elastic")
		check(float(climber.get("tail_tension_drain")) > 0.0, "Tail tension drain missing")
		climber.call("set_character_type", CharacterType.ELASTIC)
		check(bool(climber.call("is_elastic")), "set_character_type did not switch to Elastic")
		check(int(climber.call("get_state").get("character_type", -1)) == CharacterType.ELASTIC, "Type not replicated in state")
		climber.call("set_character_type", CharacterType.STRONG)
		climber.call("set_stamina_lock", 0.0)
		climber.call("apply_fall_impact", 14.0, 0.0)
		var short_lock: float = float(climber.get("stamina_lock"))
		climber.call("set_stamina_lock", 0.0)
		climber.call("apply_fall_impact", 14.0, 2.0)
		check(float(climber.get("stamina_lock")) > short_lock, "Long falls must lock more stamina than short falls")
		climber.call("_reset_fall_state")
		climber.set("linear_velocity", Vector3(0.0, -5.0, 0.0))
		climber.call("_update_fall_dynamics", 0.5, false)
		check(float(climber.get("fall_time")) > 0.0, "Airborne time is not tracked")
		check(float(climber.get("gravity_scale")) > 1.0, "Long falls do not accelerate gravity")
		check(float(climber.get("linear_damp")) < float(climber.get("normal_linear_damp")), "Long falls do not reduce drag")
		climber.call("_reset_fall_state")
		check(is_equal_approx(float(climber.get("gravity_scale")), 1.0), "Fall state was not reset")
		var sync: MultiplayerSynchronizer = null
		for child in climber.find_children("*", "MultiplayerSynchronizer", true, false):
			sync = child as MultiplayerSynchronizer
			break
		check(sync != null, "Climber missing MultiplayerSynchronizer")
		if sync != null:
			check(sync.replication_config.get_properties().size() >= 8, "Synchronizer has too few properties")

	var prop_script = load("res://scripts/game/prop.gd")
	if prop_script != null:
		var prop_instance = prop_script.new()
		check(prop_instance.has_method("set_fixed"), "ClimbProp missing set_fixed")
		check(prop_instance.has_signal("fixed_changed"), "ClimbProp missing fixed_changed")
		prop_instance.free()

	var manager_script = load("res://scripts/game/game_manager.gd")
	if manager_script != null:
		var manager_instance = manager_script.new()
		check(manager_instance.has_method("request_bandage_revive"), "GameManager missing bandage revive request")
		check(manager_instance.has_method("_find_tail_by_owner"), "GameManager missing tail lookup")
		check(manager_instance.has_method("is_strong_climber"), "GameManager missing Strong check")
		check(manager_instance.has_method("is_elastic_climber"), "GameManager missing Elastic check")
		manager_instance.free()

	for script_path in ["res://scripts/network/network_manager.gd", "res://scripts/ui/main_menu.gd"]:
		var file := FileAccess.open(script_path, FileAccess.READ)
		check(file != null, "Cannot read " + script_path)
		if file != null:
			var source := file.get_as_text()
			check(not source.contains("start_solo"), "Solo mode still present in " + script_path)
			file.close()

	for model in [
		"res://assets/models/jetpack.glb",
		"res://assets/models/trampoline.glb",
		"res://assets/models/plank.glb",
		"res://assets/models/crate.glb",
		"res://assets/models/bandage.glb",
		"res://assets/models/cabin.glb",
		"res://assets/models/rock.glb",
		"res://assets/models/enemy.glb",
	]:
		check(ResourceLoader.exists(model), "Missing model: " + model)

	print("CLIMB VALIDATION failures=", failures)
	quit(0 if failures == 0 else 1)
