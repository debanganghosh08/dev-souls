extends SceneTree
## The suite's site rules, on demand (W20). test_site_placement.gd is the authority, but it only runs
## inside a four-minute suite, and moving two dozen sites out of a new river bed needs the answer in
## seconds. Same rules, same numbers, read from the same registry.

const SITE_CLEARANCE := 1.5
const MAX_GROUND_DROP := 1.6
const RIDGE_CLEARANCE := 25.0


func _init() -> void:
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var hf: Heightfield = Heightfield.from_dict(area)
	var sites: Array[Dictionary] = SiteRegistry.load_area("vale")
	var bad: int = 0
	var masks: Array[KeepOutMask] = []
	for site: Dictionary in sites:
		var mask := KeepOutMask.new()
		for obb: Dictionary in SiteRegistry.world_obbs(site):
			mask.add_obb(obb, SITE_CLEARANCE * 0.5)
		masks.append(mask)
		# Fixed sites stand on ground the terrain was shaped for (the Hearth crypt is under the pond, and
		# the suite exempts it too); a crossing stands over a gap, which is what makes it a crossing.
		if _is_crossing(site) or bool(site.get("fixed", false)):
			continue
		var span: Vector2 = Settlements.ground_span(site, hf)
		if span.y - span.x > MAX_GROUND_DROP:
			print("  NOT FLAT   %-24s ground falls %.2f m (limit %.1f)" % [site["id"], span.y - span.x, MAX_GROUND_DROP])
			bad += 1
		if span.x <= hf.water_level() + 0.5:
			print("  IN WATER   %-24s lowest %.2f" % [site["id"], span.x])
			bad += 1
		if hf.in_river(float((site["at"] as Array)[0]), float((site["at"] as Array)[1]), 1.0):
			print("  IN RIVER   %-24s" % site["id"])
			bad += 1
		if SiteRegistry.at_of(site).length() >= hf.ridge_inner_radius() - RIDGE_CLEARANCE:
			print("  PAST RIM   %-24s %.1f m out" % [site["id"], SiteRegistry.at_of(site).length()])
			bad += 1
	for i: int in range(sites.size()):
		for j: int in range(i + 1, sites.size()):
			if masks[i].overlaps(masks[j]):
				print("  OVERLAP    %-24s and %s" % [sites[i]["id"], sites[j]["id"]])
				bad += 1
	print("%d sites checked, %d problems" % [sites.size(), bad])
	quit(0 if bad == 0 else 1)


static func _is_crossing(site: Dictionary) -> bool:
	return str(site.get("layout", "")).contains("bridge")
