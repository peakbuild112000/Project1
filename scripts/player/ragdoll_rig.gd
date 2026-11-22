extends Node3D
class_name RagdollRig

const PART_NAMES := ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]

var parts: Array[RigidBody3D] = []
var joints: Array[PinJoint3D] = []
var _rest: PackedVector3Array = PackedVector3Array()
var _links: Array = []


func _ready() -> void:
	_setup()


func _setup() -> void:
	if not parts.is_empty():
		return
	top_level = true
	visible = false

	_rest = PackedVector3Array()
	_rest.push_back(Vector3(0.0, -0.28, 0.0))
	_rest.push_back(Vector3(0.0, 0.38, 0.0))
	_rest.push_back(Vector3(0.0, 0.96, 0.0))
	_rest.push_back(Vector3(-0.48, 0.42, 0.0))
	_rest.push_back(Vector3(0.48, 0.42, 0.0))
	_rest.push_back(Vector3(-0.22, -0.92, 0.0))
	_rest.push_back(Vector3(0.22, -0.92, 0.0))

	_links = [[0, 1], [1, 2], [1, 3], [1, 4], [0, 5], [0, 6]]

	for name in PART_NAMES:
		var body: RigidBody3D = get_node_or_null(name) as RigidBody3D
		if body == null:
			continue
		body.freeze = true
		body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		body.linear_damp = 1.2
		body.angular_damp = 2.2
		body.can_sleep = false
		parts.append(body)

	for link in _links:
		var joint := PinJoint3D.new()
		joint.name = "Link_%d_%d" % [link[0], link[1]]
		add_child(joint)
		joints.append(joint)


func _ensure_parts() -> void:
	if not parts.is_empty():
		return
	_setup()


func apply_color(color: Color) -> void:
	_ensure_parts()
	for part in parts:
		var visual: MeshInstance3D = part.get_node_or_null("Mesh") as MeshInstance3D
		if visual == null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.42
		material.emission_enabled = true
		material.emission = color.darkened(0.6)
		visual.material_override = material


func activate(body_xform: Transform3D, velocity: Vector3, stretch: float, color: Color) -> void:
	apply_color(color)
	_place(body_xform)
	_enable_joints()

	var swing: Vector3 = body_xform.basis.x * (stretch * 2.2)
	var base_impulse: Vector3 = velocity * 0.55 + (Vector3.UP * (1.4 + stretch * 4.2)) + swing
	for i in range(parts.size()):
		var multiplier: float = 1.0 if i < 3 else 0.7
		parts[i].apply_central_impulse(base_impulse * parts[i].mass * multiplier)
	if parts.size() > 2:
		parts[2].apply_torque_impulse(Vector3(2.4, 1.2, -1.8))
	visible = true


func activate_remote(body_xform: Transform3D) -> void:
	_ensure_parts()
	_place(body_xform)
	_enable_joints()
	visible = true


func deactivate() -> void:
	_ensure_parts()
	for joint in joints:
		joint.node_a = NodePath()
		joint.node_b = NodePath()
	for part in parts:
		part.freeze = true
		part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
	visible = false


func get_hips_position() -> Vector3:
	if parts.is_empty():
		return global_position
	return parts[0].global_position


func get_hips_velocity() -> Vector3:
	if parts.is_empty():
		return Vector3.ZERO
	return parts[0].linear_velocity


func get_parts() -> Array[RigidBody3D]:
	_ensure_parts()
	return parts


func pack_poses() -> PackedFloat32Array:
	var data := PackedFloat32Array()
	for part in parts:
		var t: Transform3D = part.global_transform
		data.push_back(t.basis.x.x)
		data.push_back(t.basis.x.y)
		data.push_back(t.basis.x.z)
		data.push_back(t.basis.y.x)
		data.push_back(t.basis.y.y)
		data.push_back(t.basis.y.z)
		data.push_back(t.basis.z.x)
		data.push_back(t.basis.z.y)
		data.push_back(t.basis.z.z)
		data.push_back(t.origin.x)
		data.push_back(t.origin.y)
		data.push_back(t.origin.z)
	return data


func apply_poses(data: PackedFloat32Array) -> void:
	if data.size() < parts.size() * 12:
		return
	for i in range(parts.size()):
		var offset: int = i * 12
		var basis := Basis(
			Vector3(data[offset], data[offset + 1], data[offset + 2]),
			Vector3(data[offset + 3], data[offset + 4], data[offset + 5]),
			Vector3(data[offset + 6], data[offset + 7], data[offset + 8])
		)
		var origin := Vector3(data[offset + 9], data[offset + 10], data[offset + 11])
		parts[i].global_transform = Transform3D(basis, origin)


func _place(body_xform: Transform3D) -> void:
	global_transform = body_xform
	for i in range(parts.size()):
		var part: RigidBody3D = parts[i]
		var offset_index: int = mini(i, _rest.size() - 1)
		part.freeze = false
		part.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		part.linear_velocity = Vector3.ZERO
		part.angular_velocity = Vector3.ZERO
		part.global_transform = body_xform * Transform3D(Basis.IDENTITY, _rest[offset_index])


func _enable_joints() -> void:
	for k in range(mini(joints.size(), _links.size())):
		var link: Array = _links[k]
		if link[0] >= parts.size() or link[1] >= parts.size():
			continue
		var first: RigidBody3D = parts[link[0]]
		var second: RigidBody3D = parts[link[1]]
		var joint: PinJoint3D = joints[k]
		joint.node_a = joint.get_path_to(first)
		joint.node_b = joint.get_path_to(second)
		joint.global_position = (first.global_position + second.global_position) * 0.5
