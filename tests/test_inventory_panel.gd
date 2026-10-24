extends "res://tests/test_case.gd"
## Inventory panel: the pure InventoryRows model against the real items.json, then the scene's open/close
## state handling with an injected Game and Inventory (no tree, no autoloads, nothing tweened).

const InventoryScript := preload("res://scripts/autoloads/inventory.gd")
const GameScript := preload("res://scripts/autoloads/game.gd")
const PANEL := "res://scenes/ui/inventory_panel.tscn"

var _inv: Node
var _game: Node
var _nodes: Array[Node] = []


func setup() -> void:
	_inv = InventoryScript.new()
	_inv._load_definitions()
	_game = GameScript.new()


func teardown() -> void:
	for node: Node in _nodes:
		node.free()
	_nodes.clear()
	_inv.free()
	_game.free()


func _rows(counts: Dictionary) -> Array[Dictionary]:
	return InventoryRows.build_rows(_inv.all_definitions(), counts)


func _ids(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(row["id"]))
	return out


func test_rows_cover_every_definition_grouped_by_kind_in_a_fixed_order() -> void:
	var rows: Array[Dictionary] = _rows({})
	assert_eq(rows.size(), 13, "one row per item in items.json, held or not")
	var seen_kinds: Array[String] = []
	for group: Dictionary in InventoryRows.group_rows(rows):
		assert_false(seen_kinds.has(group["kind"]), "kind '%s' appears as one contiguous group" % group["kind"])
		seen_kinds.append(group["kind"])
	assert_eq(seen_kinds, ["kindling", "fragment", "key", "tool"], "groups follow KIND_ORDER (no 'lore' items exist yet)")
	var tools: Array[String] = []
	for row: Dictionary in rows:
		if row["kind"] == "tool":
			tools.append(String(row["id"]))
	assert_eq(tools, ["sword", "hammer", "torch", "storm_lantern", "sluice_wheel", "bell_rope"], "tools sort by their `order` field")
	assert_eq(_ids(rows).slice(0, 3), ["kindling_grey", "kindling_green", "kindling_red"], "kindlings sort grey, green, red")


func test_building_twice_from_differently_ordered_counts_gives_the_same_order() -> void:
	var first: Array[String] = _ids(_rows({&"torch": 1, &"castle_key": 1}))
	var second: Array[String] = _ids(_rows({&"castle_key": 1, &"torch": 1}))
	var third: Array[String] = _ids(_rows({}))
	assert_eq(first, second, "count key order never changes the row order")
	assert_eq(first, third, "what the player holds never changes the row order, only how rows read")


func test_held_rows_show_name_and_lore_while_missing_rows_are_withheld() -> void:
	var rows: Array[Dictionary] = _rows({&"torch": 1})
	var torch: Dictionary = {}
	var sword: Dictionary = {}
	for row: Dictionary in rows:
		if row["id"] == &"torch":
			torch = row
		elif row["id"] == &"sword":
			sword = row
	assert_true(bool(torch["held"]), "torch is held")
	assert_eq(InventoryRows.title_for(torch), "Torch", "a held item shows its real name")
	assert_eq(InventoryRows.body_for(torch), _inv.definition(&"torch")["lore"], "a held item shows its lore")
	assert_false(bool(sword["held"]), "sword is not held")
	assert_eq(InventoryRows.title_for(sword), UiText.text("unknown_item"), "a missing item reads as the withheld mark")
	assert_eq(InventoryRows.title_for(sword), "???", "the withheld mark is ???")
	assert_eq(InventoryRows.body_for(sword), UiText.text("not_yet_found"), "a missing item withholds its lore")
	assert_false(_inv.definition(&"sword")["lore"] in InventoryRows.body_for(sword), "no lore leaks for an unfound item")
	assert_true(InventoryRows.is_weapon(sword) and InventoryRows.is_weapon(torch), "sword and torch sit in the weapon slot")
	assert_false(InventoryRows.is_weapon(rows[0]), "a kindling is not a weapon")


func test_counts_above_one_render_in_the_title() -> void:
	var rows: Array[Dictionary] = _rows({&"kindling_grey": 3, &"torch": 1})
	assert_eq(int(rows[0]["count"]), 3, "the count is carried on the row")
	assert_true("×3" in InventoryRows.title_for(rows[0]), "three kindlings read with ×3 (%s)" % InventoryRows.title_for(rows[0]))
	assert_true("Grey Kindling" in InventoryRows.title_for(rows[0]), "the name stays in front of the count")
	for row: Dictionary in rows:
		if row["id"] == &"torch":
			assert_false("×" in InventoryRows.title_for(row), "a single item shows no count")


func test_progress_header_maths_including_the_edges() -> void:
	assert_eq(InventoryRows.progress(_rows({})), Vector2i(0, 13), "empty inventory: 0 of 13")
	assert_eq(InventoryRows.unknown_count(_rows({})), 13, "everything unknown at the start")
	var everything: Dictionary = {}
	for id: StringName in _inv.all_definitions():
		everything[id] = 2
	assert_eq(InventoryRows.progress(_rows(everything)), Vector2i(13, 13), "all found: 13 of 13")
	assert_eq(InventoryRows.unknown_count(_rows(everything)), 0, "nothing unknown once all are found")
	assert_eq(InventoryRows.kindling_progress(_rows({})), Vector2i(0, 3), "no kindling of three")
	assert_eq(InventoryRows.kindling_progress(_rows({&"kindling_red": 5})), Vector2i(1, 3), "kindling counts distinct kinds, not pieces")
	assert_eq(InventoryRows.kindling_progress(_rows(everything)), Vector2i(3, 3), "all three kindlings")
	assert_eq(InventoryRows.progress([] as Array[Dictionary]), Vector2i(0, 0), "no definitions at all is 0 of 0, not a crash")


func test_unknown_ids_and_unknown_kinds_do_not_break_the_builder() -> void:
	var rows: Array[Dictionary] = _rows({&"dragon_egg": 1, "torch": 1})
	assert_eq(rows.size(), 13, "an id with no definition adds no row")
	var held: int = 0
	for row: Dictionary in rows:
		if row["held"]:
			held += 1
			assert_eq(row["id"], &"torch", "String-keyed counts are matched too")
	assert_eq(held, 1, "exactly the torch is held")
	var definitions: Dictionary = {
		"b_relic": {"name": "B", "kind": "relic", "lore": "", "order": 1},
		"a_charm": {"name": "A", "kind": "charm", "lore": "", "order": 1},
		"torch": {"name": "Torch", "kind": "tool", "lore": ""},
		"junk": "not a dictionary",
	}
	var odd: Array[Dictionary] = InventoryRows.build_rows(definitions, {})
	assert_eq(_ids(odd), ["torch", "a_charm", "b_relic"], "known kinds first, unknown kinds after them alphabetically")
	assert_eq(InventoryRows.kind_label("charm"), "Charm", "an unknown kind falls back to its capitalised word")
	assert_eq(InventoryRows.kind_label("tool"), UiText.text("kind_tool"), "a known kind uses its text key")


func test_panel_opens_only_while_playing_and_restores_the_state() -> void:
	var panel: InventoryPanel = (load(PANEL) as PackedScene).instantiate() as InventoryPanel
	_nodes.append(panel)
	assert_true(panel is CanvasLayer and panel.process_mode == Node.PROCESS_MODE_ALWAYS, "panel is an always-processing CanvasLayer")
	for name: String in ["%Root", "%Rows", "%Card", "%Equip", "%Progress", "%Kindling", "%Hint", "%Title"]:
		assert_not_null(panel.get_node_or_null(name), "panel has %s" % name)
	panel._inject(_game, _inv)
	_inv.restore({"torch": 1})
	_game.state = _game.State.DEAD
	panel.open()
	assert_false(panel.is_open(), "the panel never opens while DEAD")
	_game.state = _game.State.PAUSED
	panel.open()
	assert_false(panel.is_open(), "the panel never opens over another overlay holding PAUSED")
	_game.state = _game.State.PLAYING
	panel.open()
	assert_true(panel.is_open(), "Tab while PLAYING opens the panel")
	assert_eq(_game.state, _game.State.PAUSED, "opening pauses the game")
	assert_eq(panel.row_count(), 13, "every item has a row")
	assert_eq(panel.unknown_count(), 12, "twelve rows are silhouettes with one item held")
	assert_eq((panel.get_node("%Rows") as Node).get_child_count(), 13 + 4, "13 rows plus 4 kind headings in the list")
	assert_true("1 of 13" in (panel.get_node("%Progress") as Label).text, "header shows 1 of 13 found")
	assert_false(panel.request_equip(&"torch"), "no player bound: equip is refused quietly")
	panel.close()
	assert_false(panel.is_open(), "closed")
	assert_eq(_game.state, _game.State.PLAYING, "closing restores PLAYING")
	panel.close()
	assert_eq(_game.state, _game.State.PLAYING, "a second close is a no-op")
