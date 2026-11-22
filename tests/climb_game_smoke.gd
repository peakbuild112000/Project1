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
	var enemies: Array = game.get_tree().get_nodes_in_group("climb_enemies")
	check(props.size() >= 16, "Expected physical props, got %d" % props.size())
	check(items.size() >= 7, "Expected jetpack and bandage pickups, got %d" % items.size())
	check(enemies.size() >= 6, "Expected patrolling enemies, got %d" % enemies.size())
	var bandage_pickups: int = 0
	for item in items:
		if int(item.get("item_kind")) == 1:
			bandage_pickups += 1
	check(bandage_pickups >= 5, "Expected bandage pickups, got %d" % bandage_pickups)
	var level_node: Node = game.get_node("Level")
	check(level_node.find_child("ControlDrawings", true, false) != null, "Cabin control drawings missing")
	check(level_node.find_child("MissionSign", true, false) != null, "Mission sign missing")
	var mountain: Node = level_node.find_child("ProceduralMountain", true, false)
	check(mountain != null, "Procedural mountain missing")
	if mountain != null:
		var collision: CollisionShape3D = mountain.find_child("CollisionShape3D", true, false) as CollisionShape3D
		check(collision != null and (collision.shape is ConcavePolygonShape3D), "Mountain collision missing")
		check(level_node.has_method("_height_at"), "Mountain height generator missing")
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

		# Coop building: a carrier cannot anchor their own object, but a nearby
		# climber can fix and release it. Anchored props cannot be picked up.
		var build_prop: Node = null
		for candidate in props:
			if str(candidate.get("prop_id")) == "crate_0":
				build_prop = candidate
				break
		if build_prop != null:
			build_prop.global_position = climber1.global_position + Vector3(1.0, 0.0, 0.0)
			game.call("request_carry", 0, "crate_0")
			await physics_frame
			game.call("_authorize_fix", 1, "crate_0")
			check(not bool(build_prop.get("is_fixed")), "Carrier anchored the prop they were holding")
			game.call("request_drop")
			await physics_frame
			# Dropping near the teammate is what allows the coop anchor; place the
			# prop explicitly so this test does not depend on physics timing.
			build_prop.global_position = climber1.global_position + Vector3(1.0, 0.0, 0.0)
			game.call("_authorize_fix", 1, "crate_0")
			await process_frame
			check(bool(build_prop.get("is_fixed")), "Prop was not fixed")
			check(bool(build_prop.get("freeze")), "Fixed prop is not frozen")
			game.call("request_carry", 0, "crate_0")
			await process_frame
			check(int(climber1.get("carry_kind")) == -1, "Fixed prop was picked up")
			game.call("_authorize_fix", 1, "crate_0")
			check(not bool(build_prop.get("is_fixed")), "Prop was not released")
			await process_frame

		game.call("_authorize_item", 1, "jetpack_0")
		await process_frame
		check(bool(climber1.get("has_jetpack")), "Jetpack not equipped")

		# Teammates can be carried whether awake or ragdolling.
		game.call("request_carry", 1, "2")
		await process_frame
		check(int(climber1.get("carry_kind")) == 1, "Awake climber was not grabbed")
		check(int(climber2.get("carried_by_peer")) == 1, "Carried climber was not linked")
		game.call("request_drop")
		await process_frame
		check(int(climber1.get("carry_kind")) == -1, "Carried climber was not dropped")
		check(int(climber2.get("carried_by_peer")) == 0, "Carried link was not cleared")

		# Fall damage stays as a red locked slice until a bandage is used.
		check(int(climber1.get("bandages")) == 0, "Climbers must start with no bandages")
		var stamina_before: float = float(climber1.get("current_stamina"))
		climber1.call("apply_fall_impact", 24.0)
		check(float(climber1.get("current_stamina")) < stamina_before, "Fall damage did not drain stamina")
		check(float(climber1.get("stamina_lock")) > 0.0, "Fall damage did not lock stamina")
		check(float(climber1.call("usable_max_stamina")) < float(climber1.get("max_stamina")), "Usable stamina not reduced")
		check(float(climber1.get("injury")) > 0.0, "Fall damage did not cause injury")
		var injury_before: float = float(climber1.get("injury"))
		climber1.call("use_bandage")
		check(int(climber1.get("bandages")) == 0, "Bandage used without owning one")
		climber1.call("add_bandage", 1)
		var lock_before: float = float(climber1.get("stamina_lock"))
		climber1.call("use_bandage")
		check(int(climber1.get("bandages")) == 0, "Bandage was not consumed")
		check(float(climber1.get("stamina_lock")) < lock_before, "Bandage did not unlock stamina")
		check(float(climber1.get("injury")) < injury_before, "Bandage did not reduce injury")
		check(float(climber1.call("get_total_weight")) > 0.0, "Jetpack weight not counted in load")

		climber1.call("remove_jetpack")
		check(not bool(climber1.get("has_jetpack")), "Jetpack was not removed")

		climber1.call("start_ragdoll")
		check(bool(climber1.get("ragdoll_active")), "ragdoll_active not set")
		climber1.call("recover")
		check(not bool(climber1.get("ragdoll_active")), "ragdoll_active not cleared")

		# A downed teammate can be carried, dropped, then revived with a bandage.
		climber2.call("set_persistent_unconscious", true)
		climber2.set("global_position", climber1.global_position + Vector3(1.0, 0.0, 0.0))
		climber2.call("start_ragdoll")
		check(bool(climber2.get("unconscious")), "Ragdoll did not mark climber unconscious")
		climber2.call("_process_ragdoll", 3.0)
		check(bool(climber2.get("unconscious")), "Multiplayer ragdoll must wait for a bandage")
		game.call("request_carry", 1, "2")
		await process_frame
		check(int(climber2.get("carried_by_peer")) == 1, "Unconscious teammate was not carried")
		check(not bool(climber2.get("ragdoll_active")), "Carried downed teammate kept a live ragdoll")
		game.call("request_drop")
		await process_frame
		check(int(climber2.get("carried_by_peer")) == 0, "Downed teammate was not dropped")
		check(bool(climber2.get("unconscious")), "Dropping revived a downed teammate")
		climber1.call("add_bandage", 1)
		climber1.set("global_position", climber2.global_position + Vector3(1.0, 0.0, 0.0))
		climber1.call("use_bandage_on_target", 2)
		await process_frame
		check(not bool(climber2.get("unconscious")), "Bandage did not revive the teammate")
		check(not bool(climber2.get("ragdoll_active")), "Revived teammate stayed ragdolled")
		check(int(climber1.get("bandages")) == 0, "Revive bandage was not consumed")

		# The cabin door must open onto flat ground, not the mountain wall.
		for door_z in [-6.55, -5.5, -4.5, -3.5]:
			var door_height := float(level_node.call("_height_at", 0.0, door_z))
			check(door_height <= 2.0, "Mountain blocks the cabin door at z=%.1f (h=%.1f)" % [door_z, door_height])
		for child in level_node.get_children():
			if str(child.name).begins_with("Rock_"):
				check(child.global_position.distance_to(Vector3(0.0, 1.0, -6.55)) > 4.0, "A rock blocks the cabin exit")

		# A badly hurt climber who empties their bar in a fall collapses and
		# stays unconscious until a bandage is spent.
		climber1.call("respawn_at", Vector3(0.0, 2.0, -12.0))
		climber1.set("injury", 0.9)
		climber1.set("current_stamina", 5.0)
		climber1.call("apply_fall_impact", 24.0, 0.0)
		check(bool(climber1.get("ragdoll_active")), "Critical fall did not ragdoll the climber")
		check(bool(climber1.get("unconscious")), "Critical fall did not knock the climber out")
		check(bool(climber1.get("persistent_unconscious")), "Fall collapse must wait for a bandage")
		climber1.call("respawn_at", Vector3(1.0, 2.0, -12.0))

		# The downed timer advances only while the teammate is not carried.
		var death_reasons: Array = []
		climber2.connect("died", func(reason): death_reasons.append(str(reason)))
		climber2.call("respawn_at", Vector3(2.0, 2.0, -12.0))
		climber2.call("set_persistent_unconscious", true)
		climber2.call("start_ragdoll")
		check(float(climber2.call("get_death_time_left")) > 0.0, "Downed climber has no death countdown")
		climber2.set("unconscious_time", float(climber2.get("unconscious_death_time")) - 0.1)
		climber2.call("_process_ragdoll", 0.2)
		check(bool(climber2.get("dead")), "Downed climber did not die when the timer ran out")
		check(death_reasons.has("unconscious"), "Death reason must be unconscious")

		climber2.call("respawn_at", Vector3(2.0, 2.0, -12.0))
		climber2.call("set_persistent_unconscious", true)
		climber2.call("start_ragdoll")
		climber2.set("unconscious_time", 5.0)
		game.call("request_carry", 1, "2")
		await process_frame
		check(int(climber2.get("carried_by_peer")) == 1, "Downed climber was not carried for timer test")
		var paused_time := float(climber2.get("unconscious_time"))
		for _i in range(3):
			await process_frame
		check(is_equal_approx(float(climber2.get("unconscious_time")), paused_time), "Carrying did not pause the death timer")
		game.call("request_drop")
		await process_frame
		climber2.call("respawn_at", Vector3(2.0, 2.0, -12.0))

		climber1.emit_signal("checkpoint_reached", 20.0)
		await process_frame
		var states: Dictionary = game.get("_players_state")
		var st1: Dictionary = states.get(1, {})
		check(float(st1.get("checkpoint_y", 0.0)) == 20.0, "Checkpoint not registered")

		climber1.emit_signal("died", "fall")
		await process_frame
		st1 = states.get(1, {})
		check(not st1.has("lives"), "Lives must not exist")
		check(not st1.has("spectator"), "Spectator state must not exist")
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
