extends SceneTree
# Throwaway: picks the 20 house anchors from the real terrain. For each slot, searches within `r` of its target
# for the spot whose 12 x 12 m square has the smallest height range, subject to the placement rules.
const SLOTS := [
	["R1", "cottage", "maren_cottage", 85, 115, 35], ["R1", "shack", "fisher_shack", -95, -40, 45],
	["R1", "shrine", "pond_shrine", -70, 25, 30], ["R2", "cottage", "road_cottage", -135, 115, 30],
	["R3", "cottage", "outskirt_cottage_n", -230, 60, 35], ["R3", "cottage", "outskirt_cottage_s", -150, 215, 35],
	["R3", "shack", "village_shack", -285, 150, 35], ["R3", "barn", "village_barn", -120, 190, 35],
	["R4", "barn", "farm_barn_w", -250, -60, 45], ["R4", "barn", "farm_barn_s", -150, -185, 45],
	["R4", "cottage", "farmhouse", -205, -135, 40], ["R4", "shack", "orchard_shack", -95, -130, 40],
	["R5", "watch", "north_watch", 10, -290, 60], ["R5", "shack", "shepherd_shack", -95, -260, 45],
	["R6", "watch", "castle_foot_watch", 120, -45, 35], ["R6", "shrine", "east_road_shrine", 55, -15, 30],
	["R7", "shack", "woodcutter_shack", 300, 40, 50], ["R7", "watch", "east_ridge_watch", 330, -70, 45],
	["R8", "shack", "hermit_shack", 80, 285, 50], ["R9", "shrine", "edge_shrine", -255, -245, 40],
]
func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/areas/vale.json"))
	var hf: Heightfield = Heightfield.from_dict(data)
	var road := PackedVector2Array()
	for p: Variant in data["valley"]["waypoints"]:
		road.append(Vector2(float(p[0]), float(p[1])))
	var spawn: Vector3 = hf.spawn_point()
	var mask: KeepOutMask = SiteRegistry.keep_out("vale", 0.3)
	var chosen: Array[Vector2] = []
	for s: Array in SLOTS:
		var target := Vector2(s[3], s[4])
		var best := Vector2.INF
		var best_score: float = INF
		var x: float = target.x - s[5]
		while x <= target.x + s[5]:
			var z: float = target.y - s[5]
			while z <= target.y + s[5]:
				var p := Vector2(x, z)
				z += 3.0
				if p.distance_to(target) > s[5] or p.length() > hf.ridge_inner_radius() - 45.0:
					continue
				if p.distance_to(Vector2(spawn.x, spawn.z)) < 25.0 or mask.blocks_near(p.x, p.y, 14.0):
					continue
				var dr: float = INF
				for i: int in range(road.size() - 1):
					dr = minf(dr, p.distance_to(Geometry2D.get_closest_point_to_segment(p, road[i], road[i + 1])))
				if dr < 14.0:
					continue
				var crowd: bool = false
				for c: Vector2 in chosen:
					crowd = crowd or p.distance_to(c) < 40.0
				if crowd:
					continue
				var lo: float = INF
				var hi: float = -INF
				for i: int in range(-3, 4):
					for j: int in range(-3, 4):
						var h: float = hf.height_at(p.x + i * 2.0, p.y + j * 2.0)
						lo = minf(lo, h)
						hi = maxf(hi, h)
				if lo < hf.water_level() + 1.0:
					continue
				# Watch huts want height (a view); everything else wants flat ground.
				var score: float = (hi - lo) - (hf.height_at(p.x, p.y) * 0.08 if s[1] == "watch" else 0.0)
				if score < best_score:
					best_score = score
					best = p
		if best == Vector2.INF:
			print("ANCHOR %s %s %s NONE" % [s[0], s[1], s[2]])
			continue
		chosen.append(best)
		var lo2: float = INF
		var hi2: float = -INF
		for i: int in range(-3, 4):
			for j: int in range(-3, 4):
				var h: float = hf.height_at(best.x + i * 2.0, best.y + j * 2.0)
				lo2 = minf(lo2, h)
				hi2 = maxf(hi2, h)
		print("ANCHOR %s %-8s %-20s at=[%.0f, %.0f] h=%.1f drop12m=%.2f" % [s[0], s[1], s[2], best.x, best.y, hf.height_at(best.x, best.y), hi2 - lo2])
	print("SPAWN %.1f %.1f  water=%.1f" % [spawn.x, spawn.z, hf.water_level()])
	quit(0)
