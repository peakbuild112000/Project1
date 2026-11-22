extends Node3D
class_name LevelGenerator

## Deterministic, seeded climbing tower. One fixed seed keeps the route fair;
## a small per-match offset reshuffles ledges, gusts and brittle placements.

const HAZARD_SCRIPT = preload("res://scripts/game/hazard.gd")
const PROP_SCRIPT = preload("res://scripts/game/prop.gd")
const ITEM_SCRIPT = preload("res://scripts/game/item_pickup.gd")
const KIND_WIND := 0
const KIND_CHECKPOINT := 1
const KIND_SUMMIT := 2
const KIND_BRITTLE := 3
const SUMMIT_Y := 142.0
const MODEL_CRATE := "res://assets/models/crate.glb"
const MODEL_PLANK := "res://assets/models/plank.glb"
const MODEL_TRAMPOLINE := "res://assets/models/trampoline.glb"
const MODEL_JETPACK := "res://assets/models/jetpack.glb"

signal hazard_hit(kind: int, label: String, body: Node)
signal checkpoint_touched(height: float, body: Node)
signal summit_touched(body: Node)
signal item_touched(item_id: String, body: Node)

var rng := RandomNumberGenerator.new()
var seed_value := 0
var spawn_points: Array[Vector3] = []
var checkpoint_positions: Dictionary = {}
var props: Array[Node] = []
var items: Array[Node] = []
var summit_position := Vector3(0, SUMMIT_Y, 0)
var spectator_position := Vector3(26, 62.0, 0)

var _base_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _hold_material: StandardMaterial3D
var _overhang_material: StandardMaterial3D
var _accent_material: StandardMaterial3D
var _brittle_material: StandardMaterial3D
var _moving_material: StandardMaterial3D
var _checkpoint_material: StandardMaterial3D
var _summit_material: StandardMaterial3D
var _beacon_material: StandardMaterial3D
var _rock_material: StandardMaterial3D
var _snow_material: StandardMaterial3D
var _wood_material: StandardMaterial3D
var _beacon: Node3D = null
var _tutorial: Node3D = null
var _tutorial_position := Vector3(0.0, 3.7, -15.1)
var _mission_sign: Node3D = null
var _house_position := Vector3(0.0, 1.9, -11.0)


func generate(match_seed: int) -> void:
	_clear()
	seed_value = match_seed
	rng.seed = match_seed
	_build_materials()
	_build_base()
	_build_cabin()
	_build_mountain_shell()
	_build_tower()
	_build_checkpoints()
	_build_wind()
	_build_brittle_holds()
	_build_moving_platforms()
	_build_summit()
	_build_spectator_deck()
	_build_props()
	_build_items()


func _clear() -> void:
	for child in get_children():
		child.queue_free()
	spawn_points.clear()
	checkpoint_positions.clear()
	props.clear()
	items.clear()
	_beacon = null
	_tutorial = null
	_mission_sign = null


func _material(color: Color, emission: Color = Color.BLACK, emission_strength: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.74
	material.metallic = 0.06
	if emission_strength > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_strength
	return material


func _build_materials() -> void:
	_base_material = _material(Color(0.18, 0.21, 0.27))
	_wall_material = _material(Color(0.25, 0.29, 0.36))
	_hold_material = _material(Color(0.58, 0.62, 0.68))
	_overhang_material = _material(Color(0.38, 0.31, 0.42))
	_accent_material = _material(Color(0.16, 0.48, 0.62), Color(0.05, 0.45, 0.7), 0.5)
	_brittle_material = _material(Color(0.72, 0.48, 0.32), Color(0.6, 0.2, 0.05), 0.35)
	_moving_material = _material(Color(0.34, 0.58, 0.48), Color(0.05, 0.4, 0.2), 0.3)
	_checkpoint_material = _material(Color(0.22, 0.55, 0.48), Color(0.08, 0.75, 0.5), 0.7)
	_summit_material = _material(Color(0.68, 0.62, 0.26), Color(0.9, 0.7, 0.12), 0.8)
	_beacon_material = _material(Color(0.5, 0.9, 1.0), Color(0.15, 0.75, 1.0), 2.2)
	_rock_material = _material(Color(0.21, 0.23, 0.28))
	_snow_material = _material(Color(0.72, 0.79, 0.86))
	_wood_material = _material(Color(0.34, 0.23, 0.16))


func _add_box(pos: Vector3, size: Vector3, material: Material, parent: Node = null, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var host: Node = self
	if parent != null:
		host = parent
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = pos
	body.rotation = rot
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = material
	body.add_child(mesh)
	host.add_child(body)
	return body


func _add_hazard(pos: Vector3, size: Vector3, kind: int, hazard_label: String) -> Area3D:
	var area := Area3D.new()
	area.set_script(HAZARD_SCRIPT)
	area.position = pos
	area.collision_layer = 1
	area.collision_mask = 3
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	add_child(area)
	area.set("hazard_type", kind)
	area.set("label", hazard_label)
	return area


func _build_base() -> void:
	_add_box(Vector3(0, -0.5, 0), Vector3(36, 3, 36), _base_material)
	_add_box(Vector3(0, 0.9, 0), Vector3(21, 0.4, 21), _accent_material)
	var x_positions: Array[float] = [-3.4, -1.15, 1.15, 3.4]
	for x in x_positions:
		spawn_points.append(Vector3(x, 1.95, -12.8))


func _build_mountain_shell() -> void:
	var tiers := 14
	for i in range(tiers):
		var t := float(i) / float(tiers - 1)
		var y := 2.0 + t * 135.0
		var size := lerpf(9.2, 2.6, t)
		var offset := Vector3(sin(float(i) * 1.7) * 0.85, 0.0, cos(float(i) * 1.3) * 0.85)
		var material: Material = _rock_material if i < 10 else _snow_material
		_add_box(
			offset + Vector3(0.0, y, 0.0),
			Vector3(size, 11.0, size * 0.86),
			material, null, Vector3(0.0, float(i) * 0.21, 0.0)
		)
		if i % 2 == 0:
			var angle := float(i) * 0.9
			var ridge := Vector3(cos(angle) * size * 0.62, y + 1.5, sin(angle) * size * 0.62)
			_add_box(
				ridge,
				Vector3(size * 0.5, 7.5, size * 0.45),
				material, null, Vector3(0.08, angle, 0.12)
			)


func _build_tower() -> void:
	var segments := 28
	for i in range(segments):
		var y := 3.5 + float(i) * 5.0
		var angle := float(i) * 0.42
		var offset := Vector3(sin(angle) * 2.0, 0.0, cos(angle) * 2.0)
		_add_box(offset + Vector3(0, y, 0), Vector3(6.4, 5.3, 5.2), _wall_material, null, Vector3(0, angle * 0.5, 0))
		var ledge_count := 2 if i % 3 != 0 else 3
		for j in range(ledge_count):
			var hold_angle := angle + TAU * float(j) / float(ledge_count) + rng.randf_range(-0.28, 0.28)
			var radius := rng.randf_range(5.0, 8.6)
			var width := rng.randf_range(2.4, 4.4)
			var depth := rng.randf_range(1.8, 3.2)
			var hold_pos := Vector3(cos(hold_angle) * radius, y + rng.randf_range(-1.4, 1.7), sin(hold_angle) * radius)
			var hold_rot := Vector3(rng.randf_range(-0.14, 0.14), hold_angle + rng.randf_range(-0.45, 0.45), rng.randf_range(-0.14, 0.14))
			_add_box(hold_pos, Vector3(width, 0.55, depth), _hold_material, null, hold_rot)
			if i % 3 == 0 and j == 0:
				_add_box(hold_pos + Vector3(0, 2.9, 0), Vector3(width + 0.7, 0.5, depth + 0.5), _overhang_material, null, Vector3(0.1, hold_rot.y + 0.3, 0.08))
		if i % 3 == 1:
			var wall_angle := angle + 1.2
			_add_box(Vector3(cos(wall_angle) * 4.8, y + 1.0, sin(wall_angle) * 4.8), Vector3(0.7, 7.5, 3.2), _wall_material, null, Vector3(0, wall_angle, 0))


func _build_checkpoints() -> void:
	var heights: Array[float] = [20.0, 50.0, 90.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var angle := 0.7 + float(i) * 2.1
		var pos := Vector3(cos(angle) * 7.8, height, sin(angle) * 7.8)
		_add_box(pos, Vector3(5.4, 0.7, 5.4), _checkpoint_material)
		_add_box(pos + Vector3(0, 1.7, 0), Vector3(0.32, 3.2, 0.32), _beacon_material)
		var area := _add_hazard(pos + Vector3(0, 2.0, 0), Vector3(6.4, 5.0, 6.4), KIND_CHECKPOINT, "CHECKPOINT %d m" % int(height))
		area.set("checkpoint_height", height)
		area.connect(&"checkpoint_reached", Callable(self, "_on_hazard_checkpoint"))
		area.connect(&"hazard_triggered", Callable(self, "_on_hazard_triggered"))
		checkpoint_positions[height] = pos + Vector3(0, 1.2, 0)


func _build_wind() -> void:
	var heights: Array[float] = [30.0, 65.0, 100.0, 123.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var area := _add_hazard(Vector3(0, height, 0), Vector3(31, 10, 31), KIND_WIND, "WIND GUST")
		var angle := rng.randf_range(0.0, TAU)
		area.set("gust_axis", Vector3(cos(angle), 0.0, sin(angle)))
		area.set("wind_force", 9.0 + float(i) * 4.0)
		area.set("gust_period", rng.randf_range(3.4, 5.8))
		area.set("gust_phase", rng.randf_range(0.0, 1.0))
		area.connect(&"hazard_triggered", Callable(self, "_on_hazard_triggered"))
		_add_wind_visual(height)


func _add_wind_visual(height: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.75, 1.0, 0.055)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.2, 0.5, 0.9)
	material.emission_energy_multiplier = 0.3
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(31, 10, 31)
	mesh.mesh = cube
	mesh.material_override = material
	mesh.position = Vector3(0, height, 0)
	add_child(mesh)


func _build_brittle_holds() -> void:
	var heights: Array[float] = [36.0, 56.0, 76.0, 96.0, 116.0, 132.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var count := 3 if i < 3 else 2
		for j in range(count):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(5.2, 8.2)
			var size := Vector3(rng.randf_range(2.4, 3.6), 0.5, rng.randf_range(2.0, 3.0))
			var hold = HAZARD_SCRIPT.BrittleHold.new()
			hold.call("setup", size, _brittle_material, 2.0)
			hold.position = Vector3(cos(angle) * radius, height + rng.randf_range(-1.0, 1.0), sin(angle) * radius)
			hold.rotation = Vector3(0.0, angle + rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.1))
			add_child(hold)
			hold.connect(&"broke", Callable(self, "_on_brittle_broke"))


func _build_moving_platforms() -> void:
	var heights: Array[float] = [45.0, 80.0, 110.0, 130.0]
	for i in range(heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var origin := Vector3(cos(angle) * 7.2, heights[i], sin(angle) * 7.2)
		var travel := Vector3(-sin(angle) * (8.0 + float(i) * 1.6), rng.randf_range(0.0, 1.2), cos(angle) * (8.0 + float(i) * 1.6))
		var platform = HAZARD_SCRIPT.MovingPlatform.new()
		platform.call("setup", origin, travel, 4.5 + float(i) * 0.5, rng.randf_range(0.0, 1.0), Vector3(3.8, 0.6, 3.4), _moving_material)
		add_child(platform)
		_add_box(Vector3(cos(angle) * 7.2, heights[i] - 5.0, sin(angle) * 7.2), Vector3(2.8, 0.5, 2.8), _hold_material, null, Vector3(0, angle, 0))


func _build_summit() -> void:
	_add_box(Vector3(0, 141.0, 0), Vector3(7.0, 1.0, 7.0), _summit_material)
	_add_box(Vector3(0, 143.6, 0), Vector3(1.2, 5.0, 1.2), _beacon_material)
	var area := _add_hazard(Vector3(0, 142.8, 0), Vector3(9, 5, 9), KIND_SUMMIT, "SUMMIT")
	area.connect(&"summit_reached", Callable(self, "_on_hazard_summit"))
	area.connect(&"hazard_triggered", Callable(self, "_on_hazard_triggered"))
	summit_position = Vector3(0, SUMMIT_Y, 0)
	_beacon = Node3D.new()
	_beacon.position = Vector3(0, 145.0, 0)
	add_child(_beacon)
	for i in range(3):
		var torus := TorusMesh.new()
		torus.inner_radius = 2.0 + float(i) * 0.45
		torus.outer_radius = 2.16 + float(i) * 0.45
		torus.rings = 6
		torus.ring_segments = 28
		var ring := MeshInstance3D.new()
		ring.mesh = torus
		ring.material_override = _beacon_material
		ring.rotation_degrees = Vector3(float(i) * 62.0, float(i) * 37.0, 0.0)
		_beacon.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 0.9, 1.0)
	light.light_energy = 7.0
	light.omni_range = 30.0
	_beacon.add_child(light)


func _build_spectator_deck() -> void:
	_add_box(Vector3(26, 60.0, 0), Vector3(9, 0.7, 9), _base_material)
	_add_box(Vector3(26, 61.6, -4.0), Vector3(8, 2.4, 0.4), _accent_material)
	spectator_position = Vector3(26, 62.2, 0)


func _build_cabin() -> void:
	var wall_y := 3.75
	_add_box(Vector3(0.0, 1.16, -11.0), Vector3(12.0, 0.25, 9.0), _wood_material)
	_add_box(Vector3(0.0, wall_y, -15.45), Vector3(12.0, 5.0, 0.5), _wood_material)
	_add_box(Vector3(-5.85, wall_y, -11.0), Vector3(0.5, 5.0, 9.0), _wood_material)
	_add_box(Vector3(5.85, wall_y, -11.0), Vector3(0.5, 5.0, 9.0), _wood_material)
	_add_box(Vector3(-3.9, wall_y, -6.55), Vector3(4.0, 5.0, 0.5), _wood_material)
	_add_box(Vector3(3.9, wall_y, -6.55), Vector3(4.0, 5.0, 0.5), _wood_material)
	_add_box(Vector3(0.0, 5.85, -6.55), Vector3(3.8, 0.7, 0.5), _wood_material)
	_add_box(Vector3(0.0, 6.65, -11.0), Vector3(12.7, 0.35, 9.7), _wood_material)
	_build_control_drawings()
	_build_mission_sign()


func _icon(parent: Node3D, pos: Vector3, size: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = pos
	mesh.rotation = rot
	parent.add_child(mesh)


func _caption(parent: Node3D, text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 34
	label.pixel_size = 0.0055
	label.modulate = Color(0.82, 0.94, 1.0)
	label.outline_size = 6
	label.outline_modulate = Color(0.02, 0.03, 0.06, 0.9)
	label.position = pos
	parent.add_child(label)


func _build_control_drawings() -> void:
	_tutorial = Node3D.new()
	_tutorial.name = "ControlDrawings"
	_tutorial.position = Vector3(0.0, 3.7, -15.12)
	add_child(_tutorial)

	_icon(_tutorial, Vector3(-4.2, 0.75, 0.0), Vector3(1.3, 0.12, 0.08), _accent_material)
	_icon(_tutorial, Vector3(-4.2, 0.75, 0.0), Vector3(0.12, 1.1, 0.08), _accent_material)
	_icon(_tutorial, Vector3(-4.75, 1.3, 0.0), Vector3(0.45, 0.1, 0.08), _accent_material, Vector3(0, 0, 0.7))
	_icon(_tutorial, Vector3(-3.65, 1.3, 0.0), Vector3(0.45, 0.1, 0.08), _accent_material, Vector3(0, 0, -0.7))
	_caption(_tutorial, "MOVE", Vector3(-4.85, -0.35, 0.0))

	_icon(_tutorial, Vector3(-2.1, 0.75, 0.0), Vector3(0.55, 0.85, 0.1), _hold_material)
	_icon(_tutorial, Vector3(-2.1, 1.05, 0.0), Vector3(0.1, 0.25, 0.1), _beacon_material)
	_caption(_tutorial, "LOOK", Vector3(-2.75, -0.35, 0.0))

	_icon(_tutorial, Vector3(0.0, 1.0, 0.0), Vector3(0.09, 1.1, 0.08), _summit_material, Vector3(0, 0, 0.45))
	_icon(_tutorial, Vector3(0.4, 1.0, 0.0), Vector3(0.09, 1.1, 0.08), _summit_material, Vector3(0, 0, -0.45))
	_icon(_tutorial, Vector3(-0.12, 1.55, 0.0), Vector3(0.24, 0.24, 0.1), _summit_material)
	_icon(_tutorial, Vector3(0.52, 1.55, 0.0), Vector3(0.24, 0.24, 0.1), _summit_material)
	_caption(_tutorial, "GRAPPLE", Vector3(-0.85, -0.35, 0.0))

	_icon(_tutorial, Vector3(2.1, 0.8, 0.0), Vector3(0.8, 0.8, 0.12), _brittle_material)
	_icon(_tutorial, Vector3(1.55, 0.8, 0.0), Vector3(0.12, 0.5, 0.1), _hold_material)
	_icon(_tutorial, Vector3(2.65, 0.8, 0.0), Vector3(0.12, 0.5, 0.1), _hold_material)
	_caption(_tutorial, "GRAB / DROP", Vector3(1.15, -0.35, 0.0))

	_icon(_tutorial, Vector3(4.2, 0.85, 0.0), Vector3(0.55, 1.0, 0.12), _hold_material)
	_icon(_tutorial, Vector3(4.2, 0.1, 0.0), Vector3(0.35, 0.5, 0.1), _checkpoint_material, Vector3(0, 0, 0.25))
	_caption(_tutorial, "JETPACK", Vector3(3.55, -0.35, 0.0))


func _build_mission_sign() -> void:
	_mission_sign = Node3D.new()
	_mission_sign.name = "MissionSign"
	_mission_sign.position = Vector3(0.0, 5.6, -5.9)
	_mission_sign.rotation.y = PI
	_mission_sign.visible = false

	var label := Label3D.new()
	label.text = "BRING WATER\nTO YOUR HOUSE"
	label.font_size = 96
	label.pixel_size = 0.011
	label.modulate = Color(1.0, 0.88, 0.45)
	label.outline_size = 14
	label.outline_modulate = Color(0.02, 0.03, 0.06, 0.95)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_sign.add_child(label)
	add_child(_mission_sign)


func _process(delta: float) -> void:
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.rotation.y += delta * 1.15
	if _mission_sign != null and is_instance_valid(_mission_sign):
		var show := false
		for climber in get_tree().get_nodes_in_group("climbers"):
			if not bool(climber.get("is_local")):
				continue
			var climber_position: Vector3 = climber.get("global_position")
			show = climber_position.z > -7.0 and climber_position.z < 3.0 and climber_position.y < 12.0
			break
		_mission_sign.visible = show


func get_house_position() -> Vector3:
	return _house_position


func get_spawn_point(index: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 1.9, 0)
	return spawn_points[index % spawn_points.size()]


func get_checkpoint_position(height: float) -> Vector3:
	var best := -1.0
	for key in checkpoint_positions.keys():
		var candidate := float(key)
		if candidate <= height + 0.01 and candidate > best:
			best = candidate
	if best >= 0.0:
		var pos: Variant = checkpoint_positions[best]
		if pos is Vector3:
			return pos
	return get_spawn_point(0)


func get_spectator_position() -> Vector3:
	return spectator_position


func _on_hazard_triggered(kind: int, hazard_label: String, body: Node) -> void:
	hazard_hit.emit(kind, hazard_label, body)


func _on_hazard_checkpoint(height: float, body: Node) -> void:
	checkpoint_touched.emit(height, body)


func _on_hazard_summit(body: Node) -> void:
	summit_touched.emit(body)


func _on_brittle_broke() -> void:
	hazard_hit.emit(KIND_BRITTLE, "HOLD SNAPPED", self)


func _instance_model(path: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Model"
	if not ResourceLoader.exists(path):
		var fallback := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 0.8, 0.8)
		fallback.mesh = box
		holder.add_child(fallback)
		return holder
	var packed := load(path) as PackedScene
	if packed == null:
		return holder
	var model := packed.instantiate()
	if model is Node3D:
		holder.add_child(model)
	return holder


func _add_prop_pedestal(pos: Vector3, size: Vector3) -> void:
	_add_box(pos + (Vector3.DOWN * 0.55), size, _hold_material)


func _make_prop(id: String, object_kind: int, object_name: String, object_mass: float, launch: float, model_path: String, shape: Shape3D, shape_offset: Vector3, pos: Vector3, angle: float) -> Node:
	var body = PROP_SCRIPT.new()
	body.name = "Prop_%s" % id
	body.collision_layer = 4
	body.collision_mask = 3
	body.linear_damp = 0.35
	body.angular_damp = 1.4
	body.set("mass_kg", object_mass)
	body.call("setup", id, object_kind, object_name, object_mass, launch)
	body.position = pos
	body.rotation = Vector3(0.0, angle, 0.0)

	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = shape_offset
	body.add_child(collision)

	if not model_path.is_empty():
		var holder := _instance_model(model_path)
		if object_kind == PROP_SCRIPT.Kind.TRAMPOLINE:
			holder.position.y = -0.55
		body.add_child(holder)
	add_child(body)
	props.append(body)

	var pedestal_size := Vector3(2.4, 0.5, 2.4)
	var pedestal_offset := 0.55
	if object_kind == PROP_SCRIPT.Kind.PLANK:
		pedestal_size = Vector3(3.4, 0.5, 1.4)
	elif object_kind == PROP_SCRIPT.Kind.TRAMPOLINE:
		pedestal_size = Vector3(2.9, 0.5, 2.9)
	elif object_kind == PROP_SCRIPT.Kind.BUCKET:
		pedestal_size = Vector3(2.6, 0.5, 2.6)
		pedestal_offset = 1.05
	_add_box(pos + (Vector3.DOWN * pedestal_offset), pedestal_size, _hold_material)
	return body


func _build_props() -> void:
	var crate_shape := BoxShape3D.new()
	crate_shape.size = Vector3(1.1, 1.1, 1.1)
	var plank_shape := BoxShape3D.new()
	plank_shape.size = Vector3(3.0, 0.18, 0.7)
	var trampoline_shape := CylinderShape3D.new()
	trampoline_shape.radius = 1.05
	trampoline_shape.height = 0.42
	var bucket_shape := CylinderShape3D.new()
	bucket_shape.radius = 0.92
	bucket_shape.height = PROP_SCRIPT.BUCKET_HEIGHT

	var crate_heights: Array[float] = [10.0, 33.0, 58.0, 84.0, 108.0, 128.0]
	for i in range(crate_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(5.8, 7.4)
		var pos := Vector3(cos(angle) * radius, crate_heights[i] + 0.85, sin(angle) * radius)
		_make_prop("crate_%d" % i, PROP_SCRIPT.Kind.CRATE, "CAISSE", 28.0, 0.0, MODEL_CRATE, crate_shape, Vector3.ZERO, pos, rng.randf_range(0.0, TAU))

	var plank_heights: Array[float] = [18.0, 44.0, 72.0, 100.0, 122.0]
	for i in range(plank_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(6.2, 7.8)
		var pos := Vector3(cos(angle) * radius, plank_heights[i] + 0.35, sin(angle) * radius)
		_make_prop("plank_%d" % i, PROP_SCRIPT.Kind.PLANK, "PLANCHE", 16.0, 0.0, MODEL_PLANK, plank_shape, Vector3.ZERO, pos, rng.randf_range(0.0, TAU))

	var trampoline_heights: Array[float] = [26.0, 66.0, 94.0, 130.0]
	for i in range(trampoline_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(6.0, 7.4)
		var pos := Vector3(cos(angle) * radius, trampoline_heights[i] + 0.55, sin(angle) * radius)
		_make_prop("trampoline_%d" % i, PROP_SCRIPT.Kind.TRAMPOLINE, "TRAMPOLINE", 90.0, 15.5 + float(i) * 0.7, MODEL_TRAMPOLINE, trampoline_shape, Vector3.ZERO, pos, rng.randf_range(0.0, TAU))

	_make_prop(
		"bucket_0", PROP_SCRIPT.Kind.BUCKET, "SEAU D'EAU", 48.0, 0.0,
		"", bucket_shape, Vector3.ZERO, Vector3(3.4, 143.2, 0.0), 0.0
	)


func _build_items() -> void:
	var jetpack_heights: Array[float] = [13.0, 78.0]
	for i in range(jetpack_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(6.0, 7.6)
		var pickup = ITEM_SCRIPT.new()
		pickup.name = "JetpackPickup_%d" % i
		pickup.collision_layer = 4
		pickup.collision_mask = 2
		pickup.call("setup", "jetpack_%d" % i, 70.0)
		pickup.position = Vector3(cos(angle) * radius, jetpack_heights[i] + 1.4, sin(angle) * radius)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.15
		shape.shape = sphere
		pickup.add_child(shape)
		var holder := _instance_model(MODEL_JETPACK)
		holder.scale = Vector3.ONE * 1.25
		pickup.add_child(holder)
		var light := OmniLight3D.new()
		light.light_color = Color(0.2, 0.85, 1.0)
		light.light_energy = 4.0
		light.omni_range = 8.0
		pickup.add_child(light)
		add_child(pickup)
		items.append(pickup)
		if pickup.has_signal(&"touched"):
			pickup.connect(&"touched", Callable(self, "_on_item_touched"))
		_add_prop_pedestal(pickup.position + (Vector3.DOWN * 0.7), Vector3(2.0, 0.5, 2.0))


func _on_item_touched(item_id: String, body: Node) -> void:
	item_touched.emit(item_id, body)


func get_prop(prop_id: String) -> Node:
	for prop in props:
		if is_instance_valid(prop) and str(prop.get("prop_id")) == prop_id:
			return prop
	return null


func get_item(item_id: String) -> Node:
	for item in items:
		if is_instance_valid(item) and str(item.get("item_id")) == item_id:
			return item
	return null
