extends Area3D
class_name ClimbHazard

## Reusable trigger volumes plus the two small moving/breaking body classes
## used by the tower generator. Everything is built from engine primitives.

enum Type { WIND, CHECKPOINT, SUMMIT, BRITTLE, ENEMY }

signal hazard_triggered(kind: int, label: String, body: Node)
signal checkpoint_reached(height: float, body: Node)
signal summit_reached(body: Node)
signal brittle_broken(body: Node)

@export var hazard_type: Type = Type.WIND
@export var label: String = "HAZARD"
@export var checkpoint_height: float = 0.0
@export var wind_force: float = 10.0
@export var gust_period: float = 5.0
@export var gust_phase: float = 0.0
@export var gust_axis: Vector3 = Vector3.RIGHT
@export var brittle_delay: float = 2.0
@export var break_target: NodePath = NodePath()

var _inside: Dictionary = {}
var _exposure: Dictionary = {}
var _fired: Dictionary = {}
var _elapsed := 0.0
var _gust_on := false
var _gust_strength := 0.0
var _broken := false
var _target_node: Node = null


func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 1
	collision_mask = 3
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if not break_target.is_empty():
		_target_node = get_node_or_null(break_target)


static func signal_arg_count(node: Object, signal_name: StringName) -> int:
	if node == null:
		return 0
	for info in node.get_signal_list():
		if String(info.get("name", "")) == String(signal_name):
			var args: Array = info.get("args", [])
			return args.size()
	return 0


func emit_climber_signal(body: Node, signal_name: StringName, args: Array) -> void:
	if not body.has_signal(signal_name):
		return
	var signal_value := body.get(signal_name) as Signal
	if signal_value == null:
		return
	var count := signal_arg_count(body, signal_name)
	if count <= 0:
		signal_value.emit()
		return
	if count == 1:
		signal_value.emit(args[0] if not args.is_empty() else null)
		return
	if count == 2:
		signal_value.emit(args[0] if args.size() > 0 else null, args[1] if args.size() > 1 else null)
		return
	signal_value.emit()


func _physics_process(delta: float) -> void:
	match hazard_type:
		Type.WIND:
			_process_wind(delta)
		Type.BRITTLE:
			_process_brittle(delta)
		_:
			pass


func _process_wind(delta: float) -> void:
	_elapsed += delta
	var cycle := fmod(_elapsed / maxf(gust_period, 0.1) + gust_phase, 1.0)
	var wave := sin(cycle * TAU)
	var active := wave > 0.25
	_gust_strength = clampf((absf(wave) - 0.25) / 0.75, 0.0, 1.0)
	var direction := gust_axis.normalized()
	if direction == Vector3.ZERO:
		direction = Vector3.RIGHT
	if active != _gust_on:
		_gust_on = active
		if active:
			var impulse := direction * wind_force * _gust_strength
			for id in _inside.keys():
				var body := _inside[id] as Node
				if not is_instance_valid(body) or not body.has_method("apply_hazard"):
					_inside.erase(id)
					continue
				body.apply_hazard(impulse, label)
				hazard_triggered.emit(Type.WIND, "WIND GUST", body)


func _process_brittle(delta: float) -> void:
	if _broken:
		return
	for id in _inside.keys():
		var body := _inside[id] as Node
		if not is_instance_valid(body):
			_inside.erase(id)
			_exposure.erase(id)
			continue
		var exposure := float(_exposure.get(id, 0.0)) + delta
		_exposure[id] = exposure
		if exposure >= brittle_delay:
			_break_hold(body)
			return


func _break_hold(body: Node) -> void:
	_broken = true
	monitoring = false
	if _target_node != null and is_instance_valid(_target_node):
		var target := _target_node as CollisionObject3D
		if target != null:
			for child in target.get_children():
				if child is CollisionShape3D:
					(child as CollisionShape3D).disabled = true
				elif child is MeshInstance3D:
					(child as MeshInstance3D).visible = false
		if _target_node is CanvasItem:
			(_target_node as CanvasItem).visible = false
		elif _target_node is Node3D:
			(_target_node as Node3D).visible = false
	if is_instance_valid(body) and body.has_method("apply_hazard"):
		body.apply_hazard(Vector3.DOWN * 3.5, "BRITTLE HOLD")
	brittle_broken.emit(body)
	hazard_triggered.emit(Type.BRITTLE, "HOLD SNAPPED", body)


func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body) or not body.has_method("apply_hazard"):
		return
	var id := body.get_instance_id()
	_inside[id] = body
	_exposure[id] = 0.0
	match hazard_type:
		Type.CHECKPOINT:
			if bool(_fired.get(id, false)):
				return
			_fired[id] = true
			var height := checkpoint_height
			var current: Variant = body.get("checkpoint_y")
			if current != null:
				body.set("checkpoint_y", maxf(float(current), height))
			emit_climber_signal(body, &"checkpoint_reached", [height])
			checkpoint_reached.emit(height, body)
			hazard_triggered.emit(Type.CHECKPOINT, "CHECKPOINT %d m" % int(height), body)
		Type.SUMMIT:
			if bool(_fired.get(id, false)):
				return
			_fired[id] = true
			var peer: Variant = body.get("peer_id")
			emit_climber_signal(body, &"summit_reached", [peer if peer != null else 0])
			summit_reached.emit(body)
			hazard_triggered.emit(Type.SUMMIT, "SUMMIT", body)
		Type.BRITTLE:
			pass
		Type.WIND:
			if _gust_on:
				var direction := gust_axis.normalized()
				if direction == Vector3.ZERO:
					direction = Vector3.RIGHT
				body.apply_hazard(direction * wind_force * maxf(_gust_strength, 0.4), label)


func _on_body_exited(body: Node) -> void:
	var id := body.get_instance_id()
	_inside.erase(id)
	_exposure.erase(id)


class BrittleHold extends StaticBody3D:
	## A small ledge that snaps roughly two seconds after a climber lodges on it.

	signal broke()

	var delay := 2.0
	var broken := false
	var _touchers: Dictionary = {}
	var _timers: Dictionary = {}
	var _shape: CollisionShape3D = null
	var _mesh: MeshInstance3D = null
	var _zone: Area3D = null

	func setup(size: Vector3, material: Material, break_delay: float = 2.0) -> void:
		delay = break_delay
		collision_layer = 1
		collision_mask = 1
		_shape = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		_shape.shape = box
		add_child(_shape)
		_mesh = MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = size
		_mesh.mesh = cube
		_mesh.material_override = material
		add_child(_mesh)
		_zone = Area3D.new()
		var zone_shape := CollisionShape3D.new()
		var zone_box := BoxShape3D.new()
		zone_box.size = size + Vector3(0.8, 1.8, 0.8)
		zone_shape.shape = zone_box
		_zone.add_child(zone_shape)
		_zone.collision_layer = 1
		_zone.collision_mask = 3
		_zone.monitoring = true
		_zone.body_entered.connect(_on_entered)
		_zone.body_exited.connect(_on_exited)
		add_child(_zone)

	func _on_entered(body: Node) -> void:
		if is_instance_valid(body) and body.has_method("apply_hazard"):
			_touchers[body.get_instance_id()] = body

	func _on_exited(body: Node) -> void:
		var id := body.get_instance_id()
		_touchers.erase(id)
		_timers.erase(id)

	func _physics_process(delta: float) -> void:
		if broken:
			return
		for id in _touchers.keys():
			var body := _touchers[id] as Node
			if not is_instance_valid(body):
				_touchers.erase(id)
				_timers.erase(id)
				continue
			var exposure := float(_timers.get(id, 0.0)) + delta
			_timers[id] = exposure
			if exposure >= delay:
				snap()
				return

	func snap() -> void:
		if broken:
			return
		broken = true
		set_physics_process(false)
		if _shape != null:
			_shape.disabled = true
		if _mesh != null:
			_mesh.visible = false
		if _zone != null:
			_zone.monitoring = false
		for id in _touchers.keys():
			var body := _touchers[id] as Node
			if is_instance_valid(body) and body.has_method("apply_hazard"):
				body.apply_hazard(Vector3.DOWN * 3.5, "BRITTLE HOLD")
		broke.emit()


class MovingPlatform extends AnimatableBody3D:
	## A physics-aware platform sliding along a fixed line on a sine cycle.

	var travel := Vector3(8.0, 0.0, 0.0)
	var period := 5.0
	var phase := 0.0
	var origin := Vector3.ZERO
	var _time := 0.0

	func setup(origin_pos: Vector3, travel_vec: Vector3, period_s: float, phase_v: float, size: Vector3, material: Material) -> void:
		sync_to_physics = true
		collision_layer = 1
		collision_mask = 1
		origin = origin_pos
		travel = travel_vec
		period = maxf(period_s, 0.75)
		phase = phase_v
		position = origin
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = size
		mesh.mesh = cube
		mesh.material_override = material
		add_child(mesh)

	func _physics_process(delta: float) -> void:
		_time += delta
		var wave := sin(TAU * (_time / period + phase))
		position = origin + travel * (wave * 0.5)
