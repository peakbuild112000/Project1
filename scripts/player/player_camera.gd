extends Node3D
class_name PlayerCamera

## First-person camera attached to the climber. Always upright, always at head
## height: no ball camera, no third-person roll, no body spinning in view.

@export var mouse_sensitivity: float = 0.0022
@export var min_pitch_deg: float = -85.0
@export var max_pitch_deg: float = 85.0
@export var follow_speed: float = 26.0
@export var head_height: float = 0.95

var pitch_deg: float = 0.0
var yaw_rad: float = 0.0
var enabled: bool = false

@onready var player: RigidBody3D = get_parent() as RigidBody3D
@onready var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D


func _ready() -> void:
	top_level = true
	set_process(false)


func setup_local(local: bool) -> void:
	enabled = local
	visible = local
	set_process(local)
	if camera != null:
		camera.current = local
	if local:
		pitch_deg = 0.0
		yaw_rad = 0.0
		rotation = Vector3.ZERO
		if global_position.distance_squared_to(_desired_position()) > 625.0:
			global_position = _desired_position()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		pitch_deg = 0.0
		yaw_rad = 0.0
		rotation = Vector3.ZERO
		if camera != null:
			camera.position = Vector3.ZERO
			camera.rotation_degrees.x = 0.0


func get_camera() -> Camera3D:
	return camera


func get_aim_origin() -> Vector3:
	if camera != null:
		return camera.global_position
	return global_position


func get_aim_forward() -> Vector3:
	if camera != null:
		return -camera.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()


func _desired_position() -> Vector3:
	if not is_instance_valid(player):
		return global_position
	return player.global_position + (Vector3.UP * head_height)


func _process(delta: float) -> void:
	if not enabled or not is_instance_valid(player):
		return
	var target: Vector3 = _desired_position()
	if global_position.distance_squared_to(target) > 625.0:
		global_position = target
	else:
		global_position = global_position.lerp(target, clampf(delta * follow_speed, 0.0, 1.0))
	rotation = Vector3(0.0, yaw_rad, 0.0)
	if camera != null:
		camera.position = Vector3.ZERO
		camera.rotation_degrees.x = pitch_deg


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw_rad -= event.relative.x * mouse_sensitivity
		rotation.y = yaw_rad
		pitch_deg = clampf(
			pitch_deg - event.relative.y * mouse_sensitivity * (180.0 / PI),
			min_pitch_deg,
			max_pitch_deg
		)
		if camera != null:
			camera.rotation_degrees.x = pitch_deg
	elif event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
