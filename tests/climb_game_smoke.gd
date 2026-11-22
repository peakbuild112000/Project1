extends SceneTree

var failures: int = 0

func fail(msg: String) -> void:
	push_error(msg)
	failures += 1

func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)

func _initialize() -> void:
	var net: Node = root.get_node_or_null("Net")
	check(net != null, "Net autoload missing")
	if net == null:
		quit(1)
		return
	net.set("peer_id", 1)
	net.set("is_host", true)
	var roster: Dictionary[int, Dictionary] = {}
	roster[1] = {"name": "Host", "color": Color(0.3, 0.8, 1.0), "ready": true}
	roster[2] = {"name": "Guest", "color": Color(1.0, 0.5, 0.3), "ready": true}
	net.set("players", roster)

	var packed := load("res://scenes/game.tscn") as PackedScene
	check(packed != null, "Cannot load game.tscn")
	if packed == null:
		quit(1)
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var players_root: Node = game.get_node("Players")
	check(players_root.get_child_count() == 2, "Expected 2 climbers, got %d" % players_root.get_child_count())
	var climber1 := players_root.get_node_or_null("Climber_1")
	var climber2 := players_root.get_node_or_null("Climber_2")
	check(climber1 != null, "Climber_1 missing")
	check(climber2 != null, "Climber_2 missing")

	check(int(game.get("_phase")) == 0, "Expected countdown phase")
	var guard := 0
	while int(game.get("_phase")) == 0 and guard < 600:
		await process_frame
		guard += 1
	check(int(game.get("_phase")) == 1, "Countdown did not transition to active")

	var props: Array = game.get_tree().get_nodes_in_group("climb_props")
	var items: Array = game.get_tree().get_nodes_in_group("climb_items")
	check(props.size() >= 16, "Expected physical props, got %d" % props.size())
	check(items.size() == 2, "Expected two jetpack pickups, got %d" % items.size())
	var level_node: Node = game.get_node("Level")
	check(level_node.find_child("ControlDrawings", true, false) != null, "Cabin control drawings missing")
	check(level_node.find_child("MissionSign", true, false) != null, "Mission sign missing")
	var bucket = null
	for candidate in props:
		if str(candidate.get("prop_id")) == "bucket_0":
			bucket = candidate
			break
	check(bucket != null, "Water bucket missing")
	if bucket != null:
		check(float(bucket.get("water")) > 99.0, "Bucket did not start full")
		bucket.global_transform.basis = Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(60.0))
		bucket.call("_physics_process", 0.25)
		check(float(bucket.get("water")) < 100.0, "Tilted bucket did not spill")
		bucket.call("set_water", 100.0)
		check(bool(bucket.call("can_be_grappled")), "Bucket cannot be hooked by hands")
		check(not bool(bucket.get("freeze")), "Bucket is frozen before carry")
		if climber1 != null:
			var old_pos: Vector3 = climber1.global_position
			climber1.set("global_position", bucket.global_position + Vector3(2.0, 0.0, 0.0))
			var cam_pivot: Node3D = climber1.get_node("CameraPivot")
			var cam_pos: Vector3 = bucket.global_position + Vector3(0.0, 0.95, 5.0)
			cam_pivot.global_transform = Transform3D(Basis.looking_at((bucket.global_position - cam_pos).normalized(), Vector3.UP), cam_pos)
			climber1.call("_fire_arm", true)
			var left: Object = climber1.get("left_anchor")
			check(bool(left.get("anchored")), "Left hand did not hook the bucket")
			check(left.get("body") == bucket, "Left hand hooked the wrong body")
			climber1.call("_release_arm", true)
			var before_pull: Vector3 = bucket.linear_velocity
			game.call("report_prop_pull", "bucket_0", Vector3(900.0, 0.0, 0.0))
			await physics_frame
			check(bucket.linear_velocity.length() > before_pull.length(), "Bucket did not react to hand pull")
			climber1.set("global_position", old_pos)
			bucket.linear_velocity = Vector3.ZERO
			bucket.angular_velocity = Vector3.ZERO

	if climber1 != null:
		game.call("request_carry", 0, "crate_0")
		await process_frame
		check(int(climber1.get("carry_kind")) == 0, "Carry link not applied to climber")
		var prop = null
		for candidate in game.get_tree().get_nodes_in_group("climb_props"):
			if str(candidate.get("prop_id")) == "crate_0":
				prop = candidate
				break
		check(prop != null and int(prop.get("carrier_id")) == 1, "Prop carrier not assigned")
		game.call("request_drop")
		await process_frame
		check(int(climber1.get("carry_kind")) == -1, "Carry link not cleared")
		game.call("_authorize_item", 1, "jetpack_0")
		await process_frame
		check(bool(climber1.get("has_jetpack")), "Jetpack not equipped")

		climber1.call("start_ragdoll")
		check(bool(climber1.get("ragdoll_active")), "ragdoll_active not set")
		climber1.call("recover")
		check(not bool(climber1.get("ragdoll_active")), "ragdoll_active not cleared")

		climber1.emit_signal("checkpoint_reached", 20.0)
		await process_frame
		var states: Dictionary = game.get("_players_state")
		var st1: Dictionary = states.get(1, {})
		check(float(st1.get("checkpoint_y", 0.0)) == 20.0, "Checkpoint not registered")

		climber1.emit_signal("died", "fall")
		await process_frame
		st1 = states.get(1, {})
		check(int(st1.get("lives", 0)) == 2, "Life not lost on death")
		check(float(st1.get("penalty", 0.0)) == 5.0, "Penalty not applied")

		climber1.emit_signal("summit_reached")
		await process_frame
		check(int(game.get("_phase")) == 1, "Summit should not end the water mission")

		game.call("request_carry", 0, "bucket_0")
		await process_frame
		check(int(climber1.get("carry_kind")) == 0, "Bucket carry link not applied")
		climber1.set("global_position", level_node.call("get_house_position"))
		await process_frame
		await process_frame
		check(int(game.get("_phase")) == 2, "Water delivery did not end match")
		check(int(game.get("_winner_id")) == 1, "Wrong winner after water delivery")
		check(str(game.get("_end_reason")) == "WATER DELIVERED", "Wrong end reason")

	print("GAME SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
