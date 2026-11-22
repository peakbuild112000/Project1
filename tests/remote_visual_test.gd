extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/climber.tscn") as PackedScene
	var failures: int = 0

	var remote := packed.instantiate()
	root.add_child(remote)
	await process_frame
	remote.call("configure", 2, "Remote", Color.WHITE)
	await process_frame
	if bool(remote.get("is_local")):
		failures += 1
		push_error("Peer 2 should be remote")
	if not bool(remote.get("freeze")):
		failures += 1
		push_error("Remote body should be frozen")

	remote.call("respawn_at", Vector3(1.0, 2.0, 3.0), false)
	if not bool(remote.get("freeze")):
		failures += 1
		push_error("Respawn woke the remote body")

	remote.set("ragdoll_active", true)
	remote.call("recover")
	if not bool(remote.get("freeze")):
		failures += 1
		push_error("Recover woke the remote body")

	remote.call("receive_arm_visual", Vector3(0.0, 5.0, 0.0), Vector3.ZERO, true, false)
	if not bool(remote.get("_remote_left_on")):
		failures += 1
		push_error("Remote did not receive anchored arm")
	remote.call("receive_arm_visual", Vector3.ZERO, Vector3.ZERO, false, false)
	if bool(remote.get("_remote_left_on")):
		failures += 1
		push_error("Remote did not receive released arm")

	var local := packed.instantiate()
	root.add_child(local)
	await process_frame
	local.call("configure", 1, "Local", Color.WHITE)
	await process_frame
	if not bool(local.get("is_local")):
		failures += 1
		push_error("Peer 1 should be local")
	if bool(local.get("freeze")):
		failures += 1
		push_error("Local body should be dynamic")
	local.call("respawn_at", Vector3(0.0, 1.0, 0.0), false)
	if bool(local.get("freeze")):
		failures += 1
		push_error("Respawn froze the local body")

	var arm = local.get("left_anchor")
	arm.anchored = true
	arm.point = Vector3(0.0, 5.0, 0.0)
	var state: Dictionary = local.call("get_arm_visual_state")
	if not bool(state["left_on"]):
		failures += 1
		push_error("Anchored arm state missing")
	arm.anchored = false
	state = local.call("get_arm_visual_state")
	if bool(state["left_on"]):
		failures += 1
		push_error("Released arm state missing")

	local.set("global_position", Vector3(2.0, 3.0, 4.0))
	local.call("_sync_replicated_transform")
	if local.replicated_position.distance_to(Vector3(2.0, 3.0, 4.0)) > 0.001:
		failures += 1
		push_error("Replicated position not synced from local body")
	remote.set("replicated_position", Vector3(6.0, 7.0, 8.0))
	remote.call("_apply_remote_transform", 0.5)
	if remote.global_position.distance_to(Vector3(6.0, 7.0, 8.0)) > 0.001:
		failures += 1
		push_error("Remote body did not follow replicated position")

	print("REMOTE VISUAL failures=", failures)
	quit(failures)
