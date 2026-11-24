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
signal bandages_changed(count: int)
signal injury_changed(value: float)
signal stamina_lock_changed(value: float)
signal fall_damage(amount: float, impact_speed: float)
signal unconscious_changed(value: bool)
signal revived(peer_id: int)
signal notice_requested(text: String)

const MAX_STRETCH: float = 1.4
const MIN_USABLE_STAMINA: float = 10.0
const OVERLOAD_THRESHOLD: float = 0.85
const OVERLOAD_TIME: float = 1.1
const FALL_LIMIT_Y: float = -12.0
const PROP_LAYER_MASK: int = 4
## The body capsule collider is 1.7 m tall, so its underside is at -0.85.
## A 0.16 m foot box rests just above that contact plane. Walking lifts feet
## upward only; tilting raises the centre so a toe never digs into the floor.
const FOOT_GROUND_Y: float = -0.76
const FOOT_HALF_HEIGHT: float = 0.08
const FOOT_HALF_DEPTH: float = 0.21
const FOOT_TILT_DEGREES: float = 55.0

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

@export_group("Nodes")
@export var camera_pivot: Node3D
@export var left_arm: MeshInstance3D
@export var right_arm: MeshInstance3D
@export var ragdoll_rig: Node3D
@export var body_mesh: MeshInstance3D
@export var head_mesh: MeshInstance3D
@export var jetpack_visual: Node3D

@export_group("Harpoon")
@export var harpoon_reach: float = 14.0
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
@export var fix_reach: float = 4.5
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
@export var stamina_regen: float = 24.0
@export var stretch_gain: float = 0.16
@export var stretch_recovery: float = 0.55
@export var stretched_drain: float = 12.0
@export var single_arm_drain: float = 11.0
@export var double_arm_drain: float = 6.0
@export var exhausted_threshold: float = 12.0
@export var invulnerability_time: float = 0.9

@export_group("Condition")
@export var fall_damage_min_speed: float = 10.0
@export var fall_damage_per_speed: float = 3.0
@export var fall_damage_max: float = 85.0
## The longer a drop lasts, the harder gravity pulls and the less drag applies.
@export var fall_accel_per_second: float = 14.0
@export var fall_accel_max_time: float = 2.6
@export var fall_damp_min: float = 0.14
@export var fall_speed_cap: float = 70.0
@export var fall_damage_per_second: float = 4.5
@export var long_fall_notice_time: float = 1.4
@export var injury_regen_penalty: float = 0.75
@export var hazard_damage_base: float = 7.0
@export var hazard_damage_per_impulse: float = 0.35
@export var hazard_damage_max: float = 20.0
@export var hazard_injury_scale: float = 0.008
## Enemy strikes lock this share of their stamina damage permanently.
@export var enemy_stamina_lock_scale: float = 1.0
@export var starting_bandages: int = 0
@export var bandage_heal: float = 30.0
@export var bandage_injury_relief: float = 0.6
## A badly hurt climber collapses if another fall empties the usable bar.
@export var critical_injury: float = 0.55
@export var critical_lock_ratio: float = 0.45
## Seconds a downed climber survives without being carried or bandaged.
@export var unconscious_death_time: float = 20.0
## Holding the Elastic tail rope costs stamina while it is stretched.
@export var tail_tension_drain: float = 7.0
@export var jetpack_mass_kg: float = 12.0

@export_group("Progress")
@export var checkpoint_interval: float = 20.0
@export var summit_y: float = 120.0

var left_anchor: ArmAnchor = ArmAnchor.new()
var right_anchor: ArmAnchor = ArmAnchor.new()
var character_type: int = CharacterType.STRONG
## Kept so the host can verify a thrown passenger was actually launched even
## when its frozen remote body ignores linear_velocity until the owner applies it.
var last_launch_velocity: Vector3 = Vector3.ZERO
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

var injury: float = 0.0
## Stamina lost to hard falls. It stays red in the HUD and cannot be used again
## until a bandage restores it. It is not refilled by respawning or recovering.
var stamina_lock: float = 0.0
var bandages: int = 0
## Downed but still alive: a teammate can carry this climber and spend a bandage
## to bring them back. Ragdoll is the visual state, unconscious is the game state.
var unconscious: bool = false
## In multiplayer a downed climber waits for a bandage; solo matches still recover.
var persistent_unconscious: bool = false
## Death countdown: only advances while down and not carried by a teammate.
var unconscious_time: float = 0.0
var death_progress: float = 0.0
var _death_notice_stage: int = 0
## Seconds spent falling without ground or a rope. Drives acceleration and damage.
var fall_time: float = 0.0
var normal_linear_damp: float = 1.0
var _shadow: MeshInstance3D = null
var _shadow_ray_length: float = 14.0

var _remote_position_ready: bool = false
var _remote_left_point: Vector3 = Vector3.ZERO
var _remote_right_point: Vector3 = Vector3.ZERO
var _remote_left_on: bool = false
var _remote_right_on: bool = false
var _default_physics_material: PhysicsMaterial
var _carry_node: Node = null
var _carrier_node: Node = null
var _jetpack_flame: MeshInstance3D = null
var _left_foot: MeshInstance3D = null
var _right_foot: MeshInstance3D = null
var _tail_body: RigidBody3D = null
var _prop_report_timer: float = 0.0
var _prop_pull_timer: float = 0.0
var _pending_prop_pulls: Dictionary = {}


func _ready() -> void:
	add_to_group("climbers")
	can_sleep = false
	linear_damp = 1.0
	normal_linear_damp = linear_damp
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
	_setup_shadow()
	bandages = maxi(0, starting_bandages)
	_apply_color()
	_configure_synchronizer()
	_apply_authority_mode()
	_refresh_visuals()
	stamina_changed.emit(current_stamina, max_stamina)
	stamina_lock_changed.emit(stamina_lock)
	stretch_changed.emit(stretch, stretch >= OVERLOAD_THRESHOLD)
	bandages_changed.emit(bandages)
	injury_changed.emit(injury)


func _exit_tree() -> void:
	if _shadow != null and is_instance_valid(_shadow):
		_shadow.queue_free()
	if is_local and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func configure(new_peer_id: int, new_display_name: String, new_color: Color, new_character_type: int = CharacterType.STRONG) -> void:
	peer_id = maxi(1, new_peer_id)
	display_name = new_display_name
	player_color = new_color
	character_type = new_character_type if CharacterType.is_valid(new_character_type) else CharacterType.STRONG
	_configure_synchronizer()
	_apply_color()
	_apply_character_type()
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
		"character_type": character_type,
		"position": global_position,
		"velocity": linear_velocity,
		"stamina": current_stamina,
		"max_stamina": max_stamina,
		"stamina_lock": stamina_lock,
		"usable_max_stamina": usable_max_stamina(),
		"stretch": stretch,
		"overloaded": stretch >= OVERLOAD_THRESHOLD,
		"ragdoll_active": ragdoll_active,
		"unconscious": unconscious,
		"persistent_unconscious": persistent_unconscious,
		"unconscious_time": unconscious_time,
		"death_progress": death_progress,
		"death_time_left": get_death_time_left(),
		"fall_time": fall_time,
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
		"is_local": is_local,
		"dead": dead,
		"stunned": stun_timer > 0.0,
	}


func respawn_at(pos: Vector3, _unused: bool = false) -> void:
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
	unconscious = false
	ragdoll_timer = 0.0
	_reset_unconscious_timer()
	_reset_fall_state()
	_release_arm(true)
	_release_arm(false)
	_clear_carry_local()
	carried_by_peer = 0
	_carrier_node = null
	stretch = 0.0
	stretch_overload_timer = 0.0
	# Fall damage is permanent until a bandage is used: respawning refills only
	# the still-usable part of the bar, not the red locked part.
	current_stamina = usable_max_stamina()
	injury = 0.0
	injury_changed.emit(injury)

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
	stamina_lock_changed.emit(stamina_lock)
	stretch_changed.emit(stretch, false)
	unconscious_changed.emit(false)


func apply_hazard(impulse: Vector3, label: String) -> void:
	if dead or invulnerability_timer > 0.0:
		return
	if ragdoll_active and ragdoll_rig != null and ragdoll_rig.has_method("get_parts"):
		var parts: Array = ragdoll_rig.call("get_parts")
		if not parts.is_empty():
			parts[0].apply_central_impulse(impulse * parts[0].mass * 0.5)
	elif is_local and not freeze:
		apply_central_impulse(impulse * mass)

	# There is no health pool: every hit is paid for directly with stamina.
	# The short cooldown stops wind zones from draining it every physics frame.
	var loss := clampf(
		hazard_damage_base + impulse.length() * hazard_damage_per_impulse,
		0.0,
		hazard_damage_max
	)
	current_stamina = maxf(0.0, current_stamina - loss)
	injury = clampf(injury + loss * hazard_injury_scale, 0.0, 1.0)
	stun_timer = 0.4
	invulnerability_timer = maxf(invulnerability_timer, 0.45)
	stamina_changed.emit(current_stamina, max_stamina)
	injury_changed.emit(injury)
	notice_requested.emit("%s -%d STAMINA" % [label, int(loss)])


## Enemy contact is worse than a gust: the stolen stamina is locked red until
## a bandage is spent. It never comes back through standing still.
func apply_enemy_strike(amount: float, impulse: Vector3) -> void:
	if dead or invulnerability_timer > 0.0:
		return
	if ragdoll_active and ragdoll_rig != null and ragdoll_rig.has_method("get_parts"):
		var parts: Array = ragdoll_rig.call("get_parts")
		if not parts.is_empty():
			parts[0].apply_central_impulse(impulse * parts[0].mass * 0.5)
	elif is_local and not freeze:
		apply_central_impulse(impulse * mass)
	var loss := clampf(maxf(0.0, amount) * enemy_stamina_lock_scale, 0.0, fall_damage_max)
	if loss <= 0.0:
		return
	current_stamina = maxf(0.0, current_stamina - loss)
	set_stamina_lock(stamina_lock + loss)
	injury = clampf(injury + loss * hazard_injury_scale * 2.0, 0.0, 1.0)
	stun_timer = 0.4
	invulnerability_timer = maxf(invulnerability_timer, 0.8)
	stamina_changed.emit(current_stamina, max_stamina)
	injury_changed.emit(injury)
	notice_requested.emit("ENEMY HIT -%d STAMINA LOCKED" % int(loss))


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
	unconscious = true
	_reset_fall_state()
	freeze = true
	if ragdoll_rig != null:
		ragdoll_rig.call("activate", body_xform, body_velocity, kick, player_color)
	_refresh_visuals()
	ragdoll_timer = ragdoll_duration
	_reset_unconscious_timer()
	stretch_overload_timer = 0.0
	unconscious_changed.emit(true)
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
	unconscious = false
	control_disabled = false
	ragdoll_timer = 0.0
	_reset_unconscious_timer()
	_reset_fall_state()
	stretch = 0.0
	stretch_overload_timer = 0.0
	_release_arm(true)
	_release_arm(false)
	current_stamina = maxf(current_stamina, usable_max_stamina() * 0.35)
	_apply_freeze()
	global_transform = Transform3D(Basis.IDENTITY, upright_position)
	replicated_position = upright_position
	_remote_position_ready = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	invulnerability_timer = invulnerability_time
	_refresh_visuals()
	ragdoll_ended.emit()
	unconscious_changed.emit(false)
	notice_requested.emit("RECOVERED")


## The usable ceiling is the full bar minus the permanently damaged red part.
func usable_max_stamina() -> float:
	return maxf(MIN_USABLE_STAMINA, max_stamina - maxf(0.0, stamina_lock))


func set_stamina_lock(value: float) -> void:
	var bounded: float = clampf(value, 0.0, maxf(0.0, max_stamina - MIN_USABLE_STAMINA))
	if is_equal_approx(bounded, stamina_lock):
		return
	stamina_lock = bounded
	current_stamina = minf(current_stamina, usable_max_stamina())
	stamina_lock_changed.emit(stamina_lock)
	stamina_changed.emit(current_stamina, max_stamina)


func set_current_stamina(value: float) -> void:
	var bounded: float = clampf(value, 0.0, usable_max_stamina())
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
	if _left_foot == null:
		_left_foot = get_node_or_null("LeftFoot") as MeshInstance3D
	if _right_foot == null:
		_right_foot = get_node_or_null("RightFoot") as MeshInstance3D
	if _tail_body == null:
		_tail_body = find_child("Tail", true, false) as RigidBody3D


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
		"character_type",
		"highest_y",
		"checkpoint_y",
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
	if _left_foot != null:
		_left_foot.material_override = _make_material(player_color.darkened(0.25), 0.4)
	if _right_foot != null:
		_right_foot.material_override = _make_material(player_color.darkened(0.25), 0.4)
	if _tail_body != null and _tail_body.has_method("setup"):
		_tail_body.call("setup", peer_id, player_color, is_elastic())
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
	if _left_foot != null:
		_left_foot.visible = not hidden
	if _right_foot != null:
		_right_foot.visible = not hidden
	if _tail_body != null:
		_tail_body.visible = not hidden and is_elastic()
	if jetpack_visual != null:
		jetpack_visual.visible = not hidden and has_jetpack
	if _jetpack_flame != null:
		_jetpack_flame.visible = false


func _setup_shadow() -> void:
	for arm in [left_arm, right_arm]:
		if arm != null:
			arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(1.25, 0.82)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 0.0, 0.0, 0.32)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow = MeshInstance3D.new()
	_shadow.name = "GroundShadow"
	_shadow.mesh = shadow_mesh
	_shadow.material_override = material
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.rotation_degrees.x = -90.0
	_shadow.top_level = true
	_shadow.visible = false
	# Adding the shadow to this climber (with top_level enabled) avoids touching
	# the scene root while it is busy setting up children during _ready().
	add_child(_shadow)


func _update_shadow() -> void:
	# The shadow lives on the scene root and is freed on _exit_tree. During a
	# scene change _physics_process can still run after that, so never touch a
	# node that is no longer in the tree (Godot logs a Transform3D error).
	if not is_inside_tree() or not is_node_ready():
		return
	if _shadow == null or not is_instance_valid(_shadow) or not _shadow.is_inside_tree():
		return
	if ragdoll_active or dead:
		_shadow.visible = false
		return
	var world := get_world_3d()
	if world == null:
		_shadow.visible = false
		return
	var from: Vector3 = global_position + (Vector3.UP * 0.1)
	var query := PhysicsRayQueryParameters3D.create(from, from - (Vector3.UP * _shadow_ray_length), climbable_mask, [])
	query.exclude = _ray_exclusions()
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_shadow.visible = false
		return
	var height: float = maxf(0.0, from.y - float(hit.position.y))
	var fade: float = clampf(1.0 - height / _shadow_ray_length, 0.0, 1.0)
	var scale: float = lerpf(1.9, 0.85, fade)
	if not _shadow.is_inside_tree():
		return
	_shadow.visible = fade > 0.02
	_shadow.global_position = (hit.position as Vector3) + (Vector3.UP * 0.035)
	_shadow.scale = Vector3(scale, scale, scale)
	var mat := _shadow.material_override as StandardMaterial3D
	if mat != null:
		var c := mat.albedo_color
		c.a = 0.34 * fade
		mat.albedo_color = c


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


func _find_tail(peer: int) -> Node:
	if peer <= 0:
		return null
	for node in get_tree().get_nodes_in_group("climb_tails"):
		if int(node.get("owner_peer_id")) == peer:
			return node
	return null


func get_carry_hold_point() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z.normalized()
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var lift: float = 0.25
	var reach: float = 0.95
	if carry_kind == 0 and is_instance_valid(_carry_node) and int(_carry_node.get("kind")) == ClimbProp.Kind.BUCKET:
		lift = -0.18
		reach = 1.28
	return global_position + forward.normalized() * reach + (Vector3.UP * lift)


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
	elif kind_value == 2:
		_carry_node = _find_tail(int(target_id_value))
	# The bucket needs both hands, so it frees any live anchors on pickup.
	if _hands_full_with_bucket():
		_release_all_arms()
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
	var was_carried := carried_by_peer > 0
	carried_by_peer = maxi(0, peer)
	_carrier_node = null
	if carried_by_peer > 0:
		_carrier_node = _find_climber(carried_by_peer)
		_release_all_arms()
		if unconscious:
			# Keep them down until a bandage is spent on them. Fold the ragdoll
			# rig away so the hold point drives one body instead of loose parts.
			if ragdoll_active and ragdoll_rig != null:
				ragdoll_rig.call("deactivate")
			ragdoll_active = false
			control_disabled = true
			_reset_fall_state()
			_apply_freeze()
		elif ragdoll_active:
			recover()
	elif was_carried and unconscious:
		# Dropped while still down: collapse again where the carrier left them.
		ragdoll_active = true
		control_disabled = true
		ragdoll_timer = ragdoll_duration
		if ragdoll_rig != null:
			ragdoll_rig.call("activate_remote", global_transform)
		freeze = true
	stretch_overload_timer = 0.0
	_refresh_visuals()
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


func remove_jetpack() -> void:
	if not has_jetpack:
		return
	has_jetpack = false
	jetpack_fuel = 0.0
	if _jetpack_flame != null:
		_jetpack_flame.visible = false
	jetpack_changed.emit(false, 0.0)
	_refresh_visuals()
	notice_requested.emit("JETPACK REMOVED")


func add_bandage(amount: int = 1) -> void:
	bandages = clampi(bandages + maxi(0, amount), 0, 9)
	bandages_changed.emit(bandages)
	notice_requested.emit("BANDAGE PICKED UP")


func set_persistent_unconscious(value: bool) -> void:
	persistent_unconscious = value


## Prefers a carried downed teammate, then the closest unconscious one nearby.
func find_bandage_target() -> Node:
	if dead or ragdoll_active or carried_by_peer > 0 or bandages <= 0:
		return null
	if carry_kind == 1 and is_instance_valid(_carry_node) and bool(_carry_node.get("unconscious")):
		return _carry_node
	var best: Node = null
	var best_distance := carry_reach + 1.0
	for climber in get_tree().get_nodes_in_group("climbers"):
		if int(climber.get("peer_id")) == peer_id or bool(climber.get("dead")):
			continue
		if not bool(climber.get("unconscious")):
			continue
		var carried := int(climber.get("carried_by_peer"))
		if carried != 0 and carried != peer_id:
			continue
		var distance := global_position.distance_to(climber.global_position)
		if distance < best_distance:
			best = climber
			best_distance = distance
	return best


func use_bandage_on_target(target_pid: int) -> void:
	if dead or ragdoll_active or carried_by_peer > 0 or bandages <= 0:
		return
	var target := _find_climber(target_pid)
	if target == null or int(target.get("peer_id")) == peer_id or bool(target.get("dead")):
		return
	if not bool(target.get("unconscious")):
		return
	bandages -= 1
	bandages_changed.emit(bandages)
	notice_requested.emit("BANDAGE APPLIED")
	var manager := _game_manager()
	if manager != null and manager.has_method("request_bandage_revive"):
		manager.call("request_bandage_revive", target_pid)


func revive_with_bandage(helper_pid: int) -> void:
	if dead or not unconscious:
		return
	if carried_by_peer > 0:
		set_carried_by(0)
	if ragdoll_rig != null:
		ragdoll_rig.call("deactivate")
	var upright_position: Vector3 = global_position + (Vector3.UP * 0.2)
	ragdoll_active = false
	unconscious = false
	control_disabled = false
	ragdoll_timer = 0.0
	_reset_unconscious_timer()
	_reset_fall_state()
	stretch = 0.0
	stretch_overload_timer = 0.0
	_release_arm(true)
	_release_arm(false)
	set_stamina_lock(stamina_lock - bandage_heal)
	injury = maxf(0.0, injury - bandage_injury_relief)
	current_stamina = minf(usable_max_stamina(), maxf(current_stamina, usable_max_stamina() * 0.55))
	_apply_freeze()
	global_transform = Transform3D(Basis.IDENTITY, upright_position)
	replicated_position = upright_position
	_remote_position_ready = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	invulnerability_timer = maxf(invulnerability_timer, invulnerability_time)
	_refresh_visuals()
	ragdoll_ended.emit()
	unconscious_changed.emit(false)
	revived.emit(helper_pid)
	stamina_changed.emit(current_stamina, max_stamina)
	injury_changed.emit(injury)
	var notice := "SELF REVIVED" if helper_pid == peer_id else "REVIVED BY TEAMMATE"
	notice_requested.emit(notice)


func use_bandage() -> void:
	if dead or bandages <= 0:
		return
	if ragdoll_active and not unconscious:
		return
	if carried_by_peer > 0:
		return
	bandages -= 1
	bandages_changed.emit(bandages)
	if unconscious:
		revive_with_bandage(peer_id)
		return
	# A bandage is the only way to win back the red, locked part of the bar.
	set_stamina_lock(stamina_lock - bandage_heal)
	injury = maxf(0.0, injury - bandage_injury_relief)
	current_stamina = minf(usable_max_stamina(), current_stamina + bandage_heal)
	bandages_changed.emit(bandages)
	injury_changed.emit(injury)
	stamina_changed.emit(current_stamina, max_stamina)
	notice_requested.emit("BANDAGE USED")


func apply_fall_impact(impact_speed: float, fall_duration: float = 0.0) -> void:
	var speed := maxf(0.0, impact_speed)
	var duration := maxf(0.0, fall_duration)
	# Long drops hurt twice: gravity made the impact faster, and the air time
	# itself lowers the safe speed threshold. A short fall stays as forgiving as
	# before because duration is zero when this API is called directly.
	var effective_speed := speed + duration * fall_damage_per_second
	var safe_speed := maxf(4.0, fall_damage_min_speed - duration * 1.5)
	if effective_speed < safe_speed:
		return
	var loss := clampf((effective_speed - safe_speed) * fall_damage_per_speed, 0.0, fall_damage_max)
	if loss <= 0.0:
		return
	current_stamina = maxf(0.0, current_stamina - loss)
	# Hard landings do not heal back: the lost stamina becomes a permanent red
	# slice of the bar until a bandage recovers it.
	set_stamina_lock(stamina_lock + loss)
	var injury_gain := loss / maxf(1.0, fall_damage_max) * (1.0 + minf(duration, 4.0) * 0.18)
	injury = clampf(injury + injury_gain, 0.0, 1.0)
	stun_timer = maxf(stun_timer, clampf(loss / 45.0 + duration * 0.06, 0.1, 0.9))
	invulnerability_timer = maxf(invulnerability_timer, 0.35)
	stamina_changed.emit(current_stamina, max_stamina)
	injury_changed.emit(injury)
	fall_damage.emit(loss, speed)
	notice_requested.emit("FALL DAMAGE -%d STAMINA LOCKED" % int(loss))
	if duration >= long_fall_notice_time:
		notice_requested.emit("LONG FALL %.1fs -%d LOCKED" % [duration, int(loss)])
	if current_stamina <= 0.0:
		_collapse_from_fall()


func _reset_unconscious_timer() -> void:
	unconscious_time = 0.0
	death_progress = 0.0
	_death_notice_stage = 0


func get_death_time_left() -> float:
	if not unconscious or dead:
		return 0.0
	return maxf(0.0, unconscious_death_time - unconscious_time)


func is_critically_damaged() -> bool:
	return injury >= critical_injury or stamina_lock >= float(max_stamina) * critical_lock_ratio


## A hard landing that empties the bar on an already badly hurt climber knocks
## them out. They stay down until somebody spends a bandage, even after rescue.
func _collapse_from_fall() -> void:
	if dead or ragdoll_active or carried_by_peer > 0 or not is_critically_damaged():
		return
	persistent_unconscious = true
	start_ragdoll()
	notice_requested.emit("COLLAPSED - NEEDS A BANDAGE")


func _die_from_unconscious() -> void:
	if dead:
		return
	dead = true
	control_disabled = true
	_release_all_arms()
	if ragdoll_active and ragdoll_rig != null:
		ragdoll_rig.call("deactivate")
	ragdoll_active = false
	freeze = true
	_reset_unconscious_timer()
	_refresh_visuals()
	died.emit("unconscious")


func _reset_fall_state() -> void:
	fall_time = 0.0
	gravity_scale = 1.0
	linear_damp = normal_linear_damp


func _update_fall_dynamics(delta: float, grounded: bool) -> void:
	var falling: bool = not grounded and not is_climbing() and linear_velocity.y < -0.5
	if not falling:
		if fall_time <= 0.0:
			return
		_reset_fall_state()
		return
	fall_time += delta
	var ramp := clampf(fall_time / maxf(0.01, fall_accel_max_time), 0.0, 1.0)
	gravity_scale = 1.0 + fall_accel_per_second * minf(fall_time, fall_accel_max_time) / 9.81
	linear_damp = lerpf(normal_linear_damp, fall_damp_min, ramp)
	if linear_velocity.y < -fall_speed_cap:
		linear_velocity.y = -fall_speed_cap


func get_total_weight() -> float:
	var total := 0.0
	if carry_kind == 0 and is_instance_valid(_carry_node):
		total += maxf(1.0, float(_carry_node.get("mass_kg")))
	elif carry_kind == 1 and is_instance_valid(_carry_node):
		total += maxf(1.0, float(_carry_node.get("mass")))
	if has_jetpack:
		total += jetpack_mass_kg
	return total


func _request_carry() -> void:
	if ragdoll_active or dead or control_disabled:
		return
	# A Strong holding an awake Elastic uses Q to throw; F still drops safely.
	if carried_by_peer > 0:
		# A passenger can release themselves by pressing F again.
		_request_drop()
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
		# Check climbers before tails: a Strong standing next to an Elastic
		# must grab the teammate for the high throw, not the nearby rope tail.
		for query_mask in [2, 4]:
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
			if collider.is_in_group("climb_tails") or collider.has_method("get_tail_owner_id"):
				kind = 2
				target_id = str(int(collider.get("owner_peer_id")))
				best_distance = distance
			elif collider.has_method("set_carrier") and not collider.has_method("get_state"):
				kind = 0
				target_id = str(collider.get("prop_id"))
				best_distance = distance
			elif collider.has_method("get_state") and can_carry_climber(collider):
				kind = 1
				target_id = str(int(collider.get("peer_id")))
				best_distance = distance

	# Fallback: an eligible climber wins over a tail so the signature throw is
	# always reachable with F. The tail stays available when nobody is liftable.
	if kind == -1:
		for climber in get_tree().get_nodes_in_group("climbers"):
			if int(climber.get("carried_by_peer")) > 0 or not can_carry_climber(climber):
				continue
			var distance := global_position.distance_to(climber.global_position)
			if distance < carry_reach and distance < best_distance:
				kind = 1
				target_id = str(int(climber.get("peer_id")))
				best_distance = distance
	if kind == -1:
		for tail in get_tree().get_nodes_in_group("climb_tails"):
			var owner_id := int(tail.get("owner_peer_id"))
			if owner_id == peer_id or int(tail.get("carrier_id")) != 0:
				continue
			if tail.has_method("can_be_grappled") and not bool(tail.call("can_be_grappled")):
				continue
			var tail_distance := global_position.distance_to(tail.global_position)
			if tail_distance < carry_reach and tail_distance < best_distance:
				kind = 2
				target_id = str(owner_id)
				best_distance = tail_distance
	if kind == -1:
		for prop in get_tree().get_nodes_in_group("climb_props"):
			if int(prop.get("carrier_id")) > 0:
				continue
			var distance := global_position.distance_to(prop.global_position)
			if distance < 2.6 and distance < best_distance:
				kind = 0
				target_id = str(prop.get("prop_id"))
				best_distance = distance

	if kind == -1:
		notice_requested.emit("NOTHING TO GRAB")
		return
	var manager := _game_manager()
	if manager != null and manager.has_method("request_carry"):
		manager.call("request_carry", kind, target_id)


## Finds the nearest fixable nearby object. Props held by a teammate and props
## that are already anchored get priority so coop building feels responsive.
func find_fix_target() -> Node:
	var best: Node = null
	var best_score := INF
	for prop in get_tree().get_nodes_in_group("climb_props"):
		if int(prop.get("kind")) == ClimbProp.Kind.BUCKET:
			continue
		var distance := global_position.distance_to(prop.global_position)
		if distance > fix_reach:
			continue
		var score := distance
		var carrier := int(prop.get("carrier_id"))
		if carrier > 0 and carrier != peer_id:
			score *= 0.25
		elif bool(prop.get("is_fixed")):
			score *= 0.4
		if score < best_score:
			best = prop
			best_score = score
	return best


func _request_fix_prop() -> void:
	var prop := find_fix_target()
	if prop == null:
		notice_requested.emit("NOTHING TO FIX NEARBY")
		return
	var manager := _game_manager()
	if manager != null and manager.has_method("request_fix_prop"):
		manager.call("request_fix_prop", str(prop.get("prop_id")))


func _request_drop() -> void:
	var manager := _game_manager()
	if manager != null and manager.has_method("request_drop"):
		manager.call("request_drop")


func _request_throw_elastic() -> void:
	var manager := _game_manager()
	if manager == null:
		return
	if carry_kind == 1 and is_instance_valid(_carry_node):
		var held := _carry_node
		if not bool(held.get("unconscious")) and int(held.get("character_type")) == CharacterType.ELASTIC:
			manager.call("request_throw_elastic", peer_id)
			return
	# Quick throw: Q beside an awake Elastic grabs and launches them in one move.
	var best_id := ""
	var best_distance := carry_reach
	for candidate in get_tree().get_nodes_in_group("climbers"):
		if not can_carry_climber(candidate) or int(candidate.get("character_type")) != CharacterType.ELASTIC:
			continue
		if bool(candidate.get("unconscious")):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best_id = str(int(candidate.get("peer_id")))
	if best_id.is_empty():
		notice_requested.emit("NO ELASTIC IN REACH")
		return
	if manager.has_method("request_quick_throw"):
		manager.call("request_quick_throw", peer_id, best_id)


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
	elif carry_kind == 2:
		var tail := _carry_node
		var forward: Vector3 = -global_transform.basis.z.normalized()
		forward.y = 0.0
		if forward.length_squared() < 0.001:
			forward = Vector3.FORWARD
		var target := Transform3D(Basis.looking_at(forward.normalized(), Vector3.UP), get_carry_hold_point())
		tail.global_transform = tail.global_transform.interpolate_with(target, clampf(delta * 12.0, 0.0, 1.0))
		tail.linear_velocity = linear_velocity
		apply_central_force(Vector3.DOWN * 1.5 * 9.8 * carry_weight_factor)


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
		if carry_kind == 2:
			_process_active_carry(delta)
		_update_arm_visuals(delta)
		_update_foot_visuals(delta)
		_update_shadow()
		return

	invulnerability_timer = maxf(0.0, invulnerability_timer - delta)
	stun_timer = maxf(0.0, stun_timer - delta)
	mantle_cooldown = maxf(0.0, mantle_cooldown - delta)

	_track_progress()

	if Input.is_action_just_pressed("carry") and not ragdoll_active:
		_request_carry()
	if Input.is_action_just_pressed("fix_prop") and not ragdoll_active and carried_by_peer <= 0:
		_request_fix_prop()
	if Input.is_action_just_pressed("bandage"):
		var revive_target := find_bandage_target()
		if revive_target != null:
			use_bandage_on_target(int(revive_target.get("peer_id")))
		else:
			use_bandage()
	if Input.is_action_just_pressed("drop_jetpack"):
		remove_jetpack()

	if is_elastic() and not (is_strong() and carry_kind == 1):
		_update_tail_tension(delta)
	elif is_instance_valid(_tail_body) and _tail_body.has_method("set_tension"):
		_tail_body.call("set_tension", false, Vector3.FORWARD, 0.0)
	if Input.is_action_just_pressed("tail_stretch") and is_strong():
		_request_throw_elastic()

	if carried_by_peer > 0:
		_process_carried(delta)
	elif ragdoll_active:
		_process_ragdoll(delta)
	elif control_disabled:
		pass
	else:
		_process_climb(delta)

	_update_stamina(delta)
	_update_arm_visuals(delta)
	_update_foot_visuals(delta)
	_update_shadow()
	_send_visual_state(delta)
	_flush_prop_pulls(delta)
	_check_fall()


func _process_ragdoll(delta: float) -> void:
	if ragdoll_rig != null and ragdoll_rig.has_method("get_hips_position"):
		global_position = ragdoll_rig.call("get_hips_position")
		linear_velocity = ragdoll_rig.call("get_hips_velocity")
	ragdoll_timer -= delta
	if ragdoll_timer <= 0.0:
		if persistent_unconscious and unconscious:
			ragdoll_timer = 0.5
		else:
			recover()
	if not unconscious or dead or carried_by_peer > 0:
		return
	# The longer a teammate stays down, the closer they get to death. Being
	# carried pauses this clock, but only a bandage actually saves them.
	unconscious_time += delta
	death_progress = clampf(unconscious_time / maxf(0.1, unconscious_death_time), 0.0, 1.0)
	if death_progress >= 1.0:
		_die_from_unconscious()
		return
	var stage := 0
	if death_progress >= 0.75:
		stage = 3
	elif death_progress >= 0.5:
		stage = 2
	elif death_progress >= 0.25:
		stage = 1
	if stage > _death_notice_stage:
		_death_notice_stage = stage
		notice_requested.emit("DYING - BANDAGE NOW (%ds)" % int(get_death_time_left()))


func _process_climb(delta: float) -> void:
	var grounded: bool = _is_grounded()
	var impact_speed: float = maxf(0.0, -linear_velocity.y)
	if grounded and not was_grounded and impact_speed > 1.5:
		landed.emit()
		var fall_duration := fall_time
		_reset_fall_state()
		if impact_speed >= fall_damage_min_speed or fall_duration >= long_fall_notice_time:
			apply_fall_impact(impact_speed, fall_duration)
	was_grounded = grounded
	_update_fall_dynamics(delta, grounded)

	if is_mantling:
		_process_mantle(delta)
		return

	var climbing_allowed: bool = can_climb()
	if not climbing_allowed:
		_release_all_arms()
	if stun_timer <= 0.0:
		_apply_upright_balance()
		if climbing_allowed:
			_handle_arm_input()
			_handle_wheel_input()
		_process_active_carry(delta)
		_update_jetpack(delta)
		_update_stretch(delta)
		if ragdoll_active:
			return
		if climbing_allowed:
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


## Only the Strong can grapple and winch. The Elastic creates the rope but
## relies on being carried and thrown to gain altitude.
func can_climb() -> bool:
	return is_strong()


func is_climbing() -> bool:
	if not can_climb():
		return false
	return (left_anchor.anchored and not left_anchor.is_flat) or (right_anchor.anchored and not right_anchor.is_flat)


func _get_camera() -> Camera3D:
	if camera_pivot == null:
		return null
	return camera_pivot.get_node_or_null("Camera3D") as Camera3D


func _ray_exclusions() -> Array[RID]:
	var excluded: Array[RID] = [get_rid()]
	# A climber must not grapple their own tail, but teammates still can.
	if is_instance_valid(_tail_body):
		excluded.append(_tail_body.get_rid())
	if ragdoll_rig != null and ragdoll_rig.has_method("get_parts"):
		var parts: Array = ragdoll_rig.call("get_parts")
		for part in parts:
			excluded.append(part.get_rid())
	return excluded


func _hands_full_with_bucket() -> bool:
	return carry_kind == 0 and is_instance_valid(_carry_node) and int(_carry_node.get("kind")) == ClimbProp.Kind.BUCKET


func is_strong() -> bool:
	return character_type == CharacterType.STRONG


func is_elastic() -> bool:
	return character_type == CharacterType.ELASTIC


func can_carry_climber(target: Node) -> bool:
	if target == null or self == target or int(target.get("peer_id")) == peer_id or bool(target.get("dead")):
		return false
	if int(target.get("carried_by_peer")) > 0:
		return false
	if bool(target.get("unconscious")):
		return true
	return is_strong() and int(target.get("character_type")) == CharacterType.ELASTIC


func set_character_type(value: int) -> void:
	if not CharacterType.is_valid(value) or character_type == value:
		return
	character_type = value
	if value == CharacterType.ELASTIC and is_node_ready():
		_release_all_arms()
	_apply_color()
	_apply_character_type()
	_refresh_visuals()


func _apply_character_type() -> void:
	if body_mesh == null:
		return
	# Visual silhouette only: collision and mass stay identical for fairness.
	body_mesh.scale = Vector3(1.18, 1.0, 1.18) if is_strong() else Vector3(0.92, 1.05, 0.92)
	if _tail_body != null and _tail_body.has_method("setup"):
		_tail_body.call("setup", peer_id, player_color, is_elastic())


## The host applies this after releasing a Strong carrier's Elastic passenger.
func launch_from_carry(velocity: Vector3) -> void:
	if dead:
		return
	if ragdoll_active and not persistent_unconscious:
		recover()
	control_disabled = false
	last_launch_velocity = velocity
	linear_velocity = velocity
	_reset_fall_state()


## The host owns carry links but not the passenger body. The owner peer is the
## one that actually simulates the climb, so the launch must be sent to it.
@rpc("any_peer", "call_remote", "reliable")
func rpc_carry_launch(velocity: Vector3) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	launch_from_carry(velocity)


func _update_tail_tension(delta: float) -> void:
	if _tail_body == null or not _tail_body.has_method("set_tension"):
		return
	var usable: bool = (
		is_elastic()
		and not ragdoll_active
		and not dead
		and carried_by_peer <= 0
		and carry_kind != 2
		and not _hands_full_with_bucket()
		and current_stamina > 1.0
		and Input.is_action_pressed("tail_stretch")
	)
	if not usable:
		_tail_body.call("set_tension", false, Vector3.FORWARD, 0.0)
		return
	var camera: Camera3D = _get_camera()
	if camera == null:
		return
	var direction: Vector3 = -camera.global_transform.basis.z.normalized()
	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z.normalized()
	var max_length: float = float(_tail_body.get("max_tension_length"))
	set_current_stamina(current_stamina - tail_tension_drain * delta)
	_tail_body.call("set_tension", true, direction, max_length)


func _handle_arm_input() -> void:
	if _hands_full_with_bucket():
		_release_all_arms()
		return
	if Input.is_action_just_pressed("arm_left"):
		_fire_arm(true)
	elif Input.is_action_just_released("arm_left"):
		_release_arm(true)
	if Input.is_action_just_pressed("arm_right"):
		_fire_arm(false)
	elif Input.is_action_just_released("arm_right"):
		_release_arm(false)


func _fire_arm(left: bool) -> void:
	if not can_climb():
		notice_requested.emit("ELASTIC CANNOT CLIMB - ASK STRONG TO THROW YOU")
		return
	if ragdoll_active or carried_by_peer > 0 or stun_timer > 0.0:
		return
	if _hands_full_with_bucket():
		_release_all_arms()
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


## Called by a tail owner when its rope goes slack. A grapple on that rope is
## dropped immediately; otherwise the tail snaps back to its owner and yanks a
## teammate through whatever wall the rope was wrapped around.
func release_tail_anchor(owner_pid: int) -> void:
	for side in [true, false]:
		var arm: ArmAnchor = left_anchor if side else right_anchor
		if not arm.anchored or arm.body == null:
			continue
		if not arm.body.has_method("get_tail_owner_id"):
			continue
		if int(arm.body.call("get_tail_owner_id")) != owner_pid:
			continue
		_release_arm(side)
		if is_local:
			notice_requested.emit("ROPE SLACK")


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
	var weight: float = get_total_weight()
	var speed_scale: float = 1.0 / (1.0 + weight * 0.0022)
	if carry_kind != -1:
		speed_scale = minf(speed_scale, 0.78)
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
		# Feet work independently of hands: a carrier or a climber with two
		# anchors can still walk and jump on solid ground.
		var can_walk: bool = stun_timer <= 0.0
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
	if grounded:
		var jump_scale: float = 1.0
		var weight_scale: float = 1.0 / (1.0 + get_total_weight() * 0.004)
		linear_velocity.y = maxf(linear_velocity.y, 0.0)
		apply_central_impulse(Vector3.UP * ground_jump_velocity * mass * jump_scale * weight_scale)


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
	elif grounded:
		# Stamina never recovers in mid-air. Only solid ground refills the bar;
		# anchors and ropes keep draining it while hanging or climbing.
		var regen: float = stamina_regen * (1.6 if carried_by_peer > 0 else 1.2)
		regen *= 1.0 - clampf(injury, 0.0, 1.0) * injury_regen_penalty
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
	var fall_duration := fall_time
	_reset_fall_state()
	apply_fall_impact(maxf(18.0, absf(linear_velocity.y)), fall_duration)
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


func _update_foot_visuals(delta: float) -> void:
	if _left_foot == null or _right_foot == null:
		return
	if not is_local:
		walk_cycle += delta * 10.0 * clampf(Vector3(linear_velocity.x, 0.0, linear_velocity.z).length() / 6.0, 0.0, 1.5)
	var stride: float = sin(walk_cycle) * 0.18
	var left_lift: float = maxf(0.0, cos(walk_cycle)) * 0.12
	var right_lift: float = maxf(0.0, -cos(walk_cycle)) * 0.12
	var tilt: float = deg_to_rad(absf(stride) * FOOT_TILT_DEGREES)
	var tilt_clearance: float = maxf(
		0.0,
		FOOT_HALF_DEPTH * sin(tilt) + FOOT_HALF_HEIGHT * cos(tilt) - FOOT_HALF_HEIGHT
	)
	var contact_y: float = FOOT_GROUND_Y + tilt_clearance
	_left_foot.position = Vector3(-0.18, contact_y + left_lift, stride)
	_right_foot.position = Vector3(0.18, contact_y + right_lift, -stride)
	_left_foot.rotation_degrees.x = -stride * FOOT_TILT_DEGREES
	_right_foot.rotation_degrees.x = stride * FOOT_TILT_DEGREES


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
		var bucket: bool = carry_kind == 0 and int(_carry_node.get("kind")) == ClimbProp.Kind.BUCKET
		var teammate: bool = carry_kind == 1
		var two_handed: bool = bucket or teammate
		var hand_spread: float = 0.62 if bucket else (0.34 if teammate else 0.16)
		var hand_lift: float = 0.52 if bucket else (0.2 if teammate else 0.0)
		left_on = true
		right_on = true
		left_point = carry_point - (right * hand_spread) + (Vector3.UP * hand_lift)
		right_point = carry_point + (right * hand_spread) + (Vector3.UP * hand_lift)
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
