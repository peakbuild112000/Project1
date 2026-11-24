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
		for method in ["create_server", "join_server", "create_web_room", "join_web_room", "start_match", "leave", "set_ready", "send_chat", "player_data", "has_both_classes", "class_for_join_index", "assign_character_types"]:
			check(net.has_method(method), "Net missing method: " + method)
		check(not net.has_method("set_character_type"), "Manual class setter must be removed")
		check(int(net.call("class_for_join_index", 0)) == CharacterType.ELASTIC, "First guest must be Elastic")
		check(int(net.call("class_for_join_index", 1)) == CharacterType.STRONG, "Second guest must be Strong")
		check(int(net.call("class_for_join_index", 2)) == CharacterType.ELASTIC, "Third guest must be Elastic")
		var saved_players: Dictionary = net.get("players")
		var saved_join_order: Array = net.get("_join_order")
		var saved_is_host: bool = bool(net.get("is_host"))
		var saved_host_peer: int = int(net.get("peer_id"))
		var auto_roster: Dictionary[int, Dictionary] = {}
		auto_roster[1] = {"name": "Host", "character_type": CharacterType.ELASTIC}
		auto_roster[2] = {"name": "Guest A", "character_type": CharacterType.STRONG}
		auto_roster[3] = {"name": "Guest B", "character_type": CharacterType.STRONG}
		net.set("players", auto_roster)
		var guest_order: Array[int] = [2, 3]
		net.set("_join_order", guest_order)
		net.set("is_host", true)
		net.set("peer_id", 1)
		net.call("assign_character_types")
		check(int((net.get("players")[1] as Dictionary).get("character_type", -1)) == CharacterType.STRONG, "Host was not forced to Strong")
		check(int((net.get("players")[2] as Dictionary).get("character_type", -1)) == CharacterType.ELASTIC, "First guest was not forced to Elastic")
		check(int((net.get("players")[3] as Dictionary).get("character_type", -1)) == CharacterType.STRONG, "Second guest was not forced to Strong")
		check(int(net.get("character_type")) == CharacterType.STRONG, "Local class mirror was not updated")
		net.set("players", saved_players)
		net.set("_join_order", saved_join_order)
		net.set("is_host", saved_is_host)
		net.set("peer_id", saved_host_peer)
		check(net.has_signal("match_start_rejected"), "Net missing match_start_rejected signal")
		# A lobby where everyone picked the same class cannot start a match.
		var same_class: Dictionary[int, Dictionary] = {}
		same_class[1] = {"character_type": CharacterType.STRONG}
		same_class[2] = {"character_type": CharacterType.STRONG}
		net.set("players", same_class)
		check(not bool(net.call("has_both_classes")), "Same-class lobby was accepted")
		same_class[2] = {"character_type": CharacterType.ELASTIC}
		net.set("players", same_class)
		check(bool(net.call("has_both_classes")), "Mixed-class lobby was rejected")
		net.set("players", saved_players)
		var rtc := net.get_node_or_null("WebRTCRoom")
		check(rtc != null, "Net missing WebRTCRoom transport")
		if rtc != null:
			for method in ["start_host", "start_client", "close_room", "get_multiplayer_peer"]:
				check(rtc.has_method(method), "WebRTCRoom missing method: " + method)

	var climber_scene := load("res://scenes/climber.tscn") as PackedScene
	if climber_scene != null:
		var climber := climber_scene.instantiate() as Node
		root.add_child(climber)
		for method in ["configure", "respawn_at", "apply_hazard", "get_state", "add_bandage", "use_bandage", "use_bandage_on_target", "find_bandage_target", "revive_with_bandage", "set_persistent_unconscious", "apply_fall_impact", "usable_max_stamina", "set_stamina_lock", "get_total_weight", "remove_jetpack", "find_fix_target", "is_critically_damaged", "get_death_time_left", "is_strong", "is_elastic", "can_carry_climber", "launch_from_carry", "rpc_carry_launch", "release_tail_anchor", "_request_carry"]:
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
			check(tail.has_method("set_tension"), "Tail cannot be tensioned")
			check(tail.has_method("rpc_release_tail_slack"), "Reliable rope slack release missing")
			check(int(tail.get("tension_version")) >= 0, "Tail tension has no version")
		check(climber.has_method("can_carry_climber"), "Climber cannot lift a teammate")
		check(climber.has_method("can_climb"), "Climber has no class climb gate")
		check(float(climber.get("elastic_fall_damage_scale")) <= 0.6, "Elastic fall damage must be reduced")
		check(float(climber.get("elastic_fall_safe_speed_bonus")) >= 1.0, "Elastic needs a higher safe landing speed")
		var saved_type := int(climber.get("character_type"))
		climber.call("set_character_type", CharacterType.ELASTIC)
		check(not bool(climber.call("can_climb")), "Elastic must not be able to climb")
		climber.call("_fire_arm", true)
		check(not bool((climber.get("left_anchor") as Object).get("anchored")), "Elastic fired a grappling hand")
		climber.call("set_character_type", CharacterType.STRONG)
		check(bool(climber.call("can_climb")), "Strong must be able to climb")
		climber.call("set_character_type", saved_type)
		var ragdoll := climber.find_child("RagdollRig", true, false)
		check(ragdoll != null, "Climber missing ragdoll rig")
		if ragdoll != null:
			for part_name in ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
				var part := ragdoll.find_child(part_name, true, false) as RigidBody3D
				check(part != null and int(part.get("collision_layer")) == 0 and int(part.get("collision_mask")) == 0, "Inactive ragdoll part %s still collides" % part_name)
		var shape_node := climber.find_child("CollisionShape3D", true, false) as CollisionShape3D
		check(shape_node != null, "Climber missing body collider")
		var body_mesh_node := climber.get("body_mesh") as MeshInstance3D
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
