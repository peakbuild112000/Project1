extends Node3D
class_name LevelGenerator

## Deterministic, seeded procedural mountain. The same seed always produces the
## same slope, ledges, gusts and brittle holds so every peer shares one route.

const HAZARD_SCRIPT = preload("res://scripts/game/hazard.gd")
const PROP_SCRIPT = preload("res://scripts/game/prop.gd")
const ITEM_SCRIPT = preload("res://scripts/game/item_pickup.gd")
const ENEMY_SCRIPT = preload("res://scripts/game/enemy.gd")
const KIND_WIND := 0
const KIND_CHECKPOINT := 1
const KIND_SUMMIT := 2
const KIND_BRITTLE := 3
const KIND_ENEMY := 4
const SUMMIT_Y := 142.0
const MOUNTAIN_CENTER_Z := 16.0
const MOUNTAIN_BASE_RADIUS := 19.0
const MOUNTAIN_GRID := 49
const MODEL_TRAMPOLINE := "res://assets/models/trampoline.glb"
const MODEL_JETPACK := "res://assets/models/jetpack.glb"
const MODEL_ROCK := "res://assets/models/rock.glb"
const MODEL_ENEMY := "res://assets/models/enemy.glb"

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
var summit_position := Vector3(0, SUMMIT_Y, MOUNTAIN_CENTER_Z)

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
var _mountain_material: StandardMaterial3D
var _beacon: Node3D = null
var _noise_phase_a := 0.0
var _noise_phase_b := 0.0
var _noise_phase_c := 0.0
var _noise_phase_d := 0.0


func generate(match_seed: int) -> void:
	_clear()
	seed_value = match_seed
	rng.seed = match_seed
	_noise_phase_a = rng.randf_range(0.0, TAU)
	_noise_phase_b = rng.randf_range(0.0, TAU)
	_noise_phase_c = rng.randf_range(0.0, TAU)
	_noise_phase_d = rng.randf_range(0.0, TAU)
	_build_materials()
	_build_base()
	_build_mountain_surface()
	_build_start_holds()
	_build_mountain_routes()
	_build_difficult_pillar()
	_build_rocks()
	_build_checkpoints()
	_build_wind()
	_build_brittle_holds()
	_build_moving_platforms()
	_build_summit()
	_build_enemies()
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
	_mountain_material = _material(Color.WHITE)
	_mountain_material.vertex_color_use_as_albedo = true


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
	_add_box(Vector3(0, -0.5, MOUNTAIN_CENTER_Z), Vector3(52, 3, 52), _base_material)
	# Small flat pad at the very bottom and horizontal centre of the mountain.
	# The four slots are clustered around x = 0 so everybody starts in the middle.
	var pad := _add_box(Vector3(0, 2.0, -1.0), Vector3(8.0, 0.4, 3.0), _accent_material)
	pad.name = "StartPad"
	var x_positions: Array[float] = [-1.5, -0.5, 0.5, 1.5]
	for x in x_positions:
		spawn_points.append(Vector3(x, 3.05, -1.0))


func _build_start_holds() -> void:
	## Guaranteed, evenly spaced grips up the front face. The procedural route
	## starts higher up and its ribs used to wall off this entrance corridor.
	for i in range(13):
		var target_y := 2.5 + float(i) * 2.5
		var x := -1.3 if i % 2 == 0 else 1.3
		var z := _entrance_z_for_height(x, target_y)
		var hold := Vector3(x, _height_at(x, z) + 0.7, z)
		var body := _add_box(hold, Vector3(3.4, 0.5, 1.8), _hold_material)
		body.name = "EntranceHold_%d" % i
		if i % 3 == 2:
			var rest := _add_box(
				hold + Vector3(0.0, 0.4, 1.1),
				Vector3(3.0, 0.4, 1.5), _accent_material
			)
			rest.name = "EntranceRest_%d" % i


func _entrance_z_for_height(x: float, target_y: float) -> float:
	## First z on the near face where the terrain reaches `target_y`.
	var best_z := 2.0
	for step in range(0, 49):
		var z := -2.0 + float(step) * 0.25
		if _height_at(x, z) >= target_y:
			return z
		best_z = z
	return best_z


func _height_at(x: float, z: float) -> float:
	var dx := x
	var dz := z - MOUNTAIN_CENTER_Z
	var distance := sqrt(dx * dx + dz * dz)
	if distance >= MOUNTAIN_BASE_RADIUS:
		return 1.0
	var t := clampf(1.0 - distance / MOUNTAIN_BASE_RADIUS, 0.0, 1.0)
	var profile := pow(t, 1.75) * SUMMIT_Y
	var ridges := (
		sin(x * 0.41 + _noise_phase_a) * cos(dz * 0.33 + _noise_phase_b) * 4.6
		+ sin((x + dz) * 0.19 + _noise_phase_c) * 3.4
		+ cos((x - dz) * 0.27 + _noise_phase_d) * 2.2
	) * clampf(t * 1.7, 0.0, 1.0)
	var height := 1.0 + profile + ridges
	# Flat race start pad so nobody begins on a slope.
	var start_band := smoothstep(-6.0, -4.0, z) * (1.0 - smoothstep(0.0, 2.0, z))
	var start_width := 1.0 - smoothstep(5.0, 9.0, absf(x))
	height = lerpf(height, 1.0, start_band * start_width)
	if distance < 2.6:
		height = lerpf(height, SUMMIT_Y, clampf((2.6 - distance) / 2.6, 0.0, 1.0))
	return maxf(1.0, height)


func _mountain_point(height: float, angle: float, radial_offset: float = 0.0) -> Vector3:
	var ratio := clampf(height / SUMMIT_Y, 0.0, 1.0)
	var radius := MOUNTAIN_BASE_RADIUS * (1.0 - pow(ratio, 1.0 / 1.75)) + radial_offset
	return Vector3(
		cos(angle) * radius,
		height,
		MOUNTAIN_CENTER_Z + sin(angle) * radius
	)


func _build_mountain_surface() -> void:
	var half := MOUNTAIN_GRID / 2
	var cell := 1.0
	var vertices: Array[Vector3] = []
	var colors: Array[Color] = []
	for iz in range(MOUNTAIN_GRID + 1):
		var z := MOUNTAIN_CENTER_Z - float(half) + float(iz) * cell
		for ix in range(MOUNTAIN_GRID + 1):
			var x := -float(half) + float(ix) * cell
			var h := _height_at(x, z)
			vertices.append(Vector3(x, h, z))
			var snow := clampf((h - 82.0) / 55.0, 0.0, 1.0)
			var grit := clampf(sin(x * 0.73 + z * 0.41 + _noise_phase_d) * 0.08, -0.08, 0.08)
			colors.append(Color(0.21 + grit, 0.23 + grit, 0.28 + grit).lerp(Color(0.72, 0.79, 0.86), snow))

	var faces := PackedVector3Array()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_mountain_material)
	for iz in range(MOUNTAIN_GRID):
		for ix in range(MOUNTAIN_GRID):
			var a := iz * (MOUNTAIN_GRID + 1) + ix
			var b := a + 1
			var c := a + MOUNTAIN_GRID + 1
			var d := c + 1
			for tri in [[a, c, b], [b, c, d]]:
				var ids: Array = tri
				var i0 := int(ids[0])
				var i1 := int(ids[1])
				var i2 := int(ids[2])
				var p0: Vector3 = vertices[i0]
				var p1: Vector3 = vertices[i1]
				var p2: Vector3 = vertices[i2]
				faces.append(p0)
				faces.append(p1)
				faces.append(p2)
				surface.set_color(colors[i0])
				surface.add_vertex(p0)
				surface.set_color(colors[i1])
				surface.add_vertex(p1)
				surface.set_color(colors[i2])
				surface.add_vertex(p2)

	var body := StaticBody3D.new()
	body.name = "ProceduralMountain"
	body.collision_layer = 1
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	collision.shape = concave
	body.add_child(collision)

	surface.generate_normals()
	var mesh := surface.commit()
	var visual := MeshInstance3D.new()
	visual.name = "MountainMesh"
	visual.mesh = mesh
	body.add_child(visual)
	add_child(body)


func _build_mountain_routes() -> void:
	## Narrow, irregular holds pinned to the procedural slope. Higher bands are
	## smaller, more spaced out and hold fewer fragile grips.
	var tiers := 34
	for i in range(tiers):
		var difficulty := float(i) / float(tiers - 1)
		var y := 4.0 + difficulty * 132.0
		var ledge_count := 3 if i % 5 == 0 else 2
		var base_angle := float(i) * 0.71 + rng.randf_range(-0.18, 0.18)
		for j in range(ledge_count):
			var angle := base_angle + TAU * float(j) / float(ledge_count) + rng.randf_range(-0.22, 0.22)
			var pos := _mountain_point(
				y + rng.randf_range(-1.1, 1.4),
				angle,
				rng.randf_range(0.7, 1.9)
			)
			# Leave the front entrance corridor clear; _build_start_holds() owns it.
			if pos.z < 12.0 and absf(pos.x) < 8.0 and pos.y < 42.0:
				continue
			var width := rng.randf_range(lerpf(4.2, 2.2, difficulty), lerpf(5.4, 3.0, difficulty))
			var depth := rng.randf_range(lerpf(3.2, 1.6, difficulty), lerpf(4.2, 2.4, difficulty))
			var material: Material = _brittle_material if difficulty > 0.55 and rng.randf() < 0.25 else _hold_material
			var rotation := Vector3(
				rng.randf_range(-0.18, 0.18),
				angle + rng.randf_range(-0.4, 0.4),
				rng.randf_range(-0.18, 0.18)
			)
			_add_box(pos, Vector3(width, 0.45, depth), material, null, rotation)
			if i % 3 == 0 and j == 0:
				_add_box(
					pos + Vector3(0.0, rng.randf_range(2.2, 3.1), 0.0),
					Vector3(width * 0.85, 0.4, depth * 0.8),
					_overhang_material, null,
					Vector3(0.14, rotation.y + 0.35, -0.12)
				)
			if i % 4 == 2 and j == ledge_count - 1:
				_add_box(
					pos + Vector3(0.0, rng.randf_range(1.6, 2.4), 0.0),
					Vector3(width * 0.7, 0.35, depth * 0.75),
					_overhang_material, null,
					Vector3(-0.16, rotation.y - 0.4, 0.14)
				)
		if i % 2 == 1:
			var rib_angle := base_angle + 0.9
			var rib := _mountain_point(y - 1.0, rib_angle, 0.2)
			if rib.z < 12.0 and absf(rib.x) < 8.0 and rib.y < 42.0:
				continue
			_add_box(
				rib, Vector3(0.65, 6.2, 2.6), _wall_material, null,
				Vector3(rng.randf_range(-0.12, 0.12), rib_angle, rng.randf_range(-0.16, 0.16))
			)


func _build_difficult_pillar() -> void:
	## A narrow alternate spire: tiny sloped holds, wide gaps and sharp overhangs.
	var base := Vector3(22.5, 0.0, 14.0)
	var segments := 28
	for i in range(segments):
		var y := 4.0 + float(i) * 4.9
		var lean := Vector3(sin(float(i) * 0.55) * 0.7, 0.0, cos(float(i) * 0.48) * 0.7)
		var column := base + lean
		_add_box(column + Vector3(0.0, y, 0.0), Vector3(2.5, 5.0, 2.5), _wall_material, null, Vector3(0.04, float(i) * 0.31, -0.04))
		var hold_count := 2 if i % 5 != 0 else 1
		for j in range(hold_count):
			var angle := float(i) * 1.41 + TAU * float(j) / float(hold_count)
			var radius := rng.randf_range(2.0, 3.3)
			var hold_pos := column + Vector3(cos(angle) * radius, y + rng.randf_range(-0.8, 0.9), sin(angle) * radius)
			var hold_rot := Vector3(rng.randf_range(-0.28, 0.28), angle, rng.randf_range(-0.28, 0.28))
			_add_box(hold_pos, Vector3(rng.randf_range(0.9, 1.6), 0.3, rng.randf_range(0.8, 1.4)), _brittle_material, null, hold_rot)
			if i % 3 == 1:
				_add_box(hold_pos + Vector3(0.0, 2.5, 0.0), Vector3(1.3, 0.35, 1.2), _overhang_material, null, Vector3(0.22, hold_rot.y + 0.5, 0.18))
		if i % 6 == 3:
			_add_box(column + Vector3(0.0, y + 3.2, 0.0), Vector3(3.4, 0.35, 3.4), _hold_material, null, Vector3(0, float(i), 0))


func _build_rocks() -> void:
	for i in range(16):
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(9.0, MOUNTAIN_BASE_RADIUS - 1.0)
		var x := cos(angle) * radius
		var z := MOUNTAIN_CENTER_Z + sin(angle) * radius
		# Keep the whole entrance corridor clear of boulders.
		if absf(x) < 8.0 and z > -9.0 and z < 12.0:
			continue
		var rock_point := Vector3(x, _height_at(x, z) + 0.4, z)
		var holder := _instance_model(MODEL_ROCK)
		holder.name = "Rock_%d" % i
		holder.position = rock_point
		holder.rotation_degrees = Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(0.0, 360.0), rng.randf_range(-12.0, 12.0))
		var scale_value := rng.randf_range(0.9, 1.8)
		holder.scale = Vector3.ONE * scale_value
		add_child(holder)
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 1.2 * scale_value
		shape.shape = sphere
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 1
		body.position = rock_point
		body.add_child(shape)
		add_child(body)


func _build_enemies() -> void:
	var heights: Array[float] = [14.0, 42.0, 68.0, 95.0, 118.0, 136.0]
	for i in range(heights.size()):
		var enemy = ENEMY_SCRIPT.new()
		enemy.name = "Enemy_%d" % i
		var points: Array[Vector3] = []
		for step in range(4):
			var angle := TAU * float(step) / 4.0 + float(i) * 0.7
			points.append(_mountain_point(
				heights[i] + sin(angle * 2.0) * 1.4,
				angle,
				0.7 + float(i % 3) * 0.35
			))
		# setup() writes global_position, so the node must be in the tree first.
		add_child(enemy)
		enemy.call("setup", points, 2.4 + float(i) * 0.15, 13.0 + float(i) * 1.2)
		if enemy.has_signal(&"enemy_hit"):
			enemy.connect(&"enemy_hit", Callable(self, "_on_enemy_hit"))


func _build_checkpoints() -> void:
	var heights: Array[float] = [26.0, 64.0, 104.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var angle := 0.7 + float(i) * 2.1
		var pos := _mountain_point(height, angle, 1.2)
		_add_box(pos, Vector3(6.0, 0.7, 6.0), _checkpoint_material)
		_add_box(pos + Vector3(0, 1.7, 0), Vector3(0.32, 3.2, 0.32), _beacon_material)
		var area := _add_hazard(pos + Vector3(0, 2.0, 0), Vector3(5.4, 5.0, 5.4), KIND_CHECKPOINT, "CHECKPOINT %d m" % int(height))
		area.set("checkpoint_height", height)
		area.connect(&"checkpoint_reached", Callable(self, "_on_hazard_checkpoint"))
		area.connect(&"hazard_triggered", Callable(self, "_on_hazard_triggered"))
		checkpoint_positions[height] = pos + Vector3(0, 1.2, 0)


func _build_wind() -> void:
	var heights: Array[float] = [32.0, 68.0, 102.0, 126.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var area := _add_hazard(Vector3(0, height, MOUNTAIN_CENTER_Z), Vector3(44, 10, 44), KIND_WIND, "WIND GUST")
		var angle := rng.randf_range(0.0, TAU)
		area.set("gust_axis", Vector3(cos(angle), 0.0, sin(angle)))
		area.set("wind_force", 12.0 + float(i) * 5.0)
		area.set("gust_period", rng.randf_range(2.8, 4.8))
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
	cube.size = Vector3(44, 10, 44)
	mesh.mesh = cube
	mesh.material_override = material
	mesh.position = Vector3(0, height, MOUNTAIN_CENTER_Z)
	add_child(mesh)


func _build_brittle_holds() -> void:
	var heights: Array[float] = [38.0, 58.0, 78.0, 98.0, 118.0, 132.0]
	for i in range(heights.size()):
		var height: float = heights[i]
		var count := 3 if i < 3 else 2
		for _j in range(count):
			var angle := rng.randf_range(0.0, TAU)
			var size := Vector3(rng.randf_range(1.8, 2.8), 0.4, rng.randf_range(1.4, 2.2))
			var hold = HAZARD_SCRIPT.BrittleHold.new()
			hold.call("setup", size, _brittle_material, 1.4)
			hold.position = _mountain_point(height + rng.randf_range(-1.0, 1.0), angle, rng.randf_range(0.8, 1.6))
			hold.rotation = Vector3(0.0, angle + rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.1))
			add_child(hold)
			hold.connect(&"broke", Callable(self, "_on_brittle_broke"))


func _build_moving_platforms() -> void:
	var heights: Array[float] = [46.0, 82.0, 112.0, 130.0]
	for i in range(heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var origin := _mountain_point(heights[i], angle, 1.6)
		var travel_length := 9.0 + float(i) * 1.5
		var travel := Vector3(-sin(angle) * travel_length, rng.randf_range(0.0, 1.2), cos(angle) * travel_length)
		var platform = HAZARD_SCRIPT.MovingPlatform.new()
		platform.call("setup", origin, travel, 3.6 + float(i) * 0.5, rng.randf_range(0.0, 1.0), Vector3(4.4, 0.6, 3.8), _moving_material)
		add_child(platform)
		var anchor := _mountain_point(heights[i] - 4.0, angle, 0.4)
		_add_box(anchor, Vector3(2.2, 0.5, 2.2), _hold_material, null, Vector3(0, angle, 0))


func _build_summit() -> void:
	_add_box(Vector3(summit_position.x, 141.0, summit_position.z), Vector3(8.0, 1.0, 8.0), _summit_material)
	_add_box(Vector3(summit_position.x, 143.6, summit_position.z), Vector3(1.2, 5.0, 1.2), _beacon_material)
	var area := _add_hazard(Vector3(summit_position.x, 142.8, summit_position.z), Vector3(8, 5, 8), KIND_SUMMIT, "SUMMIT")
	area.connect(&"summit_reached", Callable(self, "_on_hazard_summit"))
	area.connect(&"hazard_triggered", Callable(self, "_on_hazard_triggered"))
	_beacon = Node3D.new()
	_beacon.position = Vector3(summit_position.x, 145.0, summit_position.z)
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



func _process(delta: float) -> void:
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.rotation.y += delta * 1.15


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


func _on_hazard_triggered(kind: int, hazard_label: String, body: Node) -> void:
	hazard_hit.emit(kind, hazard_label, body)


func _on_hazard_checkpoint(height: float, body: Node) -> void:
	checkpoint_touched.emit(height, body)


func _on_hazard_summit(body: Node) -> void:
	summit_touched.emit(body)


func _on_brittle_broke() -> void:
	hazard_hit.emit(KIND_BRITTLE, "HOLD SNAPPED", self)


func _on_enemy_hit(body: Node) -> void:
	hazard_hit.emit(KIND_ENEMY, "ENEMY HIT", body)


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

	var pedestal_size := Vector3(2.9, 0.5, 2.9)
	_add_box(pos + (Vector3.DOWN * 0.55), pedestal_size, _hold_material)
	return body


func _build_props() -> void:
	var trampoline_shape := CylinderShape3D.new()
	trampoline_shape.radius = 1.05
	trampoline_shape.height = 0.42
	var trampoline_heights: Array[float] = [28.0, 68.0, 96.0, 132.0]
	for i in range(trampoline_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var pos := _mountain_point(trampoline_heights[i], angle, rng.randf_range(0.8, 1.6))
		pos.y += 0.55
		_make_prop("trampoline_%d" % i, PROP_SCRIPT.Kind.TRAMPOLINE, "TRAMPOLINE", 90.0, 15.5 + float(i) * 0.7, MODEL_TRAMPOLINE, trampoline_shape, Vector3.ZERO, pos, rng.randf_range(0.0, TAU))


func _build_items() -> void:
	var jetpack_heights: Array[float] = [16.0, 82.0]
	for i in range(jetpack_heights.size()):
		var angle := rng.randf_range(0.0, TAU)
		var pickup = ITEM_SCRIPT.new()
		pickup.name = "JetpackPickup_%d" % i
		pickup.collision_layer = 4
		pickup.collision_mask = 2
		pickup.call("setup", "jetpack_%d" % i, 70.0)
		pickup.position = _mountain_point(jetpack_heights[i], angle, rng.randf_range(0.9, 1.7))
		pickup.position.y += 1.4
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
