extends RigidBody3D
class_name Climber

signal stamina_changed(current: float, max_val: float)
signal stretch_changed(value: float, overloaded: bool)
signal ragdoll_started
signal ragdoll_ended
signal died(reason: String)
signal checkpoint_reached(y: float)
signal summit_reached
signal landed
signal anchor_changed
signal carry_changed(kind: int, target_id: String)
signal jetpack_changed(equipped: bool, fuel: float)
signal notice_requested(text: String)

const MAX_STRETCH: float = 1.4
const OVERLOAD_THRESHOLD: float = 0.85
const OVERLOAD_TIME: float = 1.1
const FALL_LIMIT_Y: float = -12.0
const PROP_LAYER_MASK: int = 4

class ArmAnchor:
	var anchored: bool = false
	var point: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var rope_length: float = 1.0
	var is_flat: bool = false
	var extend: float = 0.0
	var shooting: bool = false
	var body: RigidBody3D = null
	var body_id: String = ""
	var body_local_point: Vector3 = Vector3.ZERO


@export_group("Identity")
@export var peer_id: int = 1
@export var display_name: String = "Climber"
@export var player_color: Color = Color(0.35, 0.75, 1.0)
@export var is_local: bool = false

@export_group("Replicated state")
@export var max_stamina: float = 100.0
@export var current_stamina: float = 100.0: set = set_current_stamina
@export var stretch: float = 0.0: set = set_stretch
@export var ragdoll_active: bool = false: set = set_ragdoll_active
@export var highest_y: float = 0.0
@export var checkpoint_y: float = 0.0
@export var replicated_position: Vector3 = Vector3.ZERO
@export var replicated_yaw: float = 0.0
@export var lives: int = 3
@export var max_lives: int = 3

@export_group("Nodes")
@export var camera_pivot: Node3D
@export var left_arm: MeshInstance3D
@export var right_arm: MeshInstance3D
@export var ragdoll_rig: Node3D
@export var body_mesh: MeshInstance3D
@export var head_mesh: MeshInstance3D
@export var jetpack_visual: Node3D

@export_group("Harpoon")
@export var harpoon_reach: float = 35.0
@export var climbable_mask: int = 1
@export var pull_force: float = 620.0
@export var arm_damping: float = 30.0
@export var rope_min: float = 0.9
@export var reel_rate: float = 3.2
@export var rappel_max_speed: float = 2.6
@export var winch_step: float = 0.45
@export var arm_projectile_speed: float = 70.0

@export_group("Movement")
@export var walk_speed: float = 7.2
@export var walk_acceleration: float = 22.0
@export var air_speed: float = 6.4
@export var air_acceleration: float = 14.0
@export var ground_jump_velocity: float = 7.2
@export var ground_brake: float = 14.0
@export var ground_ray_length: float = 1.25
@export var upright_spring: float = 340.0
@export var upright_damper: float = 32.0

@export_group("Mantle")
@export var mantle_lift_speed: float = 6.5
@export var mantle_forward_speed: float = 4.6
@export var mantle_duration: float = 0.5
@export var mantle_walk_impulse: float = 4.0
@export var mantle_trigger_dist: float = 3.2
@export var mantle_max_height: float = 3.2
@export var mantle_cost: float = 6.0

@export_group("Carry")
@export var carry_reach: float = 3.6
@export var carry_drain_base: float = 5.0
@export var carry_drain_per_kg: float = 0.28
@export var carry_stretch_gain: float = 0.35
@export var carry_spring: float = 26.0
@export var carry_damping: float = 8.0
@export var carry_weight_factor: float = 0.32

@export_group("Jetpack")
@export var jetpack_thrust: float = 15.0
@export var jetpack_fuel_drain: float = 22.0
@export var jetpack_fuel_max: float = 100.0

@export_group("Stamina and stretch")
@export var stamina_regen: float = 30.0
@export var stretch_gain: float = 0.14
@export var stretch_recovery: float = 0.55
@export var stretched_drain: float = 12.0
@export var single_arm_drain: float = 11.0
@export var double_arm_drain: float = 6.0
@export var exhausted_threshold: float = 12.0
@export var invulnerability_time: float = 0.9

@export_group("Progress")
@export var checkpoint_interval: float = 20.0
@export var summit_y: float = 120.0

var left_anchor: ArmAnchor = ArmAnchor.new()
var right_anchor: ArmAnchor = ArmAnchor.new()
var carry_kind: int = -1
var carry_target_id: String = ""
var carried_by_peer: int = 0
var has_jetpack: bool = false
var jetpack_fuel: float = 0.0
var control_disabled: bool = false
var dead: bool = false
var exhausted: bool = false
var is_mantling: bool = false
var mantle_timer: float = 0.0
var mantle_cooldown: float = 0.0
var mantle_target_y: float = 0.0
var mantle_dir: Vector3 = Vector3.FORWARD
var stretch_overload_timer: float = 0.0
var stun_timer: float = 0.0
var invulnerability_timer: float = 0.0
var ragdoll_timer: float = 0.0
var ragdoll_duration: float = 3.0
var walk_cycle: float = 0.0
var was_grounded: bool = true
var summit_emitted: bool = false
var visual_send_timer: float = 0.0

var _remote_position_ready: bool = false
var _remote_left_point: Vector3 = Vector3.ZERO
var _remote_right_point: Vector3 = Vector3.ZERO
var _remote_left_on: bool = false
var _remote_right_on: bool = false
var _default_physics_material: PhysicsMaterial
var _carry_node: Node = null
var _carrier_node: Node = null
var _jetpack_flame: MeshInstance3D = null
var _prop_report_timer: float = 0.0
var _prop_pull_timer: float = 0.0
var _pending_prop_pulls: Dictionary = {}


func _ready() -> void:
	add_to_group("climbers")
	can_sleep = false
	linear_damp = 1.0
	angular_damp = 4.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.12, 0.0)

	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	_default_physics_material = physics_material_override.duplicate() as PhysicsMaterial
	_default_physics_material.friction = 1.0
	_default_physics_material.bounce = 0.0
	physics_material_override = _default_physics_material

	_resolve_nodes()
	_setup_jetpack_visual()
	_apply_color()
	_configure_synchronizer()
	_apply_authority_mode()
	_refresh_visuals()
	stamina_changed.emit(current_stamina, max_stamina)
	stretch_changed.emit(stretch, stretch >= OVERLOAD_THRESHOLD)


func _exit_tree() -> void:
	if is_local and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func configure(new_peer_id: int, new_display_name: String, new_color: Color) -> void:
	peer_id = maxi(1, new_peer_id)
	display_name = new_display_name
	player_color = new_color
	_configure_synchronizer()
	_apply_color()
	if is_node_ready():
		_apply_authority_mode()
		_refresh_visuals()


func get_state() -> Dictionary:
	var grounded: bool = false
	if is_inside_tree() and get_world_3d() != null:
		grounded = _is_grounded()
	return {
		"peer_id": peer_id,
		"display_name": display_name,
		"player_color": player_color,
		"position": global_position,
		"velocity": linear_velocity,
		"stamina": current_stamina,
		"max_stamina": max_stamina,
		"stretch": stretch,
		"overloaded": stretch >= OVERLOAD_THRESHOLD,
		"ragdoll_active": ragdoll_active,
		"carry_kind": carry_kind,
		"carry_target_id": carry_target_id,
		"carried_by_peer": carried_by_peer,
		"has_jetpack": has_jetpack,
		"jetpack_fuel": jetpack_fuel,
		"left_anchored": left_anchor.anchored,
		"right_anchored": right_anchor.anchored,
		"grounded": grounded,
		"highest_y": highest_y,
		"checkpoint_y": checkpoint_y,
		"lives": lives,
		"is_local": is_local,
		"dead": dead,
		"stunned": stun_timer > 0.0,
	}


func respawn_at(pos: Vector3, restore_life: bool = false) -> void:
	dead = false
	control_disabled = false
	stun_timer = 0.0
	invulnerability_timer = invulnerability_time
	summit_emitted = false
	mantle_cooldown = 0.0
	is_mantling = false

	if ragdoll_active and ragdoll_rig != null:
		ragdoll_rig.call("deactivate")
	ragdoll_active = false
	ragdoll_timer = 0.0
	_release_arm(true)
	_release_arm(false)
	_clear_carry_local()
	carried_by_peer = 0
	_carrier_node = null
	stretch = 0.0
	stretch_overload_timer = 0.0
	current_stamina = max_stamina
	if restore_life:
		lives = max_lives

	_apply_freeze()
	global_transform = Transform3D(Basis.IDENTITY, pos)
	replicated_position = pos
	_remote_position_ready = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	highest_y = pos.y
	checkpoint_y = pos.y
	_refresh_visuals()
	stamina_changed.emit(current_stamina, max_stamina)
	stretch_changed.emit(stretch, false)


func apply_hazard(impulse: Vector3, label: String) -> void:
	if dead or invulnerability_timer > 0.0:
		return
	if ragdoll_active and ragdoll_rig != null and ragdoll_rig.has_method("get_parts"):
		var parts: Array = ragdoll_rig.call("get_parts")
		if not parts.is_empty():
			parts[0].apply_central_impulse(impulse * parts[0].mass * 0.5)
	elif is_local and not freeze:
		apply_central_impulse(impulse * mass)
	stun_timer = 0.4
	notice_requested.emit(label)


func apply_bounce(impulse: Vector3, label: String) -> void:
	if dead or ragdoll_active or carried_by_peer > 0:
		return
	if is_local:
		apply_central_impulse(impulse * mass)
	notice_requested.emit(label)


func start_ragdoll() -> void:
	if ragdoll_active or dead:
		return
	_release_arm(true)
	_release_arm(false)
	_clear_carry_local()
	_request_drop()
	carried_by_peer = 0
	_carrier_node = null
	is_mantling = false
	control_disabled = true
	var body_xform: Transform3D = global_transform
	var body_velocity: Vector3 = linear_velocity
	var kick: float = stretch
	ragdoll_active = true
	freeze = true
	if ragdoll_rig != null:
		ragdoll_rig.call("activate", body_xform, body_velocity, kick, player_color)
	_refresh_visuals()
	ragdoll_timer = ragdoll_duration
	stretch_overload_timer = 0.0
	current_stamina = maxf(0.0, current_stamina - 12.0)
	stun_timer = 0.0
	ragdoll_started.emit()
	notice_requested.emit("OVERLOAD")


func recover() -> void:
	if not ragdoll_active:
		return
	if ragdoll_rig != null:
		ragdoll_rig.call("deactivate")
	var upright_position: Vector3 = global_position + (Vector3.UP * 0.2)
	ragdoll_active = false
	control_disabled = false
	ragdoll_timer = 0.0
	stretch = 0.0
	stretch_overload_timer = 0.0
	_release_arm(true)
	_release_arm(false)
	current_stamina = maxf(current_stamina, max_stamina * 0.35)
	_apply_freeze()
	global_transform = Transform3D(Basis.IDENTITY, upright_position)
	replicated_position = upright_position
	_remote_position_ready = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	invulnerability_timer = invulnerability_time
	_refresh_visuals()
	ragdoll_ended.emit()
	notice_requested.emit("RECOVERED")


func set_current_stamina(value: float) -> void:
	var bounded: float = clampf(value, 0.0, maxf(1.0, max_stamina))
	if is_equal_approx(bounded, current_stamina):
		return
	current_stamina = bounded
	stamina_changed.emit(current_stamina, max_stamina)


func set_stretch(value: float) -> void:
	var bounded: float = clampf(value, 0.0, MAX_STRETCH)
	if is_equal_approx(bounded, stretch):
		return
	stretch = bounded
	stretch_changed.emit(stretch, stretch >= OVERLOAD_THRESHOLD)


func set_ragdoll_active(value: bool) -> void:
	if value == ragdoll_active:
		return
	ragdoll_active = value
	if not is_node_ready():
		return
	_refresh_visuals()
	if not is_local and ragdoll_rig != null:
		if value:
			var xform: Transform3D = global_transform
			ragdoll_rig.call("activate_remote", xform)
		else:
			ragdoll_rig.call("deactivate")


func _resolve_nodes() -> void:
	if camera_pivot == null:
		camera_pivot = find_child("CameraPivot", true, false) as Node3D
	if left_arm == null:
		left_arm = find_child("LeftArm", true, false) as MeshInstance3D
	if right_arm == null:
		right_arm = find_child("RightArm", true, false) as MeshInstance3D
	if ragdoll_rig == null:
		ragdoll_rig = find_child("RagdollRig", true, false) as Node3D
	if body_mesh == null:
		body_mesh = get_node_or_null("Body") as MeshInstance3D
	if head_mesh == null:
		head_mesh = get_node_or_null("Head") as MeshInstance3D
	if jetpack_visual == null:
		jetpack_visual = get_node_or_null("JetpackVisual") as Node3D


func _configure_synchronizer() -> void:
	var synchronizer := get_node_or_null("StateSync") as MultiplayerSynchronizer
	if synchronizer == null:
		synchronizer = MultiplayerSynchronizer.new()
		synchronizer.name = "StateSync"
		add_child(synchronizer)
	if synchronizer.replication_config != null and not synchronizer.replication_config.get_properties().is_empty():
		return

	var config := SceneReplicationConfig.new()
	var paths: Array[String] = [
		"replicated_position",
		"replicated_yaw",
		"current_stamina",
		"stretch",
		"ragdoll_active",
		"carry_kind",
		"carried_by_peer",
		"has_jetpack",
		"jetpack_fuel",
		"display_name",
		"player_color",
		"highest_y",
		"checkpoint_y",
		"lives",
	]
	for path in paths:
		config.add_property(NodePath(".:" + path))
	synchronizer.replication_config = config
	synchronizer.replication_interval = 0.05


func _own_peer_id() -> int:
	var net: Node = get_node_or_null("/root/Net")
	if net != null:
		var value: Variant = net.get("peer_id")
		if value != null and int(value) > 0:
			return int(value)
	var api: MultiplayerAPI = get_multiplayer()
	if api != null:
		var network_id: int = api.get_unique_id()
		if network_id > 0:
			return network_id
	return 1


func _apply_freeze() -> void:
	freeze = not is_local
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


func _apply_authority_mode() -> void:
	set_multiplayer_authority(peer_id, true)
	is_local = peer_id == _own_peer_id()
	_apply_freeze()

	if camera_pivot != null and camera_pivot.has_method("setup_local"):
		camera_pivot.call("setup_local", is_local)
	elif camera_pivot != null:
		camera_pivot.visible = is_local
	_refresh_visuals()


func _make_material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.42
	material.metallic = 0.05
	material.emission_enabled = true
	material.emission = color.darkened(glow)
	return material


func _apply_color() -> void:
	if body_mesh != null:
		body_mesh.material_override = _make_material(player_color, 0.62)
	if head_mesh != null:
		head_mesh.material_override = _make_material(player_color.lightened(0.18), 0.55)
	if left_arm != null and left_arm.has_method("set_color"):
		left_arm.call("set_color", player_color)
	if right_arm != null and right_arm.has_method("set_color"):
		right_arm.call("set_color", player_color)
	if ragdoll_rig != null and ragdoll_rig.has_method("apply_color"):
		ragdoll_rig.call("apply_color", player_color)


func _refresh_visuals() -> void:
	var hidden: bool = ragdoll_active or dead
	if body_mesh != null:
		body_mesh.visible = not hidden and not is_local
	if head_mesh != null:
		head_mesh.visible = not hidden and not is_local
	if left_arm != null:
		left_arm.visible = not hidden
	if right_arm != null:
		right_arm.visible = not hidden
	if jetpack_visual != null:
		jetpack_visual.visible = not hidden and has_jetpack
	if _jetpack_flame != null:
		_jetpack_flame.visible = false


func _setup_jetpack_visual() -> void:
	if jetpack_visual == null:
		jetpack_visual = Node3D.new()
		jetpack_visual.name = "JetpackVisual"
		add_child(jetpack_visual)
	jetpack_visual.position = Vector3(0.0, 0.14, 0.24)
	jetpack_visual.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	const model_path := "res://assets/models/jetpack.glb"
	if ResourceLoader.exists(model_path):
		var packed := load(model_path) as PackedScene
		if packed != null:
			jetpack_visual.add_child(packed.instantiate())
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.12
	cone.height = 0.5
	cone.radial_segments = 12
	flame.mesh = cone
	flame.position = Vector3(0.0, -0.58, 0.0)
	flame.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color(0.4, 0.92, 1.0)
	flame_material.emission_enabled = true
	flame_material.emission = Color(0.15, 0.8, 1.0)
	flame_material.emission_energy_multiplier = 3.2
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.material_override = flame_material
	jetpack_visual.add_child(flame)
	_jetpack_flame = flame
	jetpack_visual.visible = false


func _game_manager() -> Node:
	return get_tree().root.get_node_or_null("Game")


func _find_prop(prop_id_value: String) -> Node:
	for node in get_tree().get_nodes_in_group("climb_props"):
		if str(node.get("prop_id")) == prop_id_value:
			return node
	return null


func _find_climber(peer: int) -> Node:
	if peer <= 0:
		return null
	for node in get_tree().get_nodes_in_group("climbers"):
		if int(node.get("peer_id")) == peer:
			return node
	return null


func get_carry_hold_point() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z.normalized()
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	return global_position + forward.normalized() * 0.95 + (Vector3.UP * 0.25)


func set_carry(kind_value: int, target_id_value: String) -> void:
	if kind_value == carry_kind and target_id_value == carry_target_id:
		return
	_clear_carry_local()
	carry_kind = kind_value
	carry_target_id = target_id_value
	if kind_value == 0:
		_carry_node = _find_prop(target_id_value)
	elif kind_value == 1:
		_carry_node = _find_climber(int(target_id_value))
	stretch_overload_timer = 0.0
	carry_changed.emit(carry_kind, carry_target_id)


func _clear_carry_local() -> void:
	if carry_kind == 0 and is_instance_valid(_carry_node) and _carry_node.has_method("set_carrier"):
		if int(_carry_node.get("carrier_id")) == peer_id:
			_carry_node.call("set_carrier", 0)
	carry_kind = -1
	carry_target_id = ""
	_carry_node = null
	_prop_report_timer = 0.0
	carry_changed.emit(carry_kind, carry_target_id)


func set_carried_by(peer: int) -> void:
	if carried_by_peer == peer:
		return
	carried_by_peer = maxi(0, peer)
	_carrier_node = null
	if carried_by_peer > 0:
		_carrier_node = _find_climber(carried_by_peer)
	stretch_overload_timer = 0.0
	carry_changed.emit(carry_kind, carry_target_id)


func equip_jetpack(amount: float) -> void:
	if not has_jetpack:
		has_jetpack = true
		jetpack_fuel = clampf(amount, 0.0, jetpack_fuel_max)
	else:
		jetpack_fuel = clampf(jetpack_fuel + amount, 0.0, jetpack_fuel_max)
	jetpack_changed.emit(has_jetpack, jetpack_fuel)
	_refresh_visuals()
	notice_requested.emit("JETPACK READY")


func _request_carry() -> void:
	if ragdoll_active or dead or control_disabled or carried_by_peer > 0:
		return
	if carry_kind != -1:
		_request_drop()
		return
	var kind := -1
	var target_id := ""
	var best_distance := carry_reach
	var world := get_world_3d()
	var camera := _get_camera()
	if world != null and camera != null:
		var from: Vector3 = camera.global_position
		var direction: Vector3 = -camera.global_transform.basis.z.normalized()
		for query_mask in [4, 2]:
			var query := PhysicsRayQueryParameters3D.create(from, from + (direction * carry_reach), query_mask, [])
			query.exclude = _ray_exclusions()
			var hit := world.direct_space_state.intersect_ray(query)
			if hit.is_empty():
				continue
			var collider := hit.collider as Node
			if collider == null:
				continue
			var distance := from.distance_to(hit.position)
			if distance >= best_distance:
				continue
			if collider.has_method("set_carrier") and not collider.has_method("get_state"):
				kind = 0
				target_id = str(collider.get("prop_id"))
				best_distance = distance
			elif collider.has_method("get_state") and int(collider.get("peer_id")) != peer_id:
				kind = 1
				target_id = str(int(collider.get("peer_id")))
				best_distance = distance

	if kind == -1:
		for prop in get_tree().get_nodes_in_group("climb_props"):
			if int(prop.get("carrier_id")) > 0:
				continue
			var distance := global_position.distance_to(prop.global_position)
			if distance < 2.6 and distance < best_distance:
				kind = 0
				target_id = str(prop.get("prop_id"))
				best_distance = distance
	for climber in get_tree().get_nodes_in_group("climbers"):
		if int(climber.get("peer_id")) == peer_id or bool(climber.get("ragdoll_active")) or bool(climber.get("dead")):
			continue
		if int(climber.get("carried_by_peer")) > 0:
			continue
		var distance := global_position.distance_to(climber.global_position)
		if distance < 2.4 and distance < best_distance:
			kind = 1
			target_id = str(int(climber.get("peer_id")))
			best_distance = distance

	if kind == -1:
		notice_requested.emit("NOTHING TO GRAB")
		return
	var manager := _game_manager()
	if manager != null and manager.has_method("request_carry"):
		manager.call("request_carry", kind, target_id)


func _request_drop() -> void:
	var manager := _game_manager()
	if manager != null and manager.has_method("request_drop"):
		manager.call("request_drop")


func _carry_mass() -> float:
	if not is_instance_valid(_carry_node):
		return 0.0
	if carry_kind == 0:
		return maxf(1.0, float(_carry_node.get("mass_kg")))
	return maxf(1.0, float(_carry_node.get("mass")))


func _process_active_carry(delta: float) -> void:
	if not is_instance_valid(_carry_node):
		return
	if carry_kind == 0:
		var prop := _carry_node
		var basis := Basis.looking_at(-global_transform.basis.z.normalized(), Vector3.UP)
		var target := Transform3D(basis, get_carry_hold_point())
		prop.global_transform = prop.global_transform.interpolate_with(target, clampf(delta * 14.0, 0.0, 1.0))
		prop.linear_velocity = linear_velocity
		prop.angular_velocity = Vector3.ZERO
		apply_central_force(Vector3.DOWN * float(prop.get("mass_kg")) * 9.8 * carry_weight_factor)
		_prop_report_timer -= delta
		if _prop_report_timer <= 0.0:
			_prop_report_timer = 0.05
			var manager := _game_manager()
			if manager != null and manager.has_method("report_carried_prop"):
				var water_value: float = -1.0
				var water_variant: Variant = prop.get("water")
				if water_variant != null:
					water_value = float(water_variant)
				manager.call("report_carried_prop", str(prop.get("prop_id")), prop.global_transform, prop.linear_velocity, prop.angular_velocity, water_value)
	elif carry_kind == 1:
		apply_central_force(Vector3.DOWN * _carry_mass() * 9.8 * carry_weight_factor)


func _process_carried(delta: float) -> void:
	if not is_instance_valid(_carrier_node):
		return
	var target: Vector3 = _carrier_node.global_position + (Vector3.UP * 1.0)
	if _carrier_node.has_method("get_carry_hold_point"):
		target = _carrier_node.call("get_carry_hold_point")
	var offset: Vector3 = target - global_position
	apply_central_force((offset * carry_spring * mass) - (linear_velocity * carry_damping * mass))
	_apply_upright_balance()


func _sync_replicated_transform() -> void:
	replicated_position = global_position
	if camera_pivot != null and camera_pivot.has_method("get_aim_forward"):
		var aim: Vector3 = camera_pivot.call("get_aim_forward")
		aim.y = 0.0
		if aim.length_squared() > 0.0001:
			replicated_yaw = atan2(-aim.x, -aim.z)
			return
	if not is_zero_approx(linear_velocity.x) or not is_zero_approx(linear_velocity.z):
		replicated_yaw = atan2(-linear_velocity.x, -linear_velocity.z)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ragdoll_active:
		return
	var value := state.transform
	var forward := -value.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	value.basis = Basis.looking_at(forward.normalized(), Vector3.UP)
	state.transform = value
	var angular := state.angular_velocity
	state.angular_velocity = Vector3(0.0, angular.y, 0.0)


func _apply_remote_transform(delta: float) -> void:
	if ragdoll_active:
		return
	if not _remote_position_ready:
		global_position = replicated_position
		_remote_position_ready = true
	else:
		var drift: float = global_position.distance_to(replicated_position)
		if drift > 8.0:
			global_position = replicated_position
		else:
			global_position = global_position.lerp(replicated_position, clampf(delta * 18.0, 0.0, 1.0))
	var value := global_transform
	value.basis = Basis(Vector3.UP, replicated_yaw)
	global_transform = value


func _physics_process(delta: float) -> void:
	if is_local:
		_sync_replicated_transform()
	if not is_local or dead:
		_apply_remote_transform(delta)
		_update_arm_visuals(delta)
		return

	invulnerability_timer = maxf(0.0, invulnerability_timer - delta)
	stun_timer = maxf(0.0, stun_timer - delta)
	mantle_cooldown = maxf(0.0, mantle_cooldown - delta)

	_track_progress()

	if Input.is_action_just_pressed("carry") and not ragdoll_active and carried_by_peer <= 0:
		_request_carry()

	if ragdoll_active:
		_process_ragdoll(delta)
	elif carried_by_peer > 0:
		_process_carried(delta)
	elif control_disabled:
		pass
	else:
		_process_climb(delta)

	_update_stamina(delta)
	_update_arm_visuals(delta)
	_send_visual_state(delta)
	_flush_prop_pulls(delta)
	_check_fall()


func _process_ragdoll(delta: float) -> void:
	if ragdoll_rig != null and ragdoll_rig.has_method("get_hips_position"):
		global_position = ragdoll_rig.call("get_hips_position")
		linear_velocity = ragdoll_rig.call("get_hips_velocity")
	ragdoll_timer -= delta
	if ragdoll_timer <= 0.0:
		recover()


func _process_climb(delta: float) -> void:
	var grounded: bool = _is_grounded()
	if grounded and not was_grounded and linear_velocity.y < -1.5:
		landed.emit()
	was_grounded = grounded

	if is_mantling:
		_process_mantle(delta)
		return

	if stun_timer <= 0.0:
		_apply_upright_balance()
		_handle_arm_input()
		_handle_wheel_input()
		_process_active_carry(delta)
		_update_jetpack(delta)
		_update_stretch(delta)
		if ragdoll_active:
			return
		_apply_arm_forces()
		_apply_movement(delta, grounded)
		_handle_jump(grounded)

	if grounded:
		walk_cycle += delta * 10.0 * clampf(Vector3(linear_velocity.x, 0.0, linear_velocity.z).length() / 6.0, 0.0, 1.5)


func _update_jetpack(delta: float) -> void:
	var thrusting: bool = has_jetpack and jetpack_fuel > 0.0 and Input.is_action_pressed("jetpack")
	if _jetpack_flame != null:
		_jetpack_flame.visible = thrusting
	if not thrusting:
		return
	var direction := Vector3.UP
	var axis := _move_input()
	if axis.length_squared() > 0.01:
		var basis := Basis.looking_at(-global_transform.basis.z.normalized(), Vector3.UP)
		var wish: Vector3 = -basis.z * axis.y + basis.x * axis.x
		direction = (Vector3.UP + wish * 0.55).normalized()
	apply_central_force(direction * jetpack_thrust * mass)
	jetpack_fuel = maxf(0.0, jetpack_fuel - jetpack_fuel_drain * delta)
	jetpack_changed.emit(has_jetpack, jetpack_fuel)


func _is_grounded() -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + (Vector3.DOWN * ground_ray_length),
		climbable_mask,
		[]
	)
	query.exclude = _ray_exclusions()
	return not world.direct_space_state.intersect_ray(query).is_empty()


func _move_input() -> Vector2:
	var forward: float = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var side: float = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var input := Vector2(clampf(side, -1.0, 1.0), clampf(forward, -1.0, 1.0))
	if input.length() > 1.0:
		input = input.normalized()
	return input


func _apply_upright_balance() -> void:
	if camera_pivot == null or not camera_pivot.has_method("get_aim_forward"):
		return
	var aim: Vector3 = camera_pivot.call("get_aim_forward")
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(aim.normalized(), Vector3.UP)
	var current_quat: Quaternion = global_transform.basis.get_rotation_quaternion()
	var diff: Quaternion = target_basis.get_rotation_quaternion() * current_quat.inverse()
	var axis := Vector3(diff.x, diff.y, diff.z)
	if diff.w < 0.0:
		axis = -axis
	var yaw_torque: float = axis.y * upright_spring - angular_velocity.y * upright_damper
	apply_torque(Vector3.UP * yaw_torque)


func count_anchors() -> int:
	var count: int = 0
	if left_anchor.anchored:
		count += 1
	if right_anchor.anchored:
		count += 1
	return count


func is_climbing() -> bool:
	return (left_anchor.anchored and not left_anchor.is_flat) or (right_anchor.anchored and not right_anchor.is_flat)


func _get_camera() -> Camera3D:
	if camera_pivot == null:
		return null
	return camera_pivot.get_node_or_null("Camera3D") as Camera3D


func _ray_exclusions() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	if ragdoll_rig != null and ragdoll_rig.has_method("get_parts"):
		var parts: Array = ragdoll_rig.call("get_parts")
		for part in parts:
			excluded.append(part.get_rid())
	return excluded


func _handle_arm_input() -> void:
	if Input.is_action_just_pressed("arm_left"):
		_fire_arm(true)
	elif Input.is_action_just_released("arm_left"):
		_release_arm(true)
	if Input.is_action_just_pressed("arm_right"):
		_fire_arm(false)
	elif Input.is_action_just_released("arm_right"):
		_release_arm(false)


func _fire_arm(left: bool) -> void:
	if ragdoll_active or carried_by_peer > 0 or stun_timer > 0.0:
		return
	var arm: ArmAnchor = left_anchor if left else right_anchor
	if not arm.anchored and current_stamina < 5.0:
		notice_requested.emit("LOW STAMINA")
		return
	var camera: Camera3D = _get_camera()
	if camera == null:
		return
	var world := get_world_3d()
	if world == null:
		return

	var from: Vector3 = camera.global_position
	var reach: float = harpoon_reach * (1.0 + stretch * 0.25)
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var query := PhysicsRayQueryParameters3D.create(from, from + (direction * reach), climbable_mask | PROP_LAYER_MASK, [])
	query.exclude = _ray_exclusions()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if hit.collider == self:
		return
	arm.body = null
	arm.body_id = ""
	arm.body_local_point = Vector3.ZERO
	if hit.collider is RigidBody3D:
		var body := hit.collider as RigidBody3D
		if not body.has_method("can_be_grappled") or not bool(body.call("can_be_grappled")):
			return
		arm.body = body
		arm.body_id = str(body.get("prop_id"))
		arm.body_local_point = body.global_transform.affine_inverse() * hit.position

	arm.anchored = true
	arm.point = hit.position
	arm.normal = hit.normal
	arm.is_flat = hit.normal.y > 0.6
	arm.rope_length = clampf(from.distance_to(hit.position), rope_min, reach)
	arm.shooting = true
	arm.extend = 0.0

	var mesh: MeshInstance3D = left_arm if left else right_arm
	if mesh != null and mesh.has_method("flash_anchor"):
		mesh.call("flash_anchor", arm.point)
	current_stamina = maxf(0.0, current_stamina - 1.5)
	anchor_changed.emit()
	_force_arm_visual_send()


func _release_arm(left: bool) -> void:
	var arm: ArmAnchor = left_anchor if left else right_anchor
	if not arm.anchored:
		return
	arm.anchored = false
	arm.is_flat = false
	arm.shooting = false
	arm.extend = 0.0
	arm.rope_length = rope_min
	arm.body = null
	arm.body_id = ""
	arm.body_local_point = Vector3.ZERO
	anchor_changed.emit()
	_force_arm_visual_send()


func _release_all_arms() -> void:
	_release_arm(true)
	_release_arm(false)


func _apply_arm_forces() -> void:
	if count_anchors() == 0:
		return
	var power: float = 1.0 if not exhausted else 0.38
	var reach_bonus: float = 1.0 + stretch * 0.65
	for arm in [left_anchor, right_anchor]:
		if not arm.anchored:
			continue
		if arm.body != null:
			if not is_instance_valid(arm.body) or not arm.body.has_method("can_be_grappled") or not bool(arm.body.call("can_be_grappled")):
				arm.anchored = false
				arm.body = null
				continue
			arm.point = arm.body.global_transform * arm.body_local_point
		var delta_vector: Vector3 = arm.point - global_position
		var distance: float = delta_vector.length()
		var rest: float = arm.rope_length * reach_bonus
		if distance <= rest or distance < 0.01:
			continue
		var direction: Vector3 = delta_vector / distance
		var magnitude: float = (distance - rest) * pull_force * (1.0 + stretch * 0.75) * power
		magnitude -= linear_velocity.dot(direction) * arm_damping
		if magnitude <= 0.0:
			continue
		apply_central_force(direction * magnitude)
		if arm.body != null and not arm.body_id.is_empty():
			var reaction: Vector3 = -direction * minf(magnitude * 0.7, 900.0)
			var previous: Vector3 = _pending_prop_pulls.get(arm.body_id, Vector3.ZERO)
			_pending_prop_pulls[arm.body_id] = previous + reaction


func _flush_prop_pulls(delta: float) -> void:
	_prop_pull_timer -= delta
	if _pending_prop_pulls.is_empty():
		_prop_pull_timer = 0.0
		return
	if _prop_pull_timer > 0.0:
		return
	_prop_pull_timer = 0.05
	var manager := _game_manager()
	if manager != null and manager.has_method("report_prop_pull"):
		for key in _pending_prop_pulls.keys():
			manager.call("report_prop_pull", str(key), _pending_prop_pulls[key] as Vector3)
	_pending_prop_pulls.clear()


func _handle_wheel_input() -> void:
	if Input.is_action_just_pressed("winch_up"):
		_apply_wheel(-winch_step)
	if Input.is_action_just_pressed("winch_down"):
		_apply_wheel(winch_step)


func _apply_wheel(amount: float) -> void:
	if count_anchors() == 0:
		return
	var pull_direction := Vector3.ZERO
	var adjusted: int = 0
	for arm in [left_anchor, right_anchor]:
		if not arm.anchored:
			continue
		arm.rope_length = clampf(arm.rope_length + amount, rope_min, harpoon_reach)
		pull_direction += (arm.point - global_position).normalized()
		adjusted += 1
	if adjusted == 0 or pull_direction.length_squared() < 0.001:
		return
	var average: Vector3 = pull_direction.normalized()
	if amount < 0.0:
		var lift: Vector3 = (average * 0.65 + Vector3.UP * 0.5).normalized()
		apply_central_impulse(lift * 2.0 * mass)
	else:
		apply_central_impulse(Vector3.DOWN * 1.4 * mass)


func _update_stretch(delta: float) -> void:
	var lifting: bool = carry_kind != -1 and is_instance_valid(_carry_node) and current_stamina > 0.0
	if lifting:
		var efficiency: float = 1.0 if current_stamina > exhausted_threshold else 0.62
		var load_factor: float = clampf(_carry_mass() / 50.0, 0.25, 1.5)
		stretch += stretch_gain * carry_stretch_gain * load_factor * efficiency * delta
		if stretch >= OVERLOAD_THRESHOLD:
			stretch_overload_timer += delta
			if stretch_overload_timer >= OVERLOAD_TIME:
				start_ragdoll()
				return
		else:
			stretch_overload_timer = maxf(0.0, stretch_overload_timer - delta * 2.0)
	else:
		stretch = move_toward(stretch, 0.0, stretch_recovery * delta)
		stretch_overload_timer = maxf(0.0, stretch_overload_timer - delta * 2.0)


func _apply_movement(delta: float, grounded: bool) -> void:
	var input: Vector2 = _move_input()
	var speed_scale: float = 0.78 if carry_kind != -1 else 1.0
	var basis: Basis = global_transform.basis
	if camera_pivot != null and camera_pivot.has_method("get_aim_forward"):
		var aim: Vector3 = camera_pivot.call("get_aim_forward")
		aim.y = 0.0
		if aim.length_squared() > 0.001:
			basis = Basis.looking_at(aim, Vector3.UP)
	var forward: Vector3 = -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right: Vector3 = Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	if forward.is_zero_approx():
		forward = -global_transform.basis.z.normalized()
	if right.is_zero_approx():
		right = global_transform.basis.x.normalized()
	var wish: Vector3 = forward * input.y + right * input.x
	if wish.length() > 1.0:
		wish = wish.normalized()

	var horizontal_velocity := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if grounded:
		var can_walk: bool = count_anchors() < 2 and stun_timer <= 0.0
		if can_walk and input.length_squared() > 0.01:
			var target: Vector3 = wish * walk_speed * speed_scale
			apply_central_force((target - horizontal_velocity) * mass * walk_acceleration)
		else:
			apply_central_force(-horizontal_velocity * mass * ground_brake)
		return

	if is_climbing():
		if input.y < -0.1:
			var unroll: float = absf(input.y) * reel_rate * delta
			for arm in [left_anchor, right_anchor]:
				if arm.anchored:
					arm.rope_length = clampf(arm.rope_length + unroll, rope_min, harpoon_reach)
			if linear_velocity.y < -rappel_max_speed:
				linear_velocity.y = move_toward(linear_velocity.y, -rappel_max_speed, delta * 25.0)
		elif input.y > 0.1:
			var haul: float = input.y * reel_rate * (1.0 + stretch * 1.4) * delta
			for arm in [left_anchor, right_anchor]:
				if arm.anchored:
					arm.rope_length = clampf(arm.rope_length - haul, rope_min, harpoon_reach)
			linear_velocity.y = move_toward(linear_velocity.y, 3.2 + stretch * 2.4, delta * 20.0)
		if absf(input.x) > 0.1:
			apply_central_force(right * input.x * mass * air_acceleration * 1.5)
	elif input.length_squared() > 0.01 and stun_timer <= 0.0:
		var target: Vector3 = wish * air_speed * speed_scale
		apply_central_force((target - horizontal_velocity) * mass * air_acceleration)


func _handle_jump(grounded: bool) -> void:
	if not Input.is_action_just_pressed("jump") or stun_timer > 0.0:
		return
	if _try_mantle():
		return
	if grounded and count_anchors() == 0:
		linear_velocity.y = maxf(linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * ground_jump_velocity * mass)


func _try_mantle() -> bool:
	if mantle_cooldown > 0.0 or current_stamina < mantle_cost:
		return false
	var best := Vector3.ZERO
	var found: bool = false
	for arm in [left_anchor, right_anchor]:
		if arm.anchored and arm.is_flat:
			if not found or arm.point.y > best.y:
				best = arm.point
				found = true
	if not found:
		return false

	var distance: float = global_position.distance_to(best)
	var height_diff: float = best.y - global_position.y
	if distance > mantle_trigger_dist or height_diff < -0.4 or height_diff > mantle_max_height:
		return false

	var world := get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(
			best + (Vector3.UP * 0.12),
			best + (Vector3.UP * 1.7),
			climbable_mask,
			[]
		)
		query.exclude = _ray_exclusions()
		if not world.direct_space_state.intersect_ray(query).is_empty():
			return false

	var direction: Vector3 = best - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z
	direction = direction.normalized()

	is_mantling = true
	mantle_timer = mantle_duration
	mantle_target_y = best.y + 0.8
	mantle_dir = direction
	current_stamina = maxf(0.0, current_stamina - mantle_cost)
	linear_velocity = Vector3.ZERO
	_release_all_arms()
	return true


func _process_mantle(delta: float) -> void:
	mantle_timer -= delta
	linear_velocity.y = mantle_lift_speed if global_position.y < mantle_target_y else 1.0
	var target: Vector3 = mantle_dir * mantle_forward_speed
	linear_velocity.x = move_toward(linear_velocity.x, target.x, delta * 30.0)
	linear_velocity.z = move_toward(linear_velocity.z, target.z, delta * 30.0)
	if mantle_timer <= 0.0:
		is_mantling = false
		mantle_cooldown = 0.6
		linear_velocity = (mantle_dir * mantle_walk_impulse) + (Vector3.DOWN * 1.5)


func _update_stamina(delta: float) -> void:
	if ragdoll_active or dead:
		return
	var anchors: int = count_anchors()
	var grounded: bool = _is_grounded()
	var drain: float = 0.0

	if not grounded and anchors > 0:
		drain = double_arm_drain if anchors >= 2 else single_arm_drain
		if is_climbing():
			drain += stretch * stretched_drain
	elif grounded and anchors > 0:
		drain = stretch * (stretched_drain * 0.45)

	if carry_kind != -1 and is_instance_valid(_carry_node):
		drain += carry_drain_base + _carry_mass() * carry_drain_per_kg

	if carried_by_peer > 0:
		drain = 0.0

	if drain > 0.0:
		current_stamina -= drain * delta
	else:
		var regen: float = stamina_regen * (1.6 if carried_by_peer > 0 else (1.2 if grounded else 1.0))
		current_stamina += regen * delta

	if current_stamina <= 0.0:
		current_stamina = 0.0
		if carry_kind != -1:
			_clear_carry_local()
			_request_drop()
			notice_requested.emit("EXHAUSTED")
		elif anchors > 0:
			_release_all_arms()
			notice_requested.emit("EXHAUSTED")

	exhausted = current_stamina < exhausted_threshold


func _track_progress() -> void:
	if global_position.y > highest_y:
		highest_y = global_position.y
		if highest_y >= checkpoint_y + checkpoint_interval:
			checkpoint_y = floorf(highest_y / checkpoint_interval) * checkpoint_interval
			checkpoint_reached.emit(checkpoint_y)
		if not summit_emitted and highest_y >= summit_y:
			summit_emitted = true
			summit_reached.emit()


func _check_fall() -> void:
	if dead or global_position.y >= FALL_LIMIT_Y:
		return
	dead = true
	control_disabled = true
	_release_all_arms()
	if ragdoll_active and ragdoll_rig != null:
		ragdoll_rig.call("deactivate")
	ragdoll_active = false
	freeze = true
	_refresh_visuals()
	died.emit("fall")


func _visual_frame() -> Dictionary:
	var origin: Vector3
	var basis: Basis
	var camera: Camera3D = _get_camera()
	if is_local and camera != null:
		origin = camera.global_position
		basis = camera.global_transform.basis
	else:
		origin = global_position + (Vector3.UP * 0.9)
		basis = global_transform.basis

	var forward: Vector3 = -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right: Vector3 = Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	if forward.is_zero_approx():
		forward = -global_transform.basis.z.normalized()
	if right.is_zero_approx():
		right = global_transform.basis.x.normalized()

	return {
		"left_shoulder": origin - (right * 0.32) + (Vector3.DOWN * 0.24),
		"right_shoulder": origin + (right * 0.32) + (Vector3.DOWN * 0.24),
		"forward": forward,
		"right": right,
		"dangle": global_position + (forward * 0.34) + (Vector3.DOWN * 0.52),
	}


func _update_arm_visuals(delta: float) -> void:
	if left_arm == null or right_arm == null:
		return

	if ragdoll_active or dead:
		left_arm.call("update_arm", Vector3.ZERO, Vector3.ZERO, false, false)
		right_arm.call("update_arm", Vector3.ZERO, Vector3.ZERO, false, false)
		return

	var frame: Dictionary = _visual_frame()
	var stride: float = sin(walk_cycle) * 0.38
	var center: Vector3 = frame["dangle"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var left_dangle: Vector3 = center - (right * 0.3) + (forward * stride)
	var right_dangle: Vector3 = center + (right * 0.3) - (forward * stride)

	var left_on: bool = left_anchor.anchored
	var left_point: Vector3 = left_anchor.point
	var left_shooting: bool = left_anchor.shooting
	var left_extend: float = left_anchor.extend
	var right_on: bool = right_anchor.anchored
	var right_point: Vector3 = right_anchor.point
	var right_shooting: bool = right_anchor.shooting
	var right_extend: float = right_anchor.extend

	if not is_local:
		left_on = _remote_left_on
		left_point = _remote_left_point
		left_shooting = false
		left_extend = 0.0
		right_on = _remote_right_on
		right_point = _remote_right_point
		right_shooting = false
		right_extend = 0.0

	if carry_kind != -1 and is_instance_valid(_carry_node):
		var carry_point: Vector3 = _carry_node.global_position
		left_on = true
		right_on = true
		left_point = carry_point
		right_point = carry_point
		left_shooting = false
		right_shooting = false
		left_extend = 0.0
		right_extend = 0.0

	_update_extension(left_anchor, delta)
	_update_extension(right_anchor, delta)

	_draw_one_arm(
		left_arm, frame["left_shoulder"], left_dangle,
		left_on, left_point, left_shooting, left_extend
	)
	_draw_one_arm(
		right_arm, frame["right_shoulder"], right_dangle,
		right_on, right_point, right_shooting, right_extend
	)


func _update_extension(anchor: ArmAnchor, delta: float) -> void:
	if not anchor.anchored or not anchor.shooting:
		return
	var total: float = global_position.distance_to(anchor.point)
	anchor.extend = minf(total, anchor.extend + arm_projectile_speed * delta)
	if anchor.extend >= total - 0.01:
		anchor.shooting = false


func _draw_one_arm(
	mesh: MeshInstance3D,
	shoulder: Vector3,
	dangle: Vector3,
	anchored: bool,
	point: Vector3,
	shooting: bool,
	extension: float
) -> void:
	var target: Vector3 = dangle
	if anchored:
		target = point
		if shooting:
			var total: float = shoulder.distance_to(point)
			var ratio: float = 0.0 if total < 0.01 else clampf(extension / total, 0.0, 1.0)
			target = shoulder.lerp(point, ratio)
	mesh.call("update_arm", shoulder, target, true, anchored)


func _force_arm_visual_send() -> void:
	if is_local:
		visual_send_timer = 0.0


func get_arm_visual_state() -> Dictionary:
	return {
		"left_point": left_anchor.point if left_anchor.anchored else global_position,
		"right_point": right_anchor.point if right_anchor.anchored else global_position,
		"left_on": left_anchor.anchored,
		"right_on": right_anchor.anchored,
	}


func _send_visual_state(delta: float) -> void:
	visual_send_timer -= delta
	if visual_send_timer > 0.0:
		return
	visual_send_timer = 0.05

	if ragdoll_active and ragdoll_rig != null and ragdoll_rig.has_method("pack_poses"):
		rpc("receive_ragdoll_poses", ragdoll_rig.call("pack_poses"))
	var state := get_arm_visual_state()
	rpc(
		"receive_arm_visual",
		state["left_point"],
		state["right_point"],
		state["left_on"],
		state["right_on"]
	)


@rpc("any_peer", "call_remote", "unreliable")
func receive_ragdoll_poses(data: PackedFloat32Array) -> void:
	if is_local:
		return
	if ragdoll_rig != null and ragdoll_rig.has_method("apply_poses"):
		ragdoll_rig.call("apply_poses", data)


@rpc("any_peer", "call_remote", "unreliable")
func receive_arm_visual(
	left_point: Vector3,
	right_point: Vector3,
	left_on: bool,
	right_on: bool
) -> void:
	if is_local:
		return
	_remote_left_point = left_point
	_remote_right_point = right_point
	_remote_left_on = left_on
	_remote_right_on = right_on
