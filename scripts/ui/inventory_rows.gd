extends RefCounted
class_name InventoryRows
## The inventory panel's row model, pure and static so tests can pin it without a scene. A row is a
## Dictionary {id, kind, name, lore, slot, order, count, held}; every id in the item table yields one, held
## or not, so an incomplete set is visible as a set. Order is fully deterministic: kind rank, then `order`,
## then id, so the list never jumps between openings.

const KIND_ORDER: Array[String] = ["kindling", "fragment", "key", "tool", "lore"]
const WEAPON_SLOT := "weapon"
const KINDLING_KIND := "kindling"


## One row per definition. `counts` may use StringName or String keys; ids held but not defined are skipped
## (the Inventory autoload never stores those, but a hand-edited save could).
static func build_rows(definitions: Dictionary, counts: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: Variant in definitions:
		var definition: Variant = definitions[key]
		if not definition is Dictionary:
			continue
		var id: StringName = StringName(str(key))
		var count: int = int(counts.get(id, counts.get(String(id), 0)))
		rows.append({
			"id": id,
			"kind": str(definition.get("kind", "")),
			"name": str(definition.get("name", String(id))),
			"lore": str(definition.get("lore", "")),
			"slot": str(definition.get("slot", "")),
			"order": int(definition.get("order", 0)),
			"count": maxi(count, 0),
			"held": count > 0,
		})
	rows.sort_custom(row_before)
	return rows


static func row_before(a: Dictionary, b: Dictionary) -> bool:
	var rank_a: int = kind_rank(str(a["kind"]))
	var rank_b: int = kind_rank(str(b["kind"]))
	if rank_a != rank_b:
		return rank_a < rank_b
	if a["kind"] != b["kind"]:
		return str(a["kind"]) < str(b["kind"])
	if a["order"] != b["order"]:
		return int(a["order"]) < int(b["order"])
	return String(a["id"]) < String(b["id"])


## Kinds the design names come first in KIND_ORDER; anything else sorts after them, alphabetically.
static func kind_rank(kind: String) -> int:
	var index: int = KIND_ORDER.find(kind)
	return index if index >= 0 else KIND_ORDER.size()


## Sorted rows folded into [{kind, rows}] groups, in the same order, for the section headings.
static func group_rows(rows: Array[Dictionary]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for row: Dictionary in rows:
		if groups.is_empty() or groups[-1]["kind"] != row["kind"]:
			groups.append({"kind": row["kind"], "rows": [] as Array[Dictionary]})
		(groups[-1]["rows"] as Array[Dictionary]).append(row)
	return groups


## (held distinct items, known items).
static func progress(rows: Array[Dictionary]) -> Vector2i:
	var held: int = 0
	for row: Dictionary in rows:
		if row["held"]:
			held += 1
	return Vector2i(held, rows.size())


## (distinct kindlings held, kindlings that exist). Distinct, not a sum: the quest wants one of each.
static func kindling_progress(rows: Array[Dictionary]) -> Vector2i:
	var held: int = 0
	var total: int = 0
	for row: Dictionary in rows:
		if row["kind"] != KINDLING_KIND:
			continue
		total += 1
		if row["held"]:
			held += 1
	return Vector2i(held, total)


static func unknown_count(rows: Array[Dictionary]) -> int:
	return rows.size() - progress(rows).x


static func is_weapon(row: Dictionary) -> bool:
	return row["slot"] == WEAPON_SLOT


## List text: the real name (with a count past one) for a held item, the withheld mark otherwise.
static func title_for(row: Dictionary) -> String:
	if not row["held"]:
		return UiText.text("unknown_item")
	if int(row["count"]) > 1:
		return UiText.text("row_count") % [row["name"], int(row["count"])]
	return str(row["name"])


## Detail text: the lore for a held item, the withheld line otherwise.
static func body_for(row: Dictionary) -> String:
	return str(row["lore"]) if row["held"] else UiText.text("not_yet_found")


## Section heading for a kind; a kind the text table does not know falls back to the raw word.
static func kind_label(kind: String) -> String:
	var key: String = "kind_" + kind
	if UiText.DEFAULTS.has(key):
		return UiText.text(key)
	return kind.capitalize()
