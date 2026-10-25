class_name GrassLayer
extends RefCounted
## One kind of ground cover in a Grass lattice (blade clumps, pebbles, leaf patches or a small foliage
## model), parsed from data/grass/<area>.json. Owns the shared mesh and material and fills one cell's
## MultiMesh at a time from a GrassCell context. Density per candidate is the land (Grass.density_at)
## times patch noise, the cell's hollow factor, closeness to cluster points (trees) and the level's
## density filter. A cell's RNG is seeded from the cell key and the layer index, never from frame order,
## so a cell refilled after the player walks away and back grows exactly what it grew before.

const EXACT_SLOPE_MARGIN := 12.0

var name: String = ""
var kind: String = "clump"
var mesh: Mesh
var local: Transform3D = Transform3D.IDENTITY
var material: Material
var density: float = 1.0
var max_per_cell: int = 100
var max_slope: float = 32.0
var scale_range: Vector2 = Vector2(0.8, 1.2)
var height_range: Vector2 = Vector2(1.0, 1.0)
var patch_min: float = 1.0
var hollow: float = 0.0
var cluster_radius: float = 0.0
var cluster_falloff: float = 1.0
var cluster_outside: float = 1.0
var far_fraction: float = 0.3
var fade: Vector2 = Vector2(50.0, 70.0)
var align: float = 0.5
var sink: float = 0.0
var shadows: bool = false
var vertex_count: int = 0

var _patch: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func from_dict(d: Dictionary, seed_v: int, index: int) -> GrassLayer:
	var layer := GrassLayer.new()
	layer.name = str(d.get("name", "layer%d" % index))
	layer.kind = str(d.get("kind", "clump"))
	layer.density = maxf(0.0, float(d.get("density", 1.0)))
	layer.max_per_cell = maxi(0, int(d.get("max_per_cell", 100)))
	layer.max_slope = float(d.get("max_slope", 32.0))
	layer.scale_range = _range(d.get("scale"), Vector2(0.8, 1.2))
	layer.height_range = _range(d.get("height"), Vector2(1.0, 1.0)) if layer.kind == "clump" else layer.scale_range
	layer.patch_min = clampf(float(d.get("patch_min", 1.0)), 0.0, 1.0)
	layer.hollow = float(d.get("hollow", 0.0))
	var cluster: Dictionary = d.get("cluster", {})
	layer.cluster_radius = maxf(0.0, float(cluster.get("radius", 0.0)))
	layer.cluster_falloff = maxf(0.01, float(cluster.get("falloff", 1.0)))
	layer.cluster_outside = clampf(float(cluster.get("outside", 1.0)), 0.0, 1.0)
	layer.far_fraction = clampf(float(d.get("far_fraction", 0.3)), 0.0, 1.0)
	layer.fade = _range(d.get("fade"), Vector2(50.0, 70.0))
	layer.align = clampf(float(d.get("align", 1.0 if layer.kind == "patch" else 0.5)), 0.0, 1.0)
	layer.sink = float(d.get("sink", 0.0))
	layer.shadows = bool(d.get("shadows", false))
	if layer.patch_min < 1.0:
		layer._patch = FastNoiseLite.new()
		layer._patch.seed = seed_v + index * 7919
		layer._patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		layer._patch.fractal_type = FastNoiseLite.FRACTAL_NONE
		layer._patch.frequency = maxf(0.0001, float(d.get("patch_frequency", 0.04)))
	layer._build(d, seed_v, index)
	return layer


func _build(d: Dictionary, seed_v: int, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v ^ (index + 1) * 104729
	match kind:
		"clump":
			mesh = GrassMesh.clump(int(d.get("blades", 4)), int(d.get("segments", 3)), float(d.get("blade_width", 0.045)),
				_color(d.get("root_color"), Color(0.16, 0.18, 0.13)), _color(d.get("tip_color"), Color(0.55, 0.54, 0.42)), rng)
			material = GrassMesh.grass_material(fade, _color(d.get("dry_tint"), Color(0.70, 0.64, 0.48)))
		"pebble":
			mesh = GrassMesh.pebble(_color(d.get("color"), Color(0.30, 0.29, 0.28)), rng)
			material = GrassMesh.grass_material(fade, Color.WHITE)
		"patch":
			mesh = GrassMesh.patch_quad()
			material = GrassMesh.patch_material(str(d.get("texture", "")), fade, float(d.get("uv_tiles", 0.7)))
		"model":
			var found: Dictionary = GrassMesh.model_mesh(str(d.get("model", "")), str(d.get("mesh", "")))
			if not found.is_empty():
				mesh = found["mesh"]
				local = found["local"]
		_:
			push_error("GrassLayer %s: unknown kind '%s'" % [name, kind])
	vertex_count = GrassMesh.vertex_count(mesh)


func usable() -> bool:
	return mesh != null and max_per_cell > 0 and density > 0.0


## A pooled MultiMeshInstance3D with every instance slot preallocated: fills only write transforms.
func make_instance(slot: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = max_per_cell
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%d" % [name, slot]
	mmi.multimesh = mm
	if material != null:
		mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	return mmi


func set_wind(strength: float, direction: Vector2, speed: float, ripple: float) -> void:
	if material is ShaderMaterial and kind != "patch":
		var sm: ShaderMaterial = material
		sm.set_shader_parameter("wind_strength", strength)
		sm.set_shader_parameter("wind_dir", direction)
		sm.set_shader_parameter("wind_speed", speed)
		sm.set_shader_parameter("ripple_scale", ripple)


## Writes this layer's instances for one cell into `mmi` and their world origins into `out` (sized
## max_per_cell by the caller); returns how many were placed. `filter` is (x, z) -> float density
## multiplier and `exact_slope` is (x, z) -> degrees, asked only for borderline candidates.
func fill(key: Vector2i, index: int, seed_v: int, cell: GrassCell, mmi: MultiMeshInstance3D, out: PackedVector3Array, filter: Callable, exact_slope: Callable) -> int:
	_rng.seed = hash(Vector3i(key.x, key.y, index)) ^ seed_v
	var mm: MultiMesh = mmi.multimesh
	var candidates: int = mini(max_per_cell, ceili(density * cell.size * cell.size))
	var placed: int = 0
	for _c: int in candidates:
		# Every draw happens before any early-out so the RNG stream stays aligned whatever is rejected.
		var x: float = cell.origin.x + _rng.randf() * cell.size
		var z: float = cell.origin.y + _rng.randf() * cell.size
		var roll: float = _rng.randf()
		var yaw: float = _rng.randf() * TAU
		var s: float = _rng.randf_range(scale_range.x, scale_range.y)
		var h: float = _rng.randf_range(height_range.x, height_range.y)
		var custom := Color(_rng.randf(), _rng.randf(), _rng.randf(), 1.0)
		var n: Vector3 = cell.normal(x, z)
		var slope: float = GrassCell.slope_deg(n)
		var d: float = GrassLattice.density_at(slope, cell.height(x, z), cell.water_level, max_slope)
		if d <= 0.0:
			continue
		d *= clampf(1.0 + hollow * cell.hollow, 0.15, 2.5)
		if _patch != null:
			d *= lerpf(patch_min, 1.0, _patch.get_noise_2d(x, z) * 0.5 + 0.5)
		if cluster_radius > 0.0:
			d *= lerpf(1.0, cluster_outside, smoothstep(cluster_radius, cluster_radius + cluster_falloff, cell.nearest_cluster(x, z)))
		if filter.is_valid():
			d *= float(filter.call(x, z))
		if roll >= d:
			continue
		# The grid slope is a 3 m average; near the limit ask the heightfield exactly so the probe's
		# "nothing above max_slope" holds to the degree.
		if slope > max_slope - EXACT_SLOPE_MARGIN and exact_slope.is_valid() and float(exact_slope.call(x, z)) > max_slope:
			continue
		var y: float = float(cell.height_sampler.call(x, z)) - sink * s
		var basis: Basis = GroundPlacement.aligned_basis(n, yaw, align, 1.0) * Basis.from_scale(Vector3(s, h, s))
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, y, z)) * local)
		mm.set_instance_custom_data(placed, custom)
		out[placed] = Vector3(x, y, z)
		placed += 1
	mm.visible_instance_count = placed
	mmi.visible = placed > 0
	return placed


static func _range(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


static func _color(v: Variant, fallback: Color) -> Color:
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback
