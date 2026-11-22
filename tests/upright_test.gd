extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/climber.tscn") as PackedScene
	var remote := packed.instantiate()
	root.add_child(remote)
	await process_frame
	remote.set("peer_id", 2)
	remote.call("configure", 2, "Remote", Color.WHITE)
	await process_frame
	remote.global_transform.basis = Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(80.0))
	var tilted: float = acos(clampf(remote.global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))
	remote.call("_physics_process", 0.016)
	var fixed: float = acos(clampf(remote.global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))
	var failures: int = 0
	if tilted < 0.5:
		failures += 1
		push_error("Test setup did not tilt remote climber")
	if fixed > 0.05:
		failures += 1
		push_error("Remote climber still tilted: %f" % fixed)
	print("UPRIGHT failures=", failures, " tilted=", tilted, " fixed=", fixed)
	quit(failures)
