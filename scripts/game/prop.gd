extends RigidBody3D
class_name ClimbProp

## Static boost pad placed along the race route. The host broadcasts its
## transform so every climber sees the same trampoline.

enum Kind { TRAMPOLINE }

@export var prop_id: String = ""
@export var kind: Kind = Kind.TRAMPOLINE
@export var display_name: String = "Trampoline"
@export var mass_kg: float = 25.0
@export var bounce_impulse: float = 0.0

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
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	if bounce_impulse > 0.0:
		_build_bounce_zone()


func setup(id: String, object_kind: Kind, object_name: String, object_mass: float, launch: float) -> void:
	prop_id = id
	kind = object_kind
	display_name = object_name
	mass_kg = object_mass
	bounce_impulse = launch


func can_be_grappled() -> bool:
	return false


func apply_pull_impulse(_impulse: Vector3) -> void:
	return


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


func apply_state(transform_value: Transform3D, linear_value: Vector3, angular_value: Vector3) -> void:
	_target_transform = transform_value
	_target_linear = linear_value
	_target_angular = angular_value
	_has_target = true


func pack_state() -> Array:
	return [prop_id, global_transform, linear_velocity, angular_velocity]


func _physics_process(delta: float) -> void:
	if not _has_target:
		return
	global_transform = global_transform.interpolate_with(_target_transform, clampf(delta * 20.0, 0.0, 1.0))
	linear_velocity = _target_linear
	angular_velocity = _target_angular
