extends SceneTree

## Static and API contract for the competitive first-to-summit race.

var failures: int = 0


func fail(msg: String) -> void:
	push_error(msg)
	failures += 1


func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)


func source_has(path: String, token: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		fail("Cannot read " + path)
		return false
	var text := file.get_as_text()
	file.close()
	return text.contains(token)


func property_names(node: Node) -> Array[String]:
	var names: Array[String] = []
	for item in node.get_property_list():
		names.append(str((item as Dictionary).get("name", "")))
	return names


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
		"move_left", "move_right", "jetpack", "drop_jetpack",
		"winch_up", "winch_down", "chat", "scoreboard",
	]
	for action in actions:
		check(InputMap.has_action(action), "Missing input action: " + action)
	for action in ["carry", "fix_prop", "bandage", "tail_stretch"]:
		check(not InputMap.has_action(action), "Obsolete input action still exists: " + action)

	var net := root.get_node_or_null("Net")
	check(net != null, "Net autoload missing")
	if net != null:
		for method in ["create_server", "join_server", "create_web_room", "join_web_room", "start_match", "leave", "set_ready", "send_chat", "player_data"]:
			check(net.has_method(method), "Net missing method: " + method)
		for method in ["start_solo", "set_character_type", "has_both_classes", "class_for_join_index", "assign_character_types"]:
			check(not net.has_method(method), "Obsolete Net method still exists: " + method)
		check(int(net.get("port")) == 7777, "Desktop ENet port must be 7777")
		check(int(net.get("max_players")) == 4, "Race lobby must cap at four players")
		check(net.has_signal("match_start_rejected"), "Net missing match_start_rejected signal")
		var net_source := "res://scripts/network/network_manager.gd"
		check(source_has(net_source, "players.size() < 2"), "Start gate must use the player count")
		for token in ["start_solo", "character_type", "has_both_classes", "assign_character_types", "ENetMultiplayerPeer.create_server()"]:
			check(not source_has(net_source, token), "Obsolete Net token still exists: " + token)
		var rtc := net.get_node_or_null("WebRTCRoom")
		check(rtc != null, "Net missing WebRTCRoom transport")
		if rtc != null:
			for method in ["start_host", "start_client", "close_room", "get_multiplayer_peer"]:
				check(rtc.has_method(method), "WebRTCRoom missing method: " + method)

	var climber_scene := load("res://scenes/climber.tscn") as PackedScene
	if climber_scene != null:
		var climber := climber_scene.instantiate() as Node
		root.add_child(climber)
		for method in ["configure", "respawn_at", "apply_hazard", "apply_bounce", "get_state", "usable_max_stamina", "get_total_weight", "equip_jetpack", "remove_jetpack", "can_climb", "start_ragdoll", "recover"]:
			check(climber.has_method(method), "Climber missing method: " + method)
		for method in ["add_bandage", "use_bandage", "use_bandage_on_target", "set_character_type", "apply_fall_impact", "set_stamina_lock", "find_fix_target", "can_carry_climber", "_request_carry", "_hands_full_with_bucket"]:
			check(not climber.has_method(method), "Obsolete climber method still exists: " + method)
		var props := property_names(climber)
		for prop in ["peer_id", "display_name", "player_color", "current_stamina", "max_stamina", "ragdoll_active", "fall_time", "highest_y", "checkpoint_y", "is_local", "has_jetpack", "jetpack_fuel"]:
			check(props.has(prop), "Climber missing property: " + prop)
		for prop in ["character_type", "stamina_lock", "stretch", "unconscious", "persistent_unconscious", "injury", "bandages", "carry_kind", "carried_by_peer"]:
			check(not props.has(prop), "Obsolete climber property still exists: " + prop)
		for sig in ["stamina_changed", "ragdoll_started", "ragdoll_ended", "died", "checkpoint_reached", "summit_reached", "jetpack_changed", "notice_requested"]:
			check(climber.has_signal(sig), "Climber missing signal: " + sig)
		for sig in ["stamina_lock_changed", "stretch_changed", "unconscious_changed", "revived", "bandages_changed", "injury_changed", "fall_damage", "carry_changed"]:
			check(not climber.has_signal(sig), "Obsolete climber signal still exists: " + sig)
		check(is_equal_approx(float(climber.call("usable_max_stamina")), float(climber.get("max_stamina"))), "Falls must not lock stamina")
		check(float(climber.get("harpoon_reach")) <= 14.0, "Arm reach must stay reduced")
		check(climber.find_child("LeftFoot", true, false) != null, "Climber missing left foot")
		check(climber.find_child("RightFoot", true, false) != null, "Climber missing right foot")
		check(climber.find_child("Tail", true, false) == null, "Class rope tail must be removed")
		var ragdoll := climber.find_child("RagdollRig", true, false)
		check(ragdoll != null, "Climber missing ragdoll rig")
		if ragdoll != null:
			for part_name in ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
				var part := ragdoll.find_child(part_name, true, false) as RigidBody3D
				check(part != null and int(part.get("collision_layer")) == 0 and int(part.get("collision_mask")) == 0, "Inactive ragdoll part %s still collides" % part_name)
		var shape_node := climber.find_child("CollisionShape3D", true, false) as CollisionShape3D
		var body_mesh_node := climber.get("body_mesh") as MeshInstance3D
		check(shape_node != null, "Climber missing body collider")
		check(body_mesh_node != null, "Climber missing body mesh")
		if shape_node != null and body_mesh_node != null:
			var body_shape := shape_node.shape as CapsuleShape3D
			var visible_body := body_mesh_node.mesh as CapsuleMesh
			check(body_shape != null and visible_body != null, "Body collider and mesh must both be capsules")
			if body_shape != null and visible_body != null:
				check(absf(body_shape.height - visible_body.height) <= 0.05, "Body collider is shorter than the visible body")
				check(float(climber.get("ground_ray_length")) >= body_shape.height * 0.5 + 0.2, "Ground ray is too short for the body collider")
				var left_foot := climber.find_child("LeftFoot", true, false) as MeshInstance3D
				var right_foot := climber.find_child("RightFoot", true, false) as MeshInstance3D
				if left_foot != null and right_foot != null:
					var box := left_foot.mesh as BoxMesh
					if box != null:
						var half_h := box.size.y * 0.5
						var half_d := box.size.z * 0.5
						var collider_bottom := -body_shape.height * 0.5
						var saved_cycle := float(climber.get("walk_cycle"))
						for phase in range(16):
							climber.set("walk_cycle", TAU * float(phase) / 16.0)
							climber.call("_update_foot_visuals", 0.0)
							for foot in [left_foot, right_foot]:
								var foot_mesh := foot as MeshInstance3D
								var tilt := deg_to_rad(absf(foot_mesh.rotation_degrees.x))
								var extent := half_h * cos(tilt) + half_d * sin(tilt)
								var foot_bottom := foot_mesh.position.y - extent
								check(foot_bottom >= collider_bottom - 0.02, "Foot sinks below the collider at phase %d" % phase)
						climber.set("walk_cycle", saved_cycle)
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
			var sync_props: Array = sync.replication_config.get_properties()
			check(sync_props.size() >= 8, "Synchronizer has too few properties")
			var sync_text := str(sync_props)
			for token in ["stretch", "carry", "character_type"]:
				check(not sync_text.contains(token), "Synchronizer still replicates " + token)
		climber.free()

	var prop_script = load("res://scripts/game/prop.gd")
	if prop_script != null:
		var prop_instance = prop_script.new()
		check(int(ClimbProp.Kind.TRAMPOLINE) == 0, "Trampoline must be the only prop kind")
		check(not prop_instance.has_method("set_water"), "Prop still exposes water state")
		check(not prop_instance.has_signal("fixed_changed"), "Prop can still be anchored")
		prop_instance.free()

	var item_script = load("res://scripts/game/item_pickup.gd")
	if item_script != null:
		var item_instance = item_script.new()
		check(item_instance.has_method("setup"), "Pickup missing setup")
		check(not item_instance.has_method("add_bandage"), "Pickup still grants bandages")
		item_instance.free()

	var manager_script = load("res://scripts/game/game_manager.gd")
	if manager_script != null:
		var manager_instance = manager_script.new()
		for method in ["_finish_match", "_best_player_id", "_score_for", "_handle_death"]:
			check(manager_instance.has_method(method), "GameManager missing method: " + method)
		for method in ["request_carry", "request_bandage_revive", "report_prop_pull", "is_strong_climber", "is_elastic_climber"]:
			check(not manager_instance.has_method(method), "Obsolete GameManager method still exists: " + method)
		var constants: Dictionary = manager_script.get_script_constant_map()
		check(int(constants.get("MATCH_DURATION", 0)) == 300, "Race duration must be 300 seconds")
		check(is_equal_approx(float(constants.get("RESPAWN_PENALTY", 0.0)), 5.0), "Fall penalty must be five seconds")
		manager_instance.free()

	for script_path in ["res://scripts/network/network_manager.gd", "res://scripts/game/game_manager.gd", "res://scripts/player/climber.gd", "res://scripts/ui/main_menu.gd", "res://scripts/ui/hud.gd"]:
		for token in ["start_solo", "CharacterType", "character_type", "add_bandage", "tail_stretch", "fix_prop", "bucket_0", "_carry_links"]:
			check(not source_has(script_path, token), "Obsolete token " + token + " still exists in " + script_path)

	for model in [
		"res://assets/models/jetpack.glb",
		"res://assets/models/trampoline.glb",
		"res://assets/models/rock.glb",
		"res://assets/models/enemy.glb",
	]:
		check(ResourceLoader.exists(model), "Missing model: " + model)
	for model in [
		"res://assets/models/plank.glb",
		"res://assets/models/crate.glb",
		"res://assets/models/bandage.glb",
		"res://assets/models/cabin.glb",
	]:
		check(not ResourceLoader.exists(model), "Obsolete model still exists: " + model)

	print("CLIMB VALIDATION failures=", failures)
	quit(0 if failures == 0 else 1)
