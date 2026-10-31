extends SceneTree
## Walks a water body and says, at every step, how deep it actually is (W19b). The owner filmed a river
## that reads as a wet smear with gaps in it, and no test could have caught that: the suite checks that a
## surface exists and that the volume drowns you, not that there is any water under your feet.
##
##   GODOTC --headless --script tools/river_report.gd -- --area vale --step 12

const DEFAULT_AREA := "vale"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var area_name: String = _option(args, "--area", DEFAULT_AREA)
	var step: float = float(_option(args, "--step", "12"))
	var area: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/areas/%s.json" % area_name))
	var hf: Heightfield = Heightfield.from_dict(area)
	for raw: Variant in area.get("waters", []):
		var body: Dictionary = raw
		var points := PackedVector2Array()
		var levels := PackedFloat32Array()
		for p: Variant in body.get("points", []):
			var row: Array = p
			points.append(Vector2(float(row[0]), float(row[1])))
			levels.append(float(row[2]) if row.size() > 2 else NAN)
		if points.size() < 2:
			continue
		var walked: PackedVector2Array = Water.walk(points, step)
		var walked_levels: PackedFloat32Array = Water._levels_along(
				points, levels, walked, float(body.get("level", 0.0)))
		var half: float = float(body.get("half_width", 7.0))
		print("\n%s  half=%.1f m  %d steps" % [body.get("name", "?"), half, walked.size()])
		print("      x       z   surface     bed   depth   bank_l  bank_r   gorge  verdict")
		var dry: int = 0
		var shallow: int = 0
		for i: int in walked.size():
			var at: Vector2 = walked[i]
			var surface: float = walked_levels[i]
			# The bed under the middle of the channel, and the ground at each bank.
			var dir: Vector2 = (walked[mini(i + 1, walked.size() - 1)] - walked[maxi(i - 1, 0)]).normalized()
			var side := Vector2(-dir.y, dir.x)
			var bed: float = hf.height_at(at.x, at.y)
			# The bank is the ground at the TOP of the cut, not at the edge of the flat bed: `reach` out
			# from the line is where the cut has finished sloping back up to the land it found.
			var reach: float = hf.reach_of_cuts() + 2.0
			var bank_l: float = hf.height_at(at.x + side.x * reach, at.y + side.y * reach)
			var bank_r: float = hf.height_at(at.x - side.x * reach, at.y - side.y * reach)
			var depth: float = surface - bed
			var verdict: String = "ok"
			if depth <= 0.0:
				verdict = "DRY (bed above the surface)"
				dry += 1
			elif depth < 0.8:
				verdict = "SHALLOW"
				shallow += 1
			# A bank below the surface means the water should be spilling out sideways instead of running.
			if minf(bank_l, bank_r) < surface:
				verdict += " SPILLS"
			print("%7.1f %7.1f  %8.2f %7.2f %7.2f  %7.2f %7.2f  %6.1f  %s"
					% [at.x, at.y, surface, bed, depth, bank_l, bank_r,
					minf(bank_l, bank_r) - surface, verdict])
		print("  %d of %d steps dry, %d shallow (under 0.8 m)" % [dry, walked.size(), shallow])
	quit()


func _option(args: PackedStringArray, name: String, fallback: String) -> String:
	var i: int = args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback
