extends Area3D
class_name ClimbEnemy

## Patrolling hazard drone. It follows a fixed local route, so every peer sees
## the same motion without a network RPC. Each climber applies its own hit,
## which keeps the authoritative physics model untouched.

signal enemy_hit(body: Node)

@export var speed: float = 2.6
@export var hit_force: float = 11.0
@export var stamina_damage: float = 16.0
@export var hit_interval: float = 1.3

const MODEL_PATH := "res://assets/models/enemy.glb"

var route: Array[Vector3] = []
var _route_index: int = 0
var _inside: Dictionary = {}
var _cooldowns: Dictionary = {}
var _visual: Node3D = null
var _rotor: MeshInstance3D = null


func _ready() -> void:
	add_to_group("climb_enemies")
	monitoring = true
	monitorable = true
	collision_layer = 4
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()


func setup(points: Array[Vector3], move_speed: float, stamina_cost: float) -> void:
	route.clear()
	for point in points:
		route.append(point)
	speed = maxf(0.2, move_speed)
	stamina_damage = maxf(0.0, stamina_cost)
	if not route.is_empty():
		global_position = route[0]
		_route_index = 1 % route.size()


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "Model"
	if ResourceLoader.exists(MODEL_PATH):
		var packed := load(MODEL_PATH) as PackedScene
		if packed != null:
			_visual.add_child(packed.instantiate())
	else:
		var body := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.85, 0.6, 0.85)
		body.mesh = cube
		_visual.add_child(body)
	add_child(_visual)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.72
	ring_mesh.outer_radius = 0.88
	ring_mesh.rings = 6
	ring_mesh.ring_segments = 20
	_rotor = MeshInstance3D.new()
	_rotor.mesh = ring_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.22, 0.18)
	material.emission_enabled = true
	material.emission = Color(0.9, 0.12, 0.08)
	material.emission_energy_multiplier = 1.8
	_rotor.material_override = material
	_visual.add_child(_rotor)

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	shape.shape = sphere
	add_child(shape)


func _physics_process(delta: float) -> void:
	if _rotor != null:
		_rotor.rotation.y += delta * 4.5
	if route.size() < 2:
		return
	var target: Vector3 = route[_route_index]
	var offset: Vector3 = target - global_position
	var distance: float = offset.length()
	if distance <= 0.15:
		_route_index = (_route_index + 1) % route.size()
		return
	global_position += offset.normalized() * minf(speed * delta, distance)
	var look: Vector3 = offset.normalized()
	if look.length_squared() > 0.001:
		_visual.rotation.y = atan2(-look.x, -look.z)
	var now := Time.get_ticks_msec()
	for id in _inside.keys():
		var body := _inside[id] as Node
		if not is_instance_valid(body) or not bool(body.get("is_local")):
			continue
		if int(_cooldowns.get(id, 0)) + int(hit_interval * 1000.0) > now:
			continue
		_cooldowns[id] = now
		var body_pos: Vector3 = body.get("global_position")
		var away: Vector3 = (body_pos - global_position).normalized()
		if away.length_squared() < 0.001:
			away = Vector3.UP
		var hit_impulse: Vector3 = away * hit_force + (Vector3.UP * hit_force * 0.35)
		if body.has_method("apply_enemy_strike"):
			body.call("apply_enemy_strike", stamina_damage, hit_impulse)
		elif body.has_method("apply_hazard"):
			body.call("apply_hazard", hit_impulse, "ENEMY HIT")
		enemy_hit.emit(body)


func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body) or not body.has_method("apply_hazard"):
		return
	_inside[body.get_instance_id()] = body


func _on_body_exited(body: Node) -> void:
	_inside.erase(body.get_instance_id())
	_cooldowns.erase(body.get_instance_id())
