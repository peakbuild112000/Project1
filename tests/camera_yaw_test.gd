extends SceneTree

func _initialize() -> void:
	var packed := load("res://scenes/climber.tscn") as PackedScene
	var climber := packed.instantiate()
	root.add_child(climber)
	await process_frame
	var camera: Node3D = climber.find_child("CameraPivot", true, false) as Node3D
	if camera == null:
		print("CAMERA YAW failures=1 missing camera")
		quit(1)
		return
	camera.call("setup_local", true)
	camera.set("yaw_rad", 1.234)
	var before: float = float(camera.get("yaw_rad"))
	camera.call("_process", 0.016)
	var after: float = camera.rotation.y
	var failures: int = 0
	if absf(after - before) > 0.01:
		failures += 1
		push_error("Camera yaw was reset in _process: yaw=%f rotation.y=%f" % [before, after])
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(120.0, 0.0)
	camera.call("set", "yaw_rad", 0.0)
	camera.call("_unhandled_input", motion)
	print("CAMERA YAW failures=", failures, " preserved=", after, " mouse_headless_mode=", Input.get_mouse_mode())
	quit(failures)
