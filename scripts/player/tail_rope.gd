extends RigidBody3D
class_name TailRope

## A short grappling tail attached to its climber. It lives on the prop raycast
## layer so a teammate can hook it with a hand and winch up to its owner.
## Another climber can grab it with F, carry it and fling it; it then returns to
## its owner automatically. It never collides physically while attached.

@export var prop_id: String = "tail_0"
@export var owner_peer_id: int = 0

var rest_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.45, 0.55))

var carrier_id: int = 0
var _return_timer: float = 0.0


func _ready() -> void:
	add_to_group("climb_tails")
	can_sleep = false
	gravity_scale = 0.0
	collision_layer = 4
	collision_mask = 0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_apply_color(Color(0.35, 0.75, 1.0))


func setup(peer: int, color: Color) -> void:
	owner_peer_id = maxi(0, peer)
	prop_id = "tail_%d" % owner_peer_id
	name = "Tail_%d" % owner_peer_id
	_apply_color(color)


func can_be_grappled() -> bool:
	return owner_peer_id > 0


func get_tail_owner_id() -> int:
	return owner_peer_id


## A carrier takes control of the tail; releasing it flings it with the given
## velocity and starts the timer that snaps it back to its owner.
func set_carrier(peer_id: int, throw_velocity: Vector3 = Vector3.ZERO) -> void:
	if carrier_id == peer_id:
		return
	carrier_id = maxi(0, peer_id)
	_return_timer = 0.0
	if carrier_id > 0:
		top_level = true
		freeze = true
		gravity_scale = 0.0
		collision_mask = 0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	# Released: the tail is a light, tumbling rope for a short moment.
	top_level = true
	freeze = false
	gravity_scale = 1.0
	collision_mask = 1
	linear_velocity = throw_velocity
	angular_velocity = Vector3(sin(float(prop_id.length())), 1.4, cos(float(prop_id.length()))) * 3.0
	_return_timer = 2.6


func _physics_process(delta: float) -> void:
	if carrier_id > 0 or _return_timer <= 0.0:
		return
	_return_timer -= delta
	if _return_timer > 0.0:
		return
	_reset_to_owner()


func _reset_to_owner() -> void:
	carrier_id = 0
	_return_timer = 0.0
	top_level = false
	transform = rest_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.0
	collision_mask = 0
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _apply_color(color: Color) -> void:
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.45)
	material.roughness = 0.5
	material.metallic = 0.08
	material.emission_enabled = true
	material.emission = color.darkened(0.25)
	material.emission_energy_multiplier = 0.5
	mesh.material_override = material
