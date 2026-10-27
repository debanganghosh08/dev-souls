class_name GrassLayer
extends RefCounted
## One kind of ground cover in a Grass lattice (blade clumps, wildflowers, pebbles, leaf patches or a
## small foliage model), parsed from data/grass/<area>.json. Owns the shared mesh and material and fills
## one cell's MultiMesh at a time from a GrassCell context. Density per candidate is the land
## (GrassLattice.density_at) times patch noise, the cell's hollow factor, closeness to cluster points
## (trees), the level's density filter and, for a layer with a `zone` channel, the area's GrassZones:
## "grass" scales by the zone density, "tall" and "flowers" by those 0..1 weights, so tall grass and
## flowers appear only where the zone asks. Zoned blades also take the zone's palette and height. A
## cell's RNG is seeded from the cell key and the layer index, never from frame order, so a cell refilled
## after the player walks away and back grows exactly what it grew before.

const EXACT_SLOPE_MARGIN := 12.0
const TINTED_KINDS: Array[String] = ["clump", "flower", "pebble"]

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
## Palette when the layer is not zoned (or the area has no zones): root at the ground, tip at the top.
var root_color: Color = GrassZones.DEFAULT_ROOT
var tip_color: Color = GrassZones.DEFAULT_TIP
## A blade drifts toward dry_tint by up to dry_amount of the way, per instance, so a field is never one colour.
var dry_tint: Color = Color.WHITE
var dry_amount: float = 0.0
## "" (the land only), "grass", "tall" or "flowers": which GrassZones channel scales this layer.
var zone_channel: String = ""
## Candidates per cell are sized for the densest zone; a zone's density then accepts its share of them.
var zone_max: float = 1.0
## Flower heads pick one of these per instance (kind "flower").
var colors: PackedColorArray = PackedColorArray()
## The instance colour and custom data of the last instance placed, kept CPU-side because the headless
## renderer discards what a MultiMesh is given; tests read these, the way they read positions.
var last_tint: Color = Color.BLACK
var last_custom: Color = Color.BLACK
## Instances placed by the fill in progress (or the last one finished): what fill() returns.
var placed: int = 0

## Phase profiling (W8-G2), off in play: with `profile` on, every candidate laps the clock between phases
## into phase_usec, so a probe can say where a unit's time goes. Static so the figures sum across layers.
enum Phase { CANDIDATE, LAND, ZONE, SLOPE, TRANSFORM, UPLOAD, COUNT }
const PHASE_NAMES: Array[String] = ["candidate", "land", "zone", "slope", "transform", "upload"]
static var profile: bool = false
static var phase_usec: PackedInt64Array = PackedInt64Array()
static var _lap_t: int = 0

var _patch: FastNoiseLite
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
# The fill in progress: candidates this cell draws and how many have been drawn. Only one cell is ever
# part-way through (Grass._partial_slot), so one cursor and the layer's RNG hold exactly one fill.
var _candidates: int = 0
var _cursor: int = 0


static func from_dict(d: Dictionary, seed_v: int, index: int) -> GrassLayer:
	var layer := GrassLayer.new()
	layer.name = str(d.get("name", "layer%d" % index))
	layer.kind = str(d.get("kind", "clump"))
	layer.density = maxf(0.0, float(d.get("density", 1.0)))
	layer.max_per_cell = maxi(0, int(d.get("max_per_cell", 100)))
	layer.max_slope = float(d.get("max_slope", 32.0))
	layer.scale_range = _range(d.get("scale"), Vector2(0.8, 1.2))
	layer.height_range = _range(d.get("height"), Vector2(1.0, 1.0)) if layer.kind in ["clump", "flower"] else layer.scale_range
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
	layer.root_color = _color(d.get("root_color"), GrassZones.DEFAULT_ROOT)
	layer.tip_color = _color(d.get("tip_color"), GrassZones.DEFAULT_TIP)
	layer.dry_tint = _color(d.get("dry_tint"), Color(0.70, 0.64, 0.48) if layer.kind == "clump" else Color.WHITE)
	layer.dry_amount = clampf(float(d.get("dry_amount", 0.5 if layer.kind == "clump" else 0.0)), 0.0, 1.0)
	layer.zone_channel = str(d.get("zone", ""))
	if not layer.zone_channel in ["", "grass", "tall", "flowers"]:
		push_error("GrassLayer %s: unknown zone channel '%s'" % [layer.name, layer.zone_channel])
		layer.zone_channel = ""
	for v: Variant in d.get("colors", []):
		if v is String and Color.html_is_valid(v):
			layer.colors.append(Color.html(v))
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
			mesh = GrassMesh.clump(int(d.get("blades", 4)), int(d.get("segments", 3)), float(d.get("blade_width", 0.045)), rng)
			material = GrassMesh.grass_material(fade)
		"flower":
			mesh = GrassMesh.flower(rng)
			material = GrassMesh.grass_material(fade)
			if colors.is_empty():
				colors.append(tip_color)
		"pebble":
			mesh = GrassMesh.pebble(_color(d.get("color"), Color(0.30, 0.29, 0.28)), rng)
			material = GrassMesh.grass_material(fade)
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


## Blades and flowers: the kinds whose vertices the probe counts as blade geometry.
func is_blade() -> bool:
	return kind == "clump" or kind == "flower"


## A pooled MultiMeshInstance3D with every instance slot preallocated: fills only write transforms. The
## grass-shader kinds carry a per-instance colour (tip) as well as custom data (root fraction, wind phase).
func make_instance(slot: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = kind in TINTED_KINDS
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
## multiplier and `exact_slope` is (x, z) -> degrees, asked only for borderline candidates. One call does
## the whole cell; Grass fills in budgeted steps through begin() and step() and ends in the same place.
func fill(key: Vector2i, index: int, seed_v: int, cell: GrassCell, mmi: MultiMeshInstance3D, out: PackedVector3Array, filter: Callable, exact_slope: Callable) -> int:
	begin(key, index, seed_v, cell)
	step(cell, mmi, out, filter, exact_slope, 0)
	return placed


## Starts filling `key`'s cell: seeds the RNG from the key and layer index and sizes the candidate pool.
## `cell` must already be prepared for `key`. Nothing is written until step().
func begin(key: Vector2i, index: int, seed_v: int, cell: GrassCell) -> void:
	_rng.seed = hash(Vector3i(key.x, key.y, index)) ^ seed_v
	var zoned: bool = zone_channel != "" and cell.zones != null
	# A tall or flower layer draws nothing in a cell whose channel is zero everywhere: no candidates, no cost.
	var skip: bool = zoned and ((zone_channel == "tall" and cell.zone_tall_max <= 0.0) or (zone_channel == "flowers" and cell.zone_flowers_max <= 0.0))
	var pool: float = density * (zone_max if zoned and zone_channel == "grass" else 1.0) * cell.size * cell.size
	_candidates = 0 if skip else mini(max_per_cell, ceili(pool))
	_cursor = 0
	placed = 0


## Candidates drawn so far of the cell begun; `step` resumes from here.
func cursor() -> int:
	return _cursor


## Candidates the cell begun will draw in all.
func candidates() -> int:
	return _candidates


## Draws up to `max_candidates` more candidates (0: all that remain) of the cell begun with begin(),
## placing the accepted ones from `placed` on; returns true once the cell is done, when the MultiMesh is
## shown with every placed instance. Candidates are drawn in one fixed order from one RNG stream, so any
## split into steps places exactly what one call would (W8-G2): the budget bounds a step, never the world.
func step(cell: GrassCell, mmi: MultiMeshInstance3D, out: PackedVector3Array, filter: Callable, exact_slope: Callable, max_candidates: int = 0) -> bool:
	var mm: MultiMesh = mmi.multimesh
	var zoned: bool = zone_channel != "" and cell.zones != null
	var tinted: bool = kind in TINTED_KINDS
	var stop: int = _candidates if max_candidates <= 0 else mini(_candidates, _cursor + max_candidates)
	var prof: bool = profile
	if prof:
		_lap_t = Time.get_ticks_usec()
	for _c: int in stop - _cursor:
		# Every draw happens before any early-out so the RNG stream stays aligned whatever is rejected.
		var x: float = cell.origin.x + _rng.randf() * cell.size
		var z: float = cell.origin.y + _rng.randf() * cell.size
		var roll: float = _rng.randf()
		var yaw: float = _rng.randf() * TAU
		var s: float = _rng.randf_range(scale_range.x, scale_range.y)
		var h: float = _rng.randf_range(height_range.x, height_range.y)
		var bright: float = _rng.randf()
		var dry: float = _rng.randf()
		var phase: float = _rng.randf()
		var n: Vector3 = cell.normal(x, z)
		var slope: float = GrassCell.slope_deg(n)
		var d: float = GrassLattice.density_at(slope, cell.height(x, z), cell.water_level, max_slope)
		if prof:
			_lap(Phase.CANDIDATE)
		if d <= 0.0:
			continue
		d *= clampf(1.0 + hollow * cell.hollow, 0.15, 2.5)
		if _patch != null:
			d *= lerpf(patch_min, 1.0, _patch.get_noise_2d(x, z) * 0.5 + 0.5)
		if cluster_radius > 0.0:
			d *= lerpf(1.0, cluster_outside, smoothstep(cluster_radius, cluster_radius + cluster_falloff, cell.nearest_cluster(x, z)))
		if filter.is_valid():
			d *= float(filter.call(x, z))
		if prof:
			_lap(Phase.LAND)
		if zoned:
			cell.zone_at(x, z)
			match zone_channel:
				"grass":
					d *= cell.zone_density
				"tall":
					d *= cell.zone_tall
				"flowers":
					d *= cell.zone_flowers
		if prof:
			_lap(Phase.ZONE)
		if roll >= d:
			continue
		# The grid slope is a 3 m average; near the limit ask the heightfield exactly so the probe's
		# "nothing above max_slope" holds to the degree.
		if slope > max_slope - EXACT_SLOPE_MARGIN and exact_slope.is_valid() and float(exact_slope.call(x, z)) > max_slope:
			if prof:
				_lap(Phase.SLOPE)
			continue
		if prof:
			_lap(Phase.SLOPE)
		if zoned:
			h *= cell.zone_height
		var y: float = float(cell.height_sampler.call(x, z)) - sink * s
		var basis: Basis = GroundPlacement.aligned_basis(n, yaw, align, 1.0) * Basis.from_scale(Vector3(s, h, s))
		var xform: Transform3D = Transform3D(basis, Vector3(x, y, z)) * local
		if prof:
			_lap(Phase.TRANSFORM)
		mm.set_instance_transform(placed, xform)
		if tinted:
			_tint(mm, placed, zoned, cell, bright, dry, phase)
		else:
			mm.set_instance_custom_data(placed, Color(bright, dry, phase, 1.0))
		if prof:
			_lap(Phase.UPLOAD)
		out[placed] = Vector3(x, y, z)
		placed += 1
	_cursor = stop
	if _cursor < _candidates:
		return false
	mm.visible_instance_count = placed
	mmi.visible = placed > 0
	return true


static func _lap(phase: int) -> void:
	var now: int = Time.get_ticks_usec()
	if phase_usec.size() < Phase.COUNT:
		phase_usec.resize(Phase.COUNT)
		phase_usec.fill(0)
	phase_usec[phase] += now - _lap_t
	_lap_t = now


## Instance colour = the tip colour; custom data = the root as a fraction of the tip, and the wind phase.
## Brightness and dry drift are folded in here, per instance, instead of in the shader. A pebble's colour
## is in its mesh, so it only takes the brightness.
func _tint(mm: MultiMesh, i: int, zoned: bool, cell: GrassCell, bright: float, dry: float, phase: float) -> void:
	var shade: float = GrassMesh.SHADE_MIN + GrassMesh.SHADE_RANGE * bright
	if kind == "pebble":
		last_tint = Color(shade, shade, shade, 1.0)
		last_custom = Color(1.0, 1.0, 1.0, phase)
	else:
		if zoned:
			cell.zone_palette()
		var root: Color = cell.zone_root if zoned else root_color
		var tip: Color = cell.zone_tip if zoned else tip_color
		if kind == "flower":
			tip = colors[int(phase * float(colors.size())) % colors.size()]
		var drift: Color = Color.WHITE.lerp(dry_tint, dry * dry_amount) * shade
		root = root * drift
		tip = tip * drift
		last_tint = Color(tip.r, tip.g, tip.b, 1.0)
		last_custom = Color(root.r / maxf(tip.r, 0.001), root.g / maxf(tip.g, 0.001), root.b / maxf(tip.b, 0.001), phase)
	# The colour maths above is building, not uploading: profiled with the transform.
	if profile:
		_lap(Phase.TRANSFORM)
	mm.set_instance_color(i, last_tint)
	mm.set_instance_custom_data(i, last_custom)


static func _range(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


static func _color(v: Variant, fallback: Color) -> Color:
	if v is String and Color.html_is_valid(v):
		return Color.html(v)
	return fallback
