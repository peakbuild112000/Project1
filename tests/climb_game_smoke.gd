extends SceneTree

## Gameplay smoke test for the competitive summit race.

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
	check(players_root.get_child_count() == 2, "Expected 2 racers, got %d" % players_root.get_child_count())
	var climber1 := players_root.get_node_or_null("Climber_1")
	var climber2 := players_root.get_node_or_null("Climber_2")
	check(climber1 != null, "Climber_1 missing")
	check(climber2 != null, "Climber_2 missing")
	if climber1 == null or climber2 == null:
		quit(1)
		return

	var state1: Dictionary = climber1.call("get_state")
	var state2: Dictionary = climber2.call("get_state")
	for token in ["character_type", "stamina_lock", "stretch", "unconscious", "bandages", "carry_kind"]:
		check(not state1.has(token), "Local state still exposes " + token)
		check(not state2.has(token), "Remote state still exposes " + token)
	check(not climber1.has_method("add_bandage"), "Racers must not carry bandages")
	check(not climber1.has_method("set_character_type"), "Racers must not have classes")

	check(int(game.get("_phase")) == 0, "Expected countdown phase")
	var guard := 0
	while int(game.get("_phase")) == 0 and guard < 600:
		await process_frame
		guard += 1
	check(int(game.get("_phase")) == 1, "Countdown did not transition to active")

	var level_node: Node = game.get_node("Level")
	var props: Array = game.get_tree().get_nodes_in_group("climb_props")
	var items: Array = game.get_tree().get_nodes_in_group("climb_items")
	var enemies: Array = game.get_tree().get_nodes_in_group("climb_enemies")
	check(props.size() == 4, "Expected four trampolines, got %d" % props.size())
	check(items.size() == 2, "Expected two jetpacks, got %d" % items.size())
	check(enemies.size() >= 6, "Expected patrolling enemies, got %d" % enemies.size())
	for prop in props:
		check(int(prop.get("kind")) == ClimbProp.Kind.TRAMPOLINE, "Only trampoline props belong in the race")
		check(float(prop.get("bounce_impulse")) > 0.0, "Trampoline has no launch impulse")
		check(prop.get("_bounce_zone") != null, "Trampoline bounce zone is missing")
	for item in items:
		check(str(item.get("item_id")).begins_with("jetpack_"), "Only jetpack pickups belong in the race")
		check(not item.has_method("add_bandage"), "Item pickup still grants bandages")
	check(level_node.find_child("ControlDrawings", true, false) == null, "Control drawings must be removed")
	check(level_node.find_child("MissionSign", true, false) == null, "Mission sign must be removed")
	var mountain: Node = level_node.find_child("ProceduralMountain", true, false)
	check(mountain != null, "Procedural mountain missing")
	if mountain != null:
		var collision: CollisionShape3D = mountain.find_child("CollisionShape3D", true, false) as CollisionShape3D
		check(collision != null and (collision.shape is ConcavePolygonShape3D), "Mountain collision missing")
	check(level_node.has_method("_height_at"), "Mountain height generator missing")
	for slot in range(4):
		var spawn: Vector3 = level_node.call("get_spawn_point", slot)
		check(absf(spawn.y - 1.95) <= 0.01, "Spawn slot %d is not on the flat start pad" % slot)
		check(float(level_node.call("_height_at", spawn.x, spawn.z)) <= 1.2, "Start pad slot %d sits on a slope" % slot)

	game.call("_authorize_item", 1, "jetpack_0")
	await process_frame
	check(bool(climber1.get("has_jetpack")), "Jetpack not equipped")
	check(float(climber1.get("jetpack_fuel")) > 0.0, "Jetpack has no fuel")
	climber1.call("remove_jetpack")
	check(not bool(climber1.get("has_jetpack")), "Jetpack was not removed")

	climber1.call("start_ragdoll")
	check(bool(climber1.get("ragdoll_active")), "Ragdoll stumble did not start")
	climber1.call("_process_ragdoll", 4.0)
	check(not bool(climber1.get("ragdoll_active")), "Ragdoll stumble did not recover on its own")

	climber1.emit_signal("checkpoint_reached", 26.0)
	await process_frame
	var states: Dictionary = game.get("_players_state")
	var st1: Dictionary = states.get(1, {})
	check(float(st1.get("checkpoint_y", 0.0)) == 26.0, "Checkpoint not registered")
	var checkpoint_pos: Vector3 = level_node.call("get_checkpoint_position", 26.0)
	check(checkpoint_pos.y >= 26.0, "Checkpoint respawn point is too low")

	climber1.emit_signal("died", "fall")
	await process_frame
	st1 = states.get(1, {})
	check(not st1.has("lives"), "Lives must not exist")
	check(not st1.has("spectator"), "Spectator state must not exist")
	check(is_equal_approx(float(st1.get("penalty", 0.0)), 5.0), "Fall penalty must be five seconds")
	check(is_equal_approx(float(climber1.call("usable_max_stamina")), float(climber1.get("max_stamina"))), "Falls must not lock stamina")

	states[1]["highest_y"] = 50.0
	states[2]["highest_y"] = 10.0
	game.set("_elapsed", 299.99)
	await process_frame
	check(int(game.get("_phase")) == 2, "Time-up did not end the race")
	check(int(game.get("_winner_id")) == 1, "Time-up did not pick the leading racer")
	check(str(game.get("_end_reason")) == "TIME UP", "Wrong time-up reason")

	game.set("_phase", 1)
	game.set("_elapsed", 0.0)
	game.set("_winner_id", 0)
	game.set("_end_reason", "")
	states[1]["highest_y"] = 0.0
	states[2]["highest_y"] = 0.0
	climber2.emit_signal("summit_reached")
	await process_frame
	check(int(game.get("_phase")) == 2, "Summit did not end the race")
	check(int(game.get("_winner_id")) == 2, "First summit toucher did not win")
	check(str(game.get("_end_reason")) == "SUMMIT", "Wrong summit reason")

	print("GAME SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
