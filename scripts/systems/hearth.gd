extends RefCounted
class_name Hearth
## The endgame rule, made executable. `docs/GAME_DESIGN.md` is the whole chain: three Kindlings and the
## Sluice Wheel drain the Mirror Pond, the drained basin lets the Wick descend, and at the Hearth the ending
## is decided by one question -- "Name read? Rekindle : Become".
##
## This holds the deciding and nothing else: it owns no nodes, reads no autoload and causes no side effect,
## so the test runner (which has no tree and no autoloads) can prove every branch by handing it plain
## dictionaries. Staging the scene, consuming the items and setting the flag belong to the caller.
##
## Requirements are derived from an item's KIND in data/items.json, never from a list of ids kept here.
## A second list would drift: `InventoryRows.kindling_progress` already counts "every item of kind
## kindling" for the inventory panel, and the panel promising three while the Hearth wants four is exactly
## the kind of disagreement that survives a whole test suite. Add a Kindling to items.json and both follow.

enum Ending {
	UNREACHABLE,   ## The pond still covers the way down: the player cannot be at the Hearth at all.
	NOT_READY,     ## At the Hearth without every Kindling. The fire has nothing to take.
	BECOME_FLAME,  ## Every Kindling, but the Name is incomplete, so the Hearth feeds on the Wick instead.
	REKINDLE,      ## Every Kindling and the whole Name. The true ending.
}

const PATH := "res://data/hearth.json"
## Only these keys are read from the file, so a `_comment` can never become configuration.
const DEFAULTS := {
	"kindling_kind": "kindling",
	"name_kind": "fragment",
	"requires_flag": "pond_drained",
	"rekindled_flag": "hearth_rekindled",
	"consumed_flag": "wick_consumed",
}


## Config from data/hearth.json over the built-in defaults, key by key. A missing or malformed file reports
## and yields the defaults, so bad tuning data can never stop the game ending (same contract as WeaponTable).
static func load_from(path: String = PATH, report_errors: bool = true) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		if report_errors:
			push_error("Hearth: cannot open %s (%s); using built-in endgame defaults"
					% [path, error_string(FileAccess.get_open_error())])
		return out
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		if report_errors:
			push_error("Hearth: bad JSON in %s line %d: %s; using built-in endgame defaults"
					% [path, json.get_error_line(), json.get_error_message()])
		return out
	for key: Variant in (json.data as Dictionary).keys():
		if DEFAULTS.has(str(key)):
			out[str(key)] = str((json.data as Dictionary)[key])
	return out


## Every item of `kind` that exists, in the order data/items.json gives them ("order", then id so ties are
## stable). This is the requirement: the quest wants one of each, not a quantity.
static func required_ids(definitions: Dictionary, kind: String) -> Array[StringName]:
	var rows: Array[Dictionary] = []
	for key: Variant in definitions.keys():
		var def: Variant = definitions[key]
		if not (def is Dictionary):
			continue
		if str((def as Dictionary).get("kind", "")) != kind:
			continue
		rows.append({"id": StringName(str(key)), "order": int((def as Dictionary).get("order", 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["order"]) != int(b["order"]):
			return int(a["order"]) < int(b["order"])
		return String(a["id"]) < String(b["id"]))
	var out: Array[StringName] = []
	for row: Dictionary in rows:
		out.append(row["id"])
	return out


## What is still missing, in requirement order -- the Hearth names the next thing to find, not all of them.
static func missing(definitions: Dictionary, held: Dictionary, kind: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in required_ids(definitions, kind):
		if not _holds(held, id):
			out.append(id)
	return out


## In-world names of what is missing, for a refusal line. Falls back to the raw id if an item has no name.
static func missing_names(definitions: Dictionary, held: Dictionary, kind: String) -> Array[String]:
	var out: Array[String] = []
	for id: StringName in missing(definitions, held, kind):
		var def: Variant = definitions.get(id, definitions.get(String(id), {}))
		var name: String = str((def as Dictionary).get("name", "")) if def is Dictionary else ""
		out.append(name if name != "" else String(id))
	return out


## (held, total) for `kind`. Matches InventoryRows.kindling_progress for the same inventory by construction.
static func progress(definitions: Dictionary, held: Dictionary, kind: String) -> Vector2i:
	var ids: Array[StringName] = required_ids(definitions, kind)
	var n: int = 0
	for id: StringName in ids:
		if _holds(held, id):
			n += 1
	return Vector2i(n, ids.size())


## Whether the way down is open. An empty requires_flag means always, which is how a test level or a debug
## run reaches the Hearth without draining anything.
static func is_reachable(flag_ids: Array, cfg: Dictionary = DEFAULTS) -> bool:
	var needed: String = str(cfg.get("requires_flag", ""))
	if needed == "":
		return true
	return _has_flag(flag_ids, needed)


## True once either ending has happened, so the Hearth is spent and must not be used twice.
static func is_finished(flag_ids: Array, cfg: Dictionary = DEFAULTS) -> bool:
	return _has_flag(flag_ids, str(cfg.get("rekindled_flag", ""))) \
			or _has_flag(flag_ids, str(cfg.get("consumed_flag", "")))


## The one decision this file exists for.
static func ending_for(definitions: Dictionary, held: Dictionary, flag_ids: Array,
		cfg: Dictionary = DEFAULTS) -> Ending:
	if not is_reachable(flag_ids, cfg):
		return Ending.UNREACHABLE
	if not missing(definitions, held, str(cfg.get("kindling_kind", ""))).is_empty():
		return Ending.NOT_READY
	# The Kindling is what the fire burns; the Name is what tells it what it is. With the fuel but not the
	# Name it still wakes, and the only thing left for it to take is the Wick who carried the fuel in.
	if missing(definitions, held, str(cfg.get("name_kind", ""))).is_empty():
		return Ending.REKINDLE
	return Ending.BECOME_FLAME


## The flag an ending leaves behind. Both end the journey; which one happened is worth keeping in the save.
static func ending_flag(ending: Ending, cfg: Dictionary = DEFAULTS) -> StringName:
	match ending:
		Ending.REKINDLE:
			return StringName(str(cfg.get("rekindled_flag", "")))
		Ending.BECOME_FLAME:
			return StringName(str(cfg.get("consumed_flag", "")))
	return &""


## True for the two outcomes that actually end the game, so a caller can branch without listing them.
static func is_ending(ending: Ending) -> bool:
	return ending == Ending.REKINDLE or ending == Ending.BECOME_FLAME


# Inventory counts and item definitions may be keyed by either StringName or String depending on who built
# the dictionary (items.json parses to String keys; Inventory.add takes StringName), so check both.
static func _holds(held: Dictionary, id: StringName) -> bool:
	return int(held.get(id, 0)) > 0 or int(held.get(String(id), 0)) > 0


static func _has_flag(flag_ids: Array, needed: String) -> bool:
	if needed == "":
		return false
	for f: Variant in flag_ids:
		if str(f) == needed:
			return true
	return false
