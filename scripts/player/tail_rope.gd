extends RigidBody3D
class_name TailRope

## Elastic climbers own a rope tail. While the owner holds Q, the tail stretches
## toward the camera and becomes a long grappling line a Strong teammate can
## hook and climb. A Strong teammate can also grab the tail with F and fling it;
## it returns to its owner shortly afterwards. Strong climbers have an inert,
## hidden tail so every climber keeps the same scene shape.

const TENSION_SEND_INTERVAL := 0.05
## World geometry lives on layer 1. The stretched rope must stop at that layer
## instead of passing through walls and the mountain.
const WALL_LAYER_MASK: int = 1
const WALL_MARGIN: float = 0.18

@export var prop_id: String = "tail_0"
@export var owner_peer_id: int = 0
@export var max_tension_length: float = 13.0

var rest_transform := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.45, 0.55))

var elastic: bool = true
var carrier_id: int = 0
var tensioned: bool = false
var tension_direction: Vector3 = Vector3.FORWARD
var tension_length: float = 0.0
var _return_timer: float = 0.0
var _tension_send_timer: float = 0.0
## Monotonic state version. A reliable slack packet must not cancel a newer
## tension that started while an older unreliable packet was in flight.
var tension_version: int = 0
var _last_applied_version: int = -1


func _ready() -> void:
	add_to_group("climb_tails")
	can_sleep = false
	gravity_scale = 0.0
	collision_layer = 4 if elastic else 0
	collision_mask = 0
	continuous_cd = false
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_apply_color(Color(0.35, 0.75, 1.0))
	_update_rope_shape()


func setup(peer: int, color: Color, is_elastic: bool = true) -> void:
	owner_peer_id = maxi(0, peer)
	prop_id = "tail_%d" % owner_peer_id
	elastic = is_elastic
	visible = elastic
	collision_layer = 4 if elastic else 0
	set_multiplayer_authority(owner_peer_id)
	_apply_color(color)
	if not elastic:
		_apply_tension(false, Vector3.FORWARD, 0.0)


func can_be_grappled() -> bool:
	return elastic and owner_peer_id > 0 and carrier_id == 0


func get_tail_owner_id() -> int:
	return owner_peer_id


func is_tensioned() -> bool:
	return tensioned and elastic and carrier_id == 0


func get_tip_position() -> Vector3:
	if not is_tensioned():
		return global_position
	return _owner_origin() + tension_direction * tension_length


## The owner repeats this while holding the tension key. Remote peers receive
## a throttled RPC; the local rope is updated every frame so climbing feels tight.
func set_tension(active: bool, direction: Vector3 = Vector3.FORWARD, length: float = 0.0) -> void:
	if not elastic or carrier_id > 0:
		active = false
	var next_direction := Vector3.FORWARD
	var next_length := 0.0
	if active:
		if direction.length_squared() > 0.001:
			next_direction = direction.normalized()
		next_length = clampf(length, 0.05, max_tension_length)
		next_length = _clamp_length_to_walls(next_direction, next_length)
	var was_tensioned := tensioned
	var changed: bool = active != tensioned
	if changed:
		tension_version += 1
	_apply_tension(active, next_direction, next_length)
	if was_tensioned and not tensioned:
		_release_grapplers()
		if is_multiplayer_authority():
			var api: MultiplayerAPI = get_multiplayer()
			# The final slack message is reliable: losing it used to leave a
			# teammate grappled to a rope that snapped back through a wall.
			if api != null and api.multiplayer_peer != null:
				rpc("rpc_release_tail_slack", tension_version)
	if changed:
		_tension_send_timer = 0.0
	if is_multiplayer_authority() and (_tension_send_timer <= 0.0 or changed):
		var api: MultiplayerAPI = get_multiplayer()
		if api != null and api.multiplayer_peer != null:
			rpc("rpc_apply_tension", tensioned, tension_direction, tension_length, tension_version)
		_tension_send_timer = TENSION_SEND_INTERVAL


@rpc("authority", "call_remote", "unreliable")
func rpc_apply_tension(active: bool, direction: Vector3, length: float, version: int) -> void:
	if not elastic or version < _last_applied_version:
		return
	_last_applied_version = version
	var was_tensioned := tensioned
	_apply_tension(active, direction, length)
	if was_tensioned and not tensioned:
		_release_grapplers()


## Reliable companion to the throttled tension stream. Older packets are
## ignored so a delayed slack cannot cancel a newer pull.
@rpc("authority", "call_remote", "reliable")
func rpc_release_tail_slack(version: int) -> void:
	if not elastic or version < _last_applied_version:
		return
	_last_applied_version = version
	_apply_tension(false, Vector3.FORWARD, 0.0)
	_release_grapplers()


## A kinematic rope can be placed anywhere, so the owner raycasts along the
## tension direction every frame and shortens the rope at the first wall hit.
## Remote peers receive the already clamped length through the tension RPC.
func _clamp_length_to_walls(direction: Vector3, length: float) -> float:
	if length <= 0.0:
		return 0.0
	var world := get_world_3d()
	if world == null:
		return length
	var origin := _owner_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * length, WALL_LAYER_MASK, [])
	var exclusions: Array[RID] = [get_rid()]
	var owner_node := get_parent()
	if owner_node is Node3D:
		exclusions.append((owner_node as Node3D).get_rid())
	query.exclude = exclusions
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return length
	var hit_position: Vector3 = hit.get("position", origin + direction * length)
	return clampf(origin.distance_to(hit_position) - WALL_MARGIN, 0.0, length)


## Slack rope must not drag a grappling teammate back through walls when the
## frozen body snaps to its rest transform. Remote peers run this from the
## tension RPC, so the climber that is actually simulated drops the anchor.
func _release_grapplers() -> void:
	if owner_peer_id <= 0:
		return
	for climber in get_tree().get_nodes_in_group("climbers"):
		if climber.has_method("release_tail_anchor"):
			climber.call("release_tail_anchor", owner_peer_id)


func _apply_tension(active: bool, direction: Vector3, length: float) -> void:
	tensioned = active and elastic and carrier_id == 0
	tension_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	tension_length = clampf(length, 0.0, max_tension_length) if tensioned else 0.0
	_update_rope_shape()


## A carrier takes control of the tail; releasing it flings it with the given
## velocity and starts the timer that snaps it back to its owner.
func set_carrier(peer_id: int, throw_velocity: Vector3 = Vector3.ZERO) -> void:
	if carrier_id == peer_id:
		return
	var was_tensioned := tensioned
	carrier_id = maxi(0, peer_id)
	_return_timer = 0.0
	_apply_tension(false, Vector3.FORWARD, 0.0)
	if was_tensioned:
		_release_grapplers()
	if carrier_id > 0:
		top_level = true
		freeze = true
		gravity_scale = 0.0
		collision_mask = 0
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	# Released: the tail is a light, tumbling rope for a short moment. World
	# bodies are on layer 1 with mask 1, so the rope must share that layer for
	# Godot to register the contact in both directions; otherwise it flies
	# straight through walls and the mountain.
	top_level = true
	freeze = false
	gravity_scale = 1.0
	# Keep the rope on its grappleable layer so an owner raycast can still find
	# it, but add world layer 1 so PhysicsServer resolves contacts against the
	# mountain and props. Mask the same layers to make the collision symmetric.
	collision_layer = WALL_LAYER_MASK | 4
	collision_mask = WALL_LAYER_MASK
	# The capsule is thin and the throw is fast; sweep it so a thin wall cannot
	# be skipped between physics ticks.
	continuous_cd = true
	linear_velocity = throw_velocity
	angular_velocity = Vector3(sin(float(prop_id.length())), 1.4, cos(float(prop_id.length()))) * 3.0
	_return_timer = 2.6


func _physics_process(delta: float) -> void:
	_tension_send_timer = maxf(0.0, _tension_send_timer - delta)
	if tensioned and carrier_id == 0:
		_update_rope_shape()
	if carrier_id > 0 or _return_timer <= 0.0:
		return
	_return_timer -= delta
	if _return_timer > 0.0:
		return
	_reset_to_owner()


func _owner_origin() -> Vector3:
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return global_position
	return owner_node.global_transform * rest_transform.origin


func _update_rope_shape() -> void:
	collision_layer = 4 if elastic else 0
	if not elastic or not tensioned or carrier_id > 0:
		if not top_level:
			transform = rest_transform
		scale = Vector3.ONE
		return
	var owner_node := get_parent() as Node3D
	if owner_node == null:
		return
	var origin: Vector3 = _owner_origin()
	var tip: Vector3 = origin + tension_direction * tension_length
	var center: Vector3 = (origin + tip) * 0.5
	var y_axis: Vector3 = tension_direction.normalized()
	var z_axis: Vector3 = y_axis.cross(Vector3.RIGHT)
	if z_axis.length_squared() < 0.001:
		z_axis = y_axis.cross(Vector3.FORWARD)
	z_axis = z_axis.normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	var rope_basis := Basis(x_axis, y_axis, z_axis)
	var rope_scale := Vector3(1.0, maxf(0.05, tension_length / 1.3), 1.0)
	global_transform = Transform3D(rope_basis.scaled(rope_scale), center)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _reset_to_owner() -> void:
	carrier_id = 0
	_return_timer = 0.0
	top_level = false
	transform = rest_transform
	scale = Vector3.ONE
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	gravity_scale = 0.0
	collision_layer = 4 if elastic else 0
	collision_mask = 0
	continuous_cd = false
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
