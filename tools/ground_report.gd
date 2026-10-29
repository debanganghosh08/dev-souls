extends SceneTree
## Command-line placement checker (W10). Says whether a building can stand at a point, and where the
## nearest legal spot is if it cannot. Content work -- laying out a village, a camp, a row of lamps -- is
## data, and this is how that data gets chosen without writing a program for it.
##
## Usage (GODOTC is the console executable, see docs/TOOLS.md):
##
##   GODOTC --headless --script tools/ground_report.gd -- --at 120,-40 --at -60,210
##       check two spots
##   GODOTC --headless --script tools/ground_report.gd -- --find 120,-40 --footprint 12
##       the nearest spot a 12 m structure can stand on
##   GODOTC --headless --script tools/ground_report.gd -- --grid -40,180,40,260 --step 20
##       sweep a rectangle (min x, min z, max x, max z) and print every legal spot in it
##
## Options: --area vale (default), --footprint 9, --reach 40, --legal-only.
## Every spot it calls LEGAL satisfies tests/test_site_placement.gd with a margin; it is a search tool, not
## a substitute for running the suite.

const DEFAULT_AREA := "vale"


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var area_name: String = _option(args, "--area", DEFAULT_AREA)
	var footprint: float = float(_option(args, "--footprint", "9"))
	var reach: float = float(_option(args, "--reach", "40"))
	var legal_only: bool = args.has("--legal-only")
	var path: String = "res://data/areas/%s.json" % area_name
	if not FileAccess.file_exists(path):
		print("no such area: %s" % path)
		quit(1)
		return
	var area: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var hf: Heightfield = Heightfield.from_dict(area)
	var road: PackedVector2Array = GroundProbe.road_of(area)
	var taken: Array = SiteRegistry.load_area(area_name)
	var ridge: float = GroundProbe.ridge_limit(area)
	print("area=%s sites=%d footprint=%.1f m  water=%.2f" % [area_name, taken.size(), footprint, hf.water_level()])
	print("       x        z   ground   drop     road  nearest site      verdict")
	var printed: int = 0
	for i: int in range(args.size()):
		match args[i]:
			"--at":
				var at: Vector2 = _point(args, i + 1)
				print(GroundProbe.line(GroundProbe.report(hf, road, taken, at, footprint, ridge)))
				printed += 1
			"--find":
				var want: Vector2 = _point(args, i + 1)
				var spot: Vector2 = GroundProbe.find(hf, road, taken, want, footprint, reach, 8, ridge)
				if spot == Vector2.INF:
					print("  no legal ground within %.0f m of (%.1f, %.1f)" % [reach, want.x, want.y])
				else:
					print(GroundProbe.line(GroundProbe.report(hf, road, taken, spot, footprint, ridge))
							+ "  moved %.1f m" % spot.distance_to(want))
				printed += 1
			"--grid":
				var box: PackedFloat32Array = _box(args, i + 1)
				var step: float = float(_option(args, "--step", "20"))
				var legal: int = 0
				var x: float = box[0]
				while x <= box[2]:
					var z: float = box[1]
					while z <= box[3]:
						var row: Dictionary = GroundProbe.report(hf, road, taken, Vector2(x, z), footprint, ridge)
						if bool(row["legal"]):
							legal += 1
						if bool(row["legal"]) or not legal_only:
							print(GroundProbe.line(row))
						z += step
					x += step
				print("  %d legal spots in that rectangle" % legal)
				printed += 1
	if printed == 0:
		print("nothing asked. Try: -- --at 120,-40   or   -- --find 120,-40   or   -- --grid -40,180,40,260")
	quit(0)


func _option(args: PackedStringArray, name: String, fallback: String) -> String:
	var at: int = args.find(name)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


func _point(args: PackedStringArray, index: int) -> Vector2:
	if index >= args.size():
		return Vector2.ZERO
	var parts: PackedStringArray = args[index].split(",")
	return Vector2(float(parts[0]), float(parts[1]) if parts.size() > 1 else 0.0)


func _box(args: PackedStringArray, index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if index >= args.size():
		return out
	var parts: PackedStringArray = args[index].split(",")
	for i: int in range(mini(4, parts.size())):
		out[i] = float(parts[i])
	return out
