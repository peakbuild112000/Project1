extends MeshInstance3D
class_name ArmMesh

@export var radial_segments: int = 8
@export var curve_segments: int = 12
@export var base_radius: float = 0.06
@export var max_sag: float = 0.45
@export var spark_duration: float = 0.28
@export var hand_marker: MeshInstance3D

var _tube_mesh: ImmediateMesh
var _tube_material: StandardMaterial3D
var _hand_material: StandardMaterial3D
var _spark: MeshInstance3D
var _spark_material: StandardMaterial3D
var _spark_life: float = 0.0


func _ready() -> void:
	_tube_mesh = ImmediateMesh.new()
	mesh = _tube_mesh

	_tube_material = StandardMaterial3D.new()
	_tube_material.albedo_color = Color(0.95, 0.95, 0.95)
	_tube_material.roughness = 0.38
	_tube_material.metallic = 0.05
	_tube_material.emission_enabled = true
	_tube_material.emission = Color(0.2, 0.25, 0.3)
	material_override = _tube_material

	if hand_marker == null:
		hand_marker = get_node_or_null("HandMarker") as MeshInstance3D

	_hand_material = StandardMaterial3D.new()
	_hand_material.albedo_color = Color(1.0, 1.0, 1.0)
	_hand_material.roughness = 0.2
	_hand_material.emission_enabled = true
	_hand_material.emission = Color(1.0, 1.0, 1.0)
	_hand_material.emission_energy_multiplier = 1.8
	if hand_marker != null:
		hand_marker.material_override = _hand_material
		hand_marker.visible = false

	_spark_material = StandardMaterial3D.new()
	_spark_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.emission_enabled = true
	_spark_material.emission = Color(1.0, 1.0, 1.0)
	_spark_material.emission_energy_multiplier = 2.5
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.17
	spark_mesh.height = 0.34
	_spark = MeshInstance3D.new()
	_spark.name = "AnchorSpark"
	_spark.mesh = spark_mesh
	_spark.material_override = _spark_material
	_spark.top_level = true
	_spark.visible = false
	add_child(_spark)


func set_color(color: Color) -> void:
	if _tube_material != null:
		_tube_material.albedo_color = color
		_tube_material.emission = color.darkened(0.55)
	if _hand_material != null:
		_hand_material.albedo_color = color.lightened(0.35)
		_hand_material.emission = color.lightened(0.25)
	if _spark_material != null:
		_spark_material.albedo_color = Color(color.r, color.g, color.b, 0.0)
		_spark_material.emission = color.lightened(0.4)


func flash_anchor(world_position: Vector3) -> void:
	if _spark == null:
		return
	_spark.global_position = world_position
	_spark_life = 1.0
	_spark.visible = true


func update_arm(start_global: Vector3, end_global: Vector3, draw: bool, anchored: bool) -> void:
	if _tube_mesh == null:
		return
	_tube_mesh.clear_surfaces()

	if hand_marker != null:
		hand_marker.visible = false

	if not draw:
		return

	var distance: float = start_global.distance_to(end_global)
	if distance < 0.05:
		return

	var thin: float = clampf(1.2 / maxf(distance, 1.2), 0.32, 1.0)
	var radius: float = base_radius * thin
	var tension: float = clampf(distance / 9.0, 0.0, 1.0)
	var sag: float = lerpf(max_sag, 0.04, tension)
	if not anchored:
		sag *= 0.32

	var mid: Vector3 = (start_global + end_global) * 0.5
	var control: Vector3 = mid + (Vector3.DOWN * sag)

	var rings: Array = []
	for i in range(curve_segments + 1):
		var t: float = float(i) / float(curve_segments)
		var center: Vector3 = _bezier(start_global, control, end_global, t)
		var tangent: Vector3 = _bezier_tangent(start_global, control, end_global, t).normalized()
		if tangent.length_squared() < 0.001:
			tangent = (end_global - start_global).normalized()
		var up_ref: Vector3 = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.92 else Vector3.RIGHT
		var normal: Vector3 = tangent.cross(up_ref).normalized()
		var binormal: Vector3 = tangent.cross(normal).normalized()

		var ring: Array = []
		for j in range(radial_segments):
			var angle: float = (float(j) / float(radial_segments)) * TAU
			var offset: Vector3 = (normal * cos(angle) + binormal * sin(angle)) * radius
			ring.append(to_local(center + offset))
		rings.append(ring)

	_tube_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(curve_segments):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for j in range(radial_segments):
			var next_j: int = (j + 1) % radial_segments
			var v00: Vector3 = r0[j]
			var v01: Vector3 = r0[next_j]
			var v10: Vector3 = r1[j]
			var v11: Vector3 = r1[next_j]
			_tube_mesh.surface_add_vertex(v00)
			_tube_mesh.surface_add_vertex(v10)
			_tube_mesh.surface_add_vertex(v01)
			_tube_mesh.surface_add_vertex(v01)
			_tube_mesh.surface_add_vertex(v10)
			_tube_mesh.surface_add_vertex(v11)
	_tube_mesh.surface_end()

	if hand_marker != null:
		hand_marker.global_position = end_global
		hand_marker.visible = true
		var scale: float = 1.15 if anchored else 0.85
		hand_marker.scale = Vector3.ONE * scale


func _process(delta: float) -> void:
	if _spark == null or not _spark.visible:
		return
	_spark_life -= delta / maxf(spark_duration, 0.01)
	if _spark_life <= 0.0:
		_spark.visible = false
		_spark_life = 0.0
		return
	var grown: float = lerpf(1.9, 0.35, 1.0 - _spark_life)
	_spark.scale = Vector3.ONE * grown
	if _spark_material != null:
		var c: Color = _spark_material.albedo_color
		c.a = _spark_life
		_spark_material.albedo_color = c


func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var q0: Vector3 = p0.lerp(p1, t)
	var q1: Vector3 = p1.lerp(p2, t)
	return q0.lerp(q1, t)


func _bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	return 2.0 * (1.0 - t) * (p1 - p0) + 2.0 * t * (p2 - p1)
