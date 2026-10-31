extends "res://tests/test_case.gd"
## Pure tests for GrassZones (W8-G): the owner's complaint -- "there is literally no grass" on the castle
## hill, "consistent grass everywhere" -- as numbers. Samples the zone data on a grid over the real vale
## heightfield with the real keep-out mask, no scene and no renderer. The density here is the zones' own
## function; in the game GrassCell samples it on a 3 m grid per cell and the layers roll against it, so
## the live counts are in the vale probe (tests/test_ground_cover.gd, test_grass_sprint.gd). What none of
## this proves is how it looks: every palette is UNVERIFIED until the owner sees a frame.

const VALE := "res://data/areas/vale.json"
const ZONES := "res://data/grass/zones_vale.json"
const VALE_SCRIPT := "res://scenes/levels/vale.gd"
const STEP := 5.0
## The player's floor_max_angle: "walkable" is the player's word, not the grass layer's slope limit.
const WALK_SLOPE := 45.0
const KEEP_OUT_MARGIN := 0.3
## Half the road plus its feather: a point farther off than this is "off-road".
const ROAD_EDGE := 6.5
const CELL := 12.0

var _hf: Heightfield
var _zones: GrassZones
var _keep_out: KeepOutMask
var _limit: float = 0.0


func setup() -> void:
	_hf = Heightfield.from_dict(Terrain.load_data(VALE))
	_zones = GrassZones.load_file(ZONES, _hf)
	_keep_out = SiteRegistry.keep_out("vale", KEEP_OUT_MARGIN)
	var margin: float = float((load(VALE_SCRIPT) as GDScript).get_script_constant_map().get("GRASS_RIDGE_MARGIN", 30.0))
	_limit = _hf.ridge_inner_radius() - margin


## Grid points a player can stand on and grass may grow on: inside the ridge margin, dry by the shore
## band, walkable, unbuilt and off the road; optionally only within a ring round `centre`.
func _open_points(centre: Vector2 = Vector2.ZERO, r0: float = 0.0, r1: float = INF) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = ceili(_limit / STEP)
	for j: int in range(-n, n + 1):
		for i: int in range(-n, n + 1):
			var p := Vector2(float(i) * STEP, float(j) * STEP)
			if p.length() > _limit:
				continue
			var d: float = p.distance_to(centre)
			if d < r0 or d > r1:
				continue
			if _hf.height_at(p.x, p.y) < _hf.water_level() + GrassLattice.SHORE_BAND or _hf.slope_at(p.x, p.y) > WALK_SLOPE:
				continue
			if _keep_out.blocks(p.x, p.y) or _zones.road_distance(p.x, p.y) <= ROAD_EDGE:
				continue
			out.append(p)
	return out


func _coverage(zones: GrassZones, points: PackedVector2Array, at_least: float) -> float:
	var ok: int = 0
	for p: Vector2 in points:
		if zones.density_at(p.x, p.y) >= at_least:
			ok += 1
	return float(ok) / float(maxi(1, points.size()))


func _mean_density(zones: GrassZones, points: PackedVector2Array) -> float:
	var total: float = 0.0
	for p: Vector2 in points:
		total += zones.density_at(p.x, p.y)
	return total / float(maxi(1, points.size()))


func _plateau(name: String) -> Dictionary:
	for site: Dictionary in _hf.plateaus():
		if site["name"] == name:
			return site
	return {}


func test_at_least_ninety_percent_of_open_ground_gets_at_least_half_the_meadow_density() -> void:
	assert_not_null(_zones, "the vale zones load")
	var points: PackedVector2Array = _open_points()
	assert_true(points.size() > 10000, "the grid covers the valley (%d points)" % points.size())
	var fraction: float = _coverage(_zones, points, 0.5)
	assert_true(fraction >= 0.90, "%.1f%% of dry, walkable, unbuilt, off-road ground gets at least half the meadow density (need 90%%)" % (fraction * 100.0))
	var bare: int = 0
	for p: Vector2 in points:
		if _zones.density_at(p.x, p.y) <= 0.0:
			bare += 1
	assert_eq(bare, 0, "no open point is bare: every walkable surface grows grass unless built, wet or a road")
	# Negative control (D-014): the same measure on a thinned meadow must fail, or the number proves nothing.
	var thinned: Dictionary = Terrain.load_data(ZONES).duplicate(true)
	(thinned["zones"][0] as Dictionary)["density"] = 0.3
	var control: float = _coverage(GrassZones.from_dict(thinned, _hf), points, 0.5)
	assert_true(control < 0.90, "a 0.3x meadow fails the same measure (%.1f%%)" % (control * 100.0))


func test_the_castle_hill_skirt_averages_tall_meadow_where_the_old_rule_grew_nothing() -> void:
	var castle: Dictionary = _plateau("castle")
	assert_false(castle.is_empty(), "the castle plateau is in the area data")
	var r: float = float(castle["radius"])
	var points: PackedVector2Array = _open_points(castle["centre"], r, r + float(castle["blend"]))
	assert_true(points.size() > 500, "the skirt ring has open ground to sample (%d points)" % points.size())
	var mean: float = _mean_density(_zones, points)
	assert_true(mean >= 1.2, "the castle hill skirt averages %.2fx meadow (need 1.2x)" % mean)
	var lowest: float = INF
	var tall_total: float = 0.0
	for p: Vector2 in points:
		_zones.sample(p.x, p.y)
		lowest = minf(lowest, _zones.density)
		tall_total += _zones.tall
	assert_true(lowest >= 0.4, "nowhere on the open skirt is thinner than 0.4x (lowest %.2f)" % lowest)
	assert_true(tall_total / float(points.size()) >= 0.7, "most of the skirt asks for the tall-grass layer (%.2f)" % (tall_total / float(points.size())))
	# The rule this replaces (D-022): zero on the plateau, ramping up over the first half of the blend, so the
	# rim of the hill was bare and the ring as a whole well below meadow.
	var old_total: float = 0.0
	var old_rim: float = 0.0
	var rim: int = 0
	for p: Vector2 in points:
		var f: float = GrassLattice.site_factor(p.x, p.y, _hf.plateaus())
		old_total += f
		if p.distance_to(castle["centre"]) < r + 10.0:
			old_rim += f
			rim += 1
	assert_true(rim > 20, "the first 10 m of the skirt has open ground (%d points)" % rim)
	assert_true(old_rim / float(maxi(1, rim)) < 0.3, "the old plateau factor left the rim nearly bare (%.2f)" % (old_rim / float(maxi(1, rim))))
	assert_true(old_total / float(points.size()) < 1.0 and old_total / float(points.size()) < mean, "the old plateau factor averaged %.2f over the same ring, below meadow and below the new %.2f" % [old_total / float(points.size()), mean])


func test_the_road_is_nearly_bare_in_the_middle_and_blends_out_over_a_few_metres() -> void:
	# A point on the west road well clear of the pond's shore ring and of the village top.
	var a := Vector2(-200.0, 140.0)
	var b := Vector2(-90.0, 70.0)
	var mid: Vector2 = a.lerp(b, 0.5)
	var across: Vector2 = (b - a).normalized().orthogonal()
	assert_true(_zones.road_distance(mid.x, mid.y) < 0.01, "the midpoint is on the road's centre line")
	# A worn track, not scoured earth: the ruts still carry a little grass (W9-G).
	assert_true(_zones.density_at(mid.x, mid.y) <= 0.2, "the road's middle is worn down to a track (%.3f)" % _zones.density_at(mid.x, mid.y))
	for sign_v: float in [-1.0, 1.0]:
		var last: float = -1.0
		for k: int in 17:
			var p: Vector2 = mid + across * sign_v * float(k) * 0.5
			var d: float = _zones.density_at(p.x, p.y)
			assert_true(d >= last - 0.02, "density never falls walking off the road (%.3f after %.3f at %.1f m)" % [d, last, float(k) * 0.5])
			last = d
		var edge: Vector2 = mid + across * sign_v * 8.0
		assert_true(_zones.density_at(edge.x, edge.y) >= 0.8, "8 m off the road the meadow is back (%.2f)" % _zones.density_at(edge.x, edge.y))
		_zones.sample(edge.x, edge.y)
		var meadow_tip: Color = _zones.tip
		_zones.sample(mid.x, mid.y)
		assert_true(_zones.tip.get_luminance() < meadow_tip.get_luminance() or _zones.tip.h != meadow_tip.h, "the trampled palette differs from the meadow's")
		assert_true(_zones.tall <= 0.001 and _zones.flowers <= 0.001, "no tall grass or flowers on the road")


func test_settlements_are_short_and_trampled_and_the_hilltops_and_ridge_foot_pale_and_sparse() -> void:
	for name: String in ["village", "castle"]:
		var site: Dictionary = _plateau(name)
		var p: Vector2 = (site["centre"] as Vector2) + Vector2(0.0, 25.0)
		assert_true(_zones.road_distance(p.x, p.y) > ROAD_EDGE, "%s sample point is off the road" % name)
		_zones.sample(p.x, p.y)
		# W9-G: trampled, not bald. The owner asked for grass everywhere and consistent; a settlement still
		# reads as walked-over because it is thinner and shorter than the meadow, not because it is bare.
		assert_true(absf(_zones.density - 0.7) < 0.03, "%s interior is about 0.7x (%.2f)" % [name, _zones.density])
		assert_true(_zones.height < 0.9, "%s interior grass is short (%.2f)" % [name, _zones.height])
		assert_true(_zones.tall <= 0.001 and _zones.flowers <= 0.001, "%s interior has no tall grass or flowers" % name)
	_zones.sample(0.0, 150.0)
	var meadow_density: float = _zones.density
	assert_true(absf(meadow_density - 1.0) < 0.001 or absf(meadow_density - 1.4) < 0.001 or (meadow_density > 1.0 and meadow_density < 1.4), "open meadow is between 1.0x and a tall patch's 1.4x (%.2f)" % meadow_density)
	var top: Vector2 = Vector2.ZERO
	var top_h: float = -INF
	for x: int in range(-130, 81, 5):
		for z: int in range(-380, -229, 5):
			if Vector2(x, z).length() < _limit and _hf.height_at(x, z) > top_h:
				top_h = _hf.height_at(x, z)
				top = Vector2(x, z)
	# W20 cut a real bed for the river through this box and took 1.4 m off the highest ground in it, so a
	# shoulder was raised on the north bank to carry the hilltop band -- and because the owner asked for a
	# cut hill beside the widest water.
	assert_true(top_h >= 7.5, "the north hills have a summit above the hilltop band (%.1f m at %s)" % [top_h, top])
	_zones.sample(top.x, top.y)
	assert_true(absf(_zones.density - 0.85) < 0.03, "the summit is thinner than the meadow, not bare (%.2f)" % _zones.density)
	var hilltop_palette: Color = _zone_tip("north_hilltops")
	var meadow_palette: Color = _zone_tip("meadow")
	assert_true(hilltop_palette.get_luminance() > meadow_palette.get_luminance(),
		"the hilltop palette is drier than the meadow's (%.3f against %.3f)"
		% [hilltop_palette.get_luminance(), meadow_palette.get_luminance()])
	assert_true(_zones.tall <= 0.001, "no tall grass on the summit")
	_zones.sample(-370.0, 0.0)
	assert_true(absf(_zones.density - 0.85) < 0.03, "the ridge foot is thinner than the meadow (%.2f)" % _zones.density)
	var ridge_palette: Color = _zone_tip("ridge_foot")
	assert_true(ridge_palette.get_luminance() > _zone_tip("meadow").get_luminance(),
		"the ridge foot palette is drier than the meadow's (%.3f against %.3f)"
		% [ridge_palette.get_luminance(), _zone_tip("meadow").get_luminance()])
	_zones.sample(60.0, 300.0)
	assert_true(_zones.flowers >= 0.99, "the south meadows are full of wildflowers (%.2f)" % _zones.flowers)
	assert_true(_zones.tip.g > _zones.tip.r, "the south meadow tip is green, not gold")
	_zones.sample(0.0, 58.0)
	assert_true(absf(_zones.density - 0.9) < 0.03, "the pond shore is 0.9x (%.2f)" % _zones.density)


func test_tints_drift_across_the_valley_but_stay_sane_and_deterministic() -> void:
	var twin: GrassZones = GrassZones.load_file(ZONES, _hf)
	var tips: Array[Color] = []
	var lowest: float = INF
	var highest: float = -INF
	for x: int in range(-350, 351, 50):
		for z: int in range(-350, 351, 50):
			if Vector2(x, z).length() > _limit:
				continue
			_zones.sample(x, z)
			var tip: Color = _zones.tip
			var root: Color = _zones.root
			for c: float in [tip.r, tip.g, tip.b, root.r, root.g, root.b]:
				assert_false(is_nan(c), "no channel is NaN at (%d, %d)" % [x, z])
				lowest = minf(lowest, c)
				highest = maxf(highest, c)
			assert_true(tip.get_luminance() > root.get_luminance() * 1.5, "the tip is paler than the root at (%d, %d)" % [x, z])
			assert_eq(twin.tint_at(x, z), tip, "a second GrassZones from the same data agrees at (%d, %d)" % [x, z])
			assert_eq(twin.density_at(x, z), _zones.density_at(x, z), "and on density at (%d, %d)" % [x, z])
			tips.append(tip)
	assert_true(lowest >= 0.0 and highest <= 1.0, "every channel stays in 0..1 (%.2f..%.2f)" % [lowest, highest])
	var distinct: int = 0
	for i: int in tips.size() - 1:
		if absf(tips[i].r - tips[i + 1].r) + absf(tips[i].g - tips[i + 1].g) + absf(tips[i].b - tips[i + 1].b) > 0.01:
			distinct += 1
	assert_true(distinct > tips.size() / 2, "neighbouring fields differ in shade (%d of %d pairs)" % [distinct, tips.size() - 1])


func test_degenerate_input_and_the_zone_table() -> void:
	for v: float in [GrassZones.new().density_at(NAN, 1.0), _zones.density_at(NAN, 1.0), _zones.density_at(1.0, INF)]:
		assert_true(is_zero_approx(v), "NaN or infinite input grows nothing (%s)" % v)
	var tint: Color = _zones.tint_at(NAN, NAN)
	assert_false(is_nan(tint.r) or is_nan(tint.g) or is_nan(tint.b), "a degenerate point still has a sane tint")
	var w: Dictionary = _zones.weights(0.0, 150.0)
	assert_eq(_zones.zone_names().size(), 11, "the vale has eleven zones")
	assert_true(is_equal_approx(float(w["meadow"]), 1.0), "the meadow is the base everywhere")
	for name: String in w:
		assert_true(float(w[name]) >= 0.0 and float(w[name]) <= 1.0, "weight of %s is 0..1 (%s)" % [name, w[name]])
	assert_true(is_equal_approx(_zones.max_density(), 1.4), "the densest zone is 1.4x (%.2f)" % _zones.max_density())
	# (A missing file yields null through Terrain.load_data's push_error; not exercised here so the suite
	# output stays free of ERROR lines.)
	var empty: GrassZones = GrassZones.from_dict({}, _hf)
	assert_true(is_equal_approx(empty.density_at(10.0, 10.0), 1.0), "no zones at all is plain meadow")
	assert_true(is_inf(empty.road_distance(0.0, 0.0)) or empty.road_distance(0.0, 0.0) >= 0.0, "a road from the area's valley or none")


func test_zoned_layers_grow_only_where_their_channel_asks_and_take_the_zone_palette() -> void:
	# A synthetic area with no heightfield: meadow everywhere, and east of x = 100 a golden tall zone.
	var data: Dictionary = {"seed": 7, "zones": [
		{"name": "meadow", "shape": {"type": "base"}, "density": 1.0, "height": 1.0, "tall": 0.0, "flowers": 0.0, "root": "#2f3a1e", "tip": "#9a9a52"},
		{"name": "gold", "shape": {"type": "rect", "min": [100, -1000], "max": [1000, 1000], "feather": 1.0}, "density": 1.4, "height": 1.2, "tall": 1.0, "flowers": 1.0, "root": "#3a3a1c", "tip": "#c9a94f"},
	]}
	var zones: GrassZones = GrassZones.from_dict(data, null)
	assert_true(is_equal_approx(zones.density_at(50.0, 0.0), 1.0) and is_equal_approx(zones.density_at(150.0, 0.0), 1.4), "the synthetic zones paint as written")
	var flat: Callable = func(_x: float, _z: float) -> float: return 2.0
	var grass: GrassLayer = GrassLayer.from_dict({"name": "grass", "kind": "clump", "zone": "grass", "density": 1.0, "max_per_cell": 220, "patch_min": 1.0}, 1, 0)
	var tall: GrassLayer = GrassLayer.from_dict({"name": "tall", "kind": "clump", "zone": "tall", "density": 0.4, "max_per_cell": 60, "patch_min": 1.0, "height": [0.8, 1.2]}, 1, 1)
	var flowers: GrassLayer = GrassLayer.from_dict({"name": "flowers", "kind": "flower", "zone": "flowers", "density": 0.05, "max_per_cell": 12, "patch_min": 1.0, "colors": ["#e3c54a", "#ece6d2", "#8d74c6"]}, 1, 2)
	for layer: GrassLayer in [grass, tall, flowers]:
		layer.zone_max = zones.max_density()
		assert_true(layer.usable(), "%s builds without a scene" % layer.name)
	var cell := GrassCell.new()
	var counts: Dictionary = {}
	var colors: Dictionary = {}
	for key: Vector2i in [Vector2i(0, 0), Vector2i(10, 0)]:
		cell.prepare(key, CELL, flat, -5.0, PackedVector3Array(), 0.0, zones)
		for layer: GrassLayer in [grass, tall, flowers]:
			var mmi: MultiMeshInstance3D = layer.make_instance(0)
			var out := PackedVector3Array()
			out.resize(layer.max_per_cell)
			var n: int = layer.fill(key, 0, 1, cell, mmi, out, Callable(), Callable())
			counts[[layer.name, key]] = n
			if n > 0:
				# The headless renderer discards what the MultiMesh is given, so read the layer's CPU-side record.
				colors[[layer.name, key]] = layer.last_tint
				var custom: Color = layer.last_custom
				assert_true(custom.r > 0.0 and custom.r < 1.0 and custom.g < 1.0 and custom.b < 1.0, "%s root is darker than its tip (%s)" % [layer.name, custom])
				assert_true(custom.a >= 0.0 and custom.a <= 1.0, "wind phase is 0..1")
				assert_true(layer.last_tint.r > 0.0 and layer.last_tint.g > 0.0, "%s was tinted (%s)" % [layer.name, layer.last_tint])
			mmi.free()
	assert_eq(int(counts[["tall", Vector2i(0, 0)]]), 0, "no tall grass in the meadow cell")
	assert_eq(int(counts[["flowers", Vector2i(0, 0)]]), 0, "no flowers in the meadow cell")
	assert_true(int(counts[["tall", Vector2i(10, 0)]]) > 30, "tall grass fills the golden cell (%d)" % int(counts[["tall", Vector2i(10, 0)]]))
	assert_true(int(counts[["flowers", Vector2i(10, 0)]]) > 2, "flowers grow in the golden cell (%d)" % int(counts[["flowers", Vector2i(10, 0)]]))
	var meadow_n: int = counts[["grass", Vector2i(0, 0)]]
	var gold_n: int = counts[["grass", Vector2i(10, 0)]]
	assert_true(meadow_n > CELL * CELL * 0.8, "the meadow cell grows about its 1.0x density (%d)" % meadow_n)
	assert_true(float(gold_n) > float(meadow_n) * 1.25, "the 1.4x cell grows well more than the meadow cell (%d vs %d)" % [gold_n, meadow_n])
	var meadow_c: Color = colors[["grass", Vector2i(0, 0)]]
	var gold_c: Color = colors[["grass", Vector2i(10, 0)]]
	assert_ne(meadow_c, gold_c, "the two cells' blades are tinted differently")
	assert_true(gold_c.r > gold_c.g and gold_c.r > meadow_c.r, "the golden cell's tip leans red-gold (%s vs %s)" % [gold_c, meadow_c])
	var petal: Color = colors[["flowers", Vector2i(10, 0)]]
	assert_true(petal.get_luminance() > 0.3, "a flower head is a bright speck (%s)" % petal)
	var mesh: ArrayMesh = GrassMesh.flower(RandomNumberGenerator.new())
	var uv2: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	var uv: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	assert_eq(GrassMesh.vertex_count(mesh), 14, "a flower is a stalk of six vertices and two crossed quads")
	assert_true(is_zero_approx(uv2[0].y) and is_equal_approx(uv2[13].y, 1.0), "colour runs stalk to petal along UV2.y")
	assert_true(uv[13].y < 0.6, "the head bends less than a blade tip (mask %.2f)" % uv[13].y)


## A zone's own tip colour, straight out of the data file. GrassZones adds a slow colour drift to every
## sample so that a field is never one flat colour; that drift is wider than any hill, so the only
## honest way to compare two palettes is to compare the palettes.
func _zone_tip(name: String) -> Color:
	var doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/grass/zones_vale.json"))
	for raw: Variant in doc.get("zones", []):
		var zone: Dictionary = raw
		if str(zone.get("name", "")) == name:
			return Color(str(zone["tip"]))
	return Color.BLACK
