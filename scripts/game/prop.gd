extends RigidBody3D
class_name ClimbProp

## Physical, carryable level object. Free props are simulated by the host and
## their state is broadcast to peers. A carried prop is driven by its carrier.

enum Kind { CRATE, PLANK, TRAMPOLINE, BUCKET }

signal carrier_changed(peer_id: int)
signal water_changed(value: float)

@export var prop_id: String = ""
@export var kind: Kind = Kind.CRATE
@export var display_name: String = "Object"
@export var mass_kg: float = 25.0
@export var bounce_impulse: float = 0.0

var carrier_id: int = 0
var water: float = 100.0

const BUCKET_HEIGHT: float = 1.6

var _water_mesh: MeshInstance3D = null
var _target_transform: Transform3D = Transform3D.IDENTITY
var _target_linear: Vector3 = Vector3.ZERO
var _target_angular: Vector3 = Vector3.ZERO
var _has_target: bool = false
var _bounce_zone: Area3D = null
var _bounce_cooldowns: Dictionary = {}


func _ready() -> void:
	add_to_group("climb_props")
	mass = mass_kg
	can_sleep = false
	_target_transform = global_transform
	if kind == Kind.TRAMPOLINE and bounce_impulse > 0.0:
		_build_bounce_zone()
	if kind == Kind.BUCKET:
		_build_bucket_visual()
		_update_water_visual()


func setup(id: String, object_kind: Kind, object_name: String, object_mass: float, launch: float) -> void:
	prop_id = id
	kind = object_kind
	display_name = object_name
	mass_kg = object_mass
	bounce_impulse = launch
	if kind == Kind.BUCKET:
		water = 100.0


func _build_bucket_visual() -> void:
	var shell := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.95
	cylinder.bottom_radius = 0.7
	cylinder.height = BUCKET_HEIGHT
	cylinder.radial_segments = 14
	shell.mesh = cylinder
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.46, 0.52, 0.58)
	metal.metallic = 0.55
	metal.roughness = 0.4
	shell.material_override = metal
	add_child(shell)

	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.88
	torus.outer_radius = 1.0
	torus.ring_segments = 18
	rim.mesh = torus
	rim.position.y = BUCKET_HEIGHT * 0.5
	rim.material_override = metal
	add_child(rim)

	_water_mesh = MeshInstance3D.new()
	var water_cylinder := CylinderMesh.new()
	water_cylinder.top_radius = 0.78
	water_cylinder.bottom_radius = 0.78
	water_cylinder.height = 1.0
	water_cylinder.radial_segments = 14
	_water_mesh.mesh = water_cylinder
	var water_material := StandardMaterial3D.new()
	water_material.albedo_color = Color(0.12, 0.55, 0.95)
	water_material.emission_enabled = true
	water_material.emission = Color(0.08, 0.4, 0.8)
	water_material.emission_energy_multiplier = 0.8
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.albedo_color.a = 0.86
	_water_mesh.material_override = water_material
	add_child(_water_mesh)


func _update_water_visual() -> void:
	if _water_mesh == null:
		return
	var ratio := clampf(water / 100.0, 0.0, 1.0)
	_water_mesh.visible = ratio > 0.001
	var height: float = maxf(0.02, 1.25 * ratio)
	var cylinder := _water_mesh.mesh as CylinderMesh
	if cylinder != null:
		cylinder.height = height
	_water_mesh.position.y = -(BUCKET_HEIGHT * 0.5) + 0.1 + (height * 0.5)


func set_water(value: float) -> void:
	var next_value := clampf(value, 0.0, 100.0)
	if is_equal_approx(water, next_value):
		return
	water = next_value
	_update_water_visual()
	water_changed.emit(water)


func can_be_grappled() -> bool:
	return kind == Kind.BUCKET and carrier_id == 0


func apply_pull_impulse(impulse: Vector3) -> void:
	if carrier_id > 0 or freeze or impulse.length_squared() < 0.000001:
		return
	var limited := impulse.limit_length(65.0)
	apply_central_impulse(limited)
	# A hand on the rim creates torque, which makes the water spill naturally.
	apply_torque_impulse(Vector3(limited.z, 0.0, -limited.x) * 0.35)


func _build_bounce_zone() -> void:
	_bounce_zone = Area3D.new()
	_bounce_zone.name = "BounceZone"
	_bounce_zone.position = Vector3(0.0, 0.05, 0.0)
	_bounce_zone.collision_layer = 4
	_bounce_zone.collision_mask = 2
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.05
	cylinder.height = 0.42
	shape.shape = cylinder
	_bounce_zone.add_child(shape)
	add_child(_bounce_zone)
	_bounce_zone.body_entered.connect(_on_bounce_body)


func _on_bounce_body(body: Node) -> void:
	if not is_instance_valid(body) or not body.has_method("apply_bounce"):
		return
	var key := body.get_instance_id()
	var now := Time.get_ticks_msec()
	if int(_bounce_cooldowns.get(key, 0)) + 700 > now:
		return
	_bounce_cooldowns[key] = now
	body.call("apply_bounce", Vector3.UP * bounce_impulse, "TRAMPOLINE")


func set_carrier(peer_id: int) -> void:
	if carrier_id == peer_id:
		return
	carrier_id = peer_id
	if peer_id > 0:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	else:
		freeze = false
	carrier_changed.emit(peer_id)


func apply_state(transform_value: Transform3D, linear_value: Vector3, angular_value: Vector3) -> void:
	_target_transform = transform_value
	_target_linear = linear_value
	_target_angular = angular_value
	_has_target = true


func pack_state() -> Array:
	return [prop_id, global_transform, linear_velocity, angular_velocity, water]


func _is_server() -> bool:
	var api: MultiplayerAPI = get_multiplayer()
	if api == null:
		return true
	return api.get_unique_id() == 1


func _update_spill(delta: float) -> void:
	if water <= 0.0 or not _is_server():
		return
	var tilt: float = acos(clampf(global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))
	var speed := linear_velocity.length()
	var spin := angular_velocity.length()
	var excess := 0.0
	if tilt > deg_to_rad(18.0):
		excess += (tilt - deg_to_rad(18.0)) / deg_to_rad(55.0)
	if speed > 8.0:
		excess += (speed - 8.0) / 14.0
	if spin > 2.2:
		excess += (spin - 2.2) / 7.0
	if excess <= 0.0:
		return
	var loss: float = (10.0 + 22.0 * excess) * excess * delta
	set_water(water - loss)


func _physics_process(delta: float) -> void:
	if kind == Kind.BUCKET:
		_update_spill(delta)
	if not _has_target:
		return
	var own_id := 0
	var api: MultiplayerAPI = get_multiplayer()
	if api != null:
		own_id = api.get_unique_id()
	if carrier_id == own_id and own_id > 0:
		return
	global_transform = global_transform.interpolate_with(_target_transform, clampf(delta * 20.0, 0.0, 1.0))
	linear_velocity = _target_linear
	angular_velocity = _target_angular
