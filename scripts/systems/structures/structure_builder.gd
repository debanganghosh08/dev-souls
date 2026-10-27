class_name StructureBuilder
extends Node3D
## Builds a structure from a layout file in data/structures/: every entry names a kit piece, its parameters
## and where it stands (local metres, yaw and tilt in degrees). Entries with a `repeat` list become one
## MultiMesh and one body (D-013: identical pieces are instanced, never duplicated). Layouts are data, so the
## lead can move a wall by editing JSON; nothing here knows what a castle is. build() is public because the
## test runner never enters a tree, so _ready never fires there.

@export_file("*.json") var layout_path: String = ""
## Pieces built from one layout file are identical every time it is placed, so with this on their meshes and
## collision shapes are built once per run and reused by every placement of that layout. Settlements turns it
## on: twenty houses from five archetypes cost five sets of meshes, not twenty. Off by default so the castle,
## the village and every test keep building their own exactly as before.
@export var share_pieces: bool = false

static var _shared: Dictionary = {}

var _built: bool = false
var _layout: Dictionary = {}
var _stats: Dictionary = {}
var _groups: Dictionary = {}


func _ready() -> void:
	if not _built:
		build()


func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_built = true
	_stats = {"pieces": 0, "meshes": 0, "multimeshes": 0, "instances": 0, "colliders": 0, "verts": 0}
	_groups = {}
	_layout = load_layout(layout_path)
	var entries: Array = _layout.get("pieces", [])
	for i: int in range(entries.size()):
		if entries[i] is Dictionary:
			_spawn(entries[i], i)


func is_built() -> bool:
	return _built


func layout() -> Dictionary:
	return _layout


func stats() -> Dictionary:
	return _stats.duplicate()


## Distinct group names starting with prefix (a village counts its shacks this way).
func group_names(prefix: String = "") -> Array[String]:
	var out: Array[String] = []
	for name: String in _groups:
		if name.begins_with(prefix):
			out.append(name)
	out.sort()
	return out


## Farthest any piece reaches from the structure's origin on the ground plane: checked against the plateau
## radius in data/areas/vale.json so a structure fits the flattened site it was designed for.
func footprint_radius() -> float:
	var best: float = 0.0
	for entry: Variant in _layout.get("pieces", []):
		if not entry is Dictionary:
			continue
		var params: Dictionary = entry.get("params", {})
		var extent: float = maxf(maxf(_f(params, "w", 0.0), _f(params, "d", 0.0)), 2.0 * _f(params, "radius", 0.0))
		extent = maxf(extent, _f(params, "rise", 0.0) * 1.4) * 0.5
		for placement: Transform3D in placements_of(entry):
			best = maxf(best, Vector2(placement.origin.x, placement.origin.z).length() + extent)
	return best


static func load_layout(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		push_error("StructureBuilder: layout %s missing" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("StructureBuilder: %s is not a valid JSON object" % path)
		return {}
	return json.data


## [x, y, z], [x, y, z, yaw_deg] or [x, y, z, yaw_deg, tilt_deg]; tilt leans the piece about its own X axis.
static func placement(entry: Array) -> Transform3D:
	if entry.size() < 3:
		return Transform3D.IDENTITY
	var basis := Basis(Vector3.UP, deg_to_rad(float(entry[3]) if entry.size() > 3 else 0.0))
	if entry.size() > 4:
		basis = basis * Basis(Vector3.RIGHT, deg_to_rad(float(entry[4])))
	return Transform3D(basis, Vector3(float(entry[0]), float(entry[1]), float(entry[2])))


static func placements_of(entry: Dictionary) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if entry.has("repeat") and entry["repeat"] is Array:
		for item: Variant in entry["repeat"]:
			if item is Array:
				out.append(placement(item))
		return out
	var at: Array = entry.get("at", [0.0, 0.0, 0.0])
	var yaw: float = _f(entry, "yaw", 0.0)
	var tilt: float = _f(entry, "tilt", 0.0)
	out.append(placement([at[0], at[1], at[2], yaw, tilt]))
	return out


## Kit dispatch by kind name. Unknown kinds return an empty dictionary and are skipped with a warning.
## `name` is the entry's name; it only seeds the texture offset, so pieces built without one still work.
static func make_piece(kind: String, p: Dictionary, name: String = "") -> Dictionary:
	var mat: String = str(p.get("mat", "stone"))
	match kind:
		"wall":
			return StructureKit.wall(_f(p, "w", 4.0), _f(p, "h", 3.0), _f(p, "t", 0.5), mat, _d(p, "opening"), _d(p, "plinth"), _d(p, "course"), name)
		"broken_wall":
			return StructureKit.broken_wall(_f(p, "w", 4.0), _f(p, "h", 3.0), _f(p, "t", 0.5), mat, int(p.get("seed", 1)), _f(p, "keep", 0.4), name)
		"pillar":
			return StructureKit.pillar(_f(p, "radius", 0.4), _f(p, "h", 3.0), mat, int(p.get("sides", 10)), name)
		"arch":
			return StructureKit.arch(_f(p, "w", 4.0), _f(p, "h", 4.0), _f(p, "t", 0.6), mat, _f(p, "ow", 1.6), _f(p, "oh", 2.6), name)
		"stairs":
			return StructureKit.stairs(_f(p, "w", 1.4), _f(p, "rise", 2.0), mat, _f(p, "riser", StructureKit.DEFAULT_RISER), _f(p, "tread", StructureKit.DEFAULT_TREAD), name)
		"floor_slab":
			return StructureKit.floor_slab(_f(p, "w", 4.0), _f(p, "d", 4.0), _f(p, "t", 0.3), mat, name)
		"block":
			return StructureKit.block(Vector3(_f(p, "w", 1.0), _f(p, "h", 1.0), _f(p, "d", 1.0)), mat, "block", _d(p, "plinth"), _d(p, "course"), name)
		"timber_frame":
			return StructureKit.timber_frame(_f(p, "w", 4.0), _f(p, "h", 2.8), _f(p, "d", 4.0), _f(p, "beam", 0.18), mat, name)
		"buttress":
			return StructureKit.buttress(_f(p, "w", 1.0), _f(p, "h", 4.0), _f(p, "depth", 1.2), mat, name)
		"pitched_roof":
			return StructureKit.pitched_roof(_f(p, "w", 4.0), _f(p, "d", 4.0), _f(p, "rise", 1.6), _f(p, "t", 0.12), mat, _f(p, "overhang", 0.3), name)
		"collapsed_roof":
			return StructureKit.collapsed_roof(_f(p, "w", 4.0), _f(p, "d", 4.0), _f(p, "rise", 1.6), _f(p, "t", 0.12), mat, int(p.get("seed", 1)), name)
		"rubble":
			return StructureKit.rubble(_f(p, "radius", 1.5), int(p.get("count", 8)), mat, int(p.get("seed", 1)), name)
		"bell":
			return StructureKit.bell(_f(p, "radius", 0.35), _f(p, "h", 0.5), mat, name)
		"headstone":
			return StructureKit.headstone(_f(p, "w", 0.5), _f(p, "h", 0.8), _f(p, "t", 0.12), mat, name)
	# Kinds added for houses and for small props live in their own kits, so the kit can grow in two places at
	# once without both sides editing this match.
	var extra: Dictionary = StructureKitHouse.make(kind, p, name)
	if extra.is_empty():
		extra = StructureKitProps.make(kind, p, name)
	if not extra.is_empty():
		return extra
	push_warning("StructureBuilder: unknown piece kind '%s'" % kind)
	return {}


func _spawn(entry: Dictionary, index: int) -> void:
	var kind: String = str(entry.get("kind", ""))
	var name: String = str(entry.get("name", "%s_%d" % [kind, index]))
	var piece: Dictionary = _piece_for(entry, kind, name, index)
	if piece.is_empty():
		return
	var transforms: Array[Transform3D] = placements_of(entry)
	var node: Node3D
	if transforms.size() == 1:
		node = StructureKit.make_node(piece, name)
		node.transform = transforms[0]
		_stats["meshes"] += 1
	else:
		node = StructureKit.make_multi(piece, transforms, name)
		_stats["multimeshes"] += 1
	var group: String = str(entry.get("group", ""))
	node.set_meta(&"group", group)
	_groups[group] = _groups.get(group, 0) + 1
	add_child(node)
	var shapes: Array = piece["shapes"]
	_stats["pieces"] += 1
	_stats["instances"] += transforms.size()
	_stats["colliders"] += shapes.size() * transforms.size()
	_stats["verts"] += int(piece["verts"]) * transforms.size()


static func _f(d: Dictionary, key: String, fallback: float) -> float:
	var v: Variant = d.get(key, fallback)
	return float(v) if v is float or v is int else fallback


## A sub-table such as opening/plinth/course; anything that is not an object counts as absent.
static func _d(d: Dictionary, key: String) -> Dictionary:
	var v: Variant = d.get(key, {})
	return v if v is Dictionary else {}


func _piece_for(entry: Dictionary, kind: String, name: String, index: int) -> Dictionary:
	if not share_pieces or layout_path == "":
		return make_piece(kind, entry.get("params", {}), name)
	var key: String = "%s#%d" % [layout_path, index]
	if not _shared.has(key):
		_shared[key] = make_piece(kind, entry.get("params", {}), name)
	return _shared[key]


## Forgets every shared piece. Tests that change material tuning between builds call this.
static func clear_shared() -> void:
	_shared = {}
