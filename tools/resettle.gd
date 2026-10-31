extends SceneTree
## Finds a legal home for every site that has lost one (W20). Cutting a real bed for the river moved the
## ground under two dozen sites; this asks GroundProbe where each of them could stand instead, ignoring
## the site's own claim on its old spot, and prints the answer for the data files to be edited with.
##
##   GODOTC --headless --script tools/resettle.gd -- --reach 120

const SITE_CLEARANCE := 1.5
const MAX_GROUND_DROP := 1.6


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var reach: float = float(_option(args, "--reach", "120"))
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var hf: Heightfield = Heightfield.from_dict(area)
	var road: PackedVector2Array = GroundProbe.road_of(area)
	var ridge: float = GroundProbe.ridge_limit(area)
	var sites: Array[Dictionary] = SiteRegistry.load_area("vale")
	var masks: Array[KeepOutMask] = []
	var spans: Array[float] = []
	for site: Dictionary in sites:
		var mask := KeepOutMask.new()
		var span: float = 0.0
		# How far the site reaches FROM ITS OWN ORIGIN. world_obbs returns world centres, so the distance
		# has to be taken from the site, not from the middle of the map.
		var home: Vector2 = SiteRegistry.at_of(site)
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			mask.add_obb(obb, SITE_CLEARANCE * 0.5)
			span = maxf(span, ((obb["centre"] as Vector2) - home).length() + Vector2(obb["hx"], obb["hz"]).length())
		masks.append(mask)
		spans.append(span)
	for i: int in sites.size():
		var site: Dictionary = sites[i]
		if str(site.get("layout", "")).contains("bridge") or bool(site.get("fixed", false)):
			continue
		var at: Vector2 = SiteRegistry.at_of(site)
		var trouble: String = ""
		var ground: Vector2 = Settlements.ground_span(site, hf)
		if ground.y - ground.x > MAX_GROUND_DROP:
			trouble += " not_flat"
		if ground.x <= hf.water_level() + 0.5:
			trouble += " in_water"
		if hf.in_river(at.x, at.y, spans[i]):
			trouble += " in_river"
		for j: int in sites.size():
			if j != i and masks[i].overlaps(masks[j]):
				trouble += " overlaps:" + str(sites[j]["id"])
				break
		if trouble == "":
			continue
		# Everyone but this site has a claim on the ground; this one is the thing being moved.
		var others: Array = []
		for j: int in sites.size():
			if j != i:
				others.append(sites[j])
		var footprint: float = maxf(9.0, spans[i] * 2.0)
		var spot: Vector2 = _find_clear(hf, road, others, masks, i, site, at, footprint, reach, ridge)
		if spot == Vector2.INF:
			print("STUCK %s %s  (footprint %.1f m)%s" % [site["id"], at, footprint, trouble])
		else:
			print("MOVE %s %.1f %.1f  # was %.0f,%.0f, moved %.1f m -%s"
					% [site["id"], spot.x, spot.y, at.x, at.y, at.distance_to(spot), trouble])
	quit()


func _option(args: PackedStringArray, name: String, fallback: String) -> String:
	var i: int = args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


## GroundProbe.find, plus the rule it does not have: the suite tests whether two sites' real footprints
## overlap, and GroundProbe only tests whether their centres are 8 m apart. A barn reaches 10 m, so two
## barns 8 m apart pass the tool and fail the suite -- which is how a search returned "moved 0.0 m" for a
## site that was overlapping its neighbour.
static func _find_clear(hf: Heightfield, road: PackedVector2Array, others: Array,
		masks: Array[KeepOutMask], self_i: int, site: Dictionary, want: Vector2,
		footprint: float, reach: float, ridge: float) -> Vector2:
	for step: int in range(0, 40):
		var radius: float = float(step) * reach / 40.0
		var points: int = 1 if step == 0 else maxi(10, int(TAU * radius / 4.0))
		for k: int in points:
			var a: float = TAU * float(k) / float(points)
			var spot: Vector2 = want if step == 0 else want + Vector2(cos(a), sin(a)) * radius
			if not bool(GroundProbe.report(hf, road, others, spot, footprint, ridge)["legal"]):
				continue
			var trial: Dictionary = site.duplicate()
			trial["at"] = [spot.x, spot.y]
			var mask := KeepOutMask.new()
			for obb: Dictionary in SiteRegistry.world_obbs(trial):
				mask.add_obb(obb, SITE_CLEARANCE * 0.5)
			var clash: bool = false
			for j: int in masks.size():
				if j != self_i and mask.overlaps(masks[j]):
					clash = true
					break
			if not clash:
				return spot
	return Vector2.INF
