class_name MapPanel
extends CanvasLayer
## The map the owner asked for (W19): a small one in the top-left corner all the time, and the whole Vale
## when M is pressed. Both are the same drawing at different scales (MapView), and both are built from the
## data the world itself is built from, so content added to the Vale turns up on the map by itself.
##
## It follows the same overlay rule as the inventory: the full map may only open while PLAYING, it moves the
## state to PAUSED, and only the overlay that took PLAYING -> PAUSED gives it back.

signal opened()
signal closed()

@export var area_name: String = "vale"
## Side of the corner map, in pixels, and how far it sits from the screen edge.
@export var mini_size: float = 168.0
@export var mini_margin: float = 18.0
@export var fade_in_sec: float = 0.16
@export var fade_out_sec: float = 0.10
## Metres across the full map. 1,100 covers the Vale's 1,024 m with a margin round the ridge.
@export var full_span: float = 1100.0
## Microseconds of relief building per frame while playing (W21-C). Three milliseconds leaves the rest of
## a 60 fps frame alone; the whole picture is done a few seconds after the level loads.
const RELIEF_BUDGET_USEC := 3000

var _mini: MapView
var _full: MapView
var _frame: Panel
var _title: Label
var _where: Label
var _hint: Label
var _full_root: Control
var _player: Node3D
var _level: Node
var _game: Node
var _world: Dictionary = {}
var _relief: MapRelief
var _open: bool = false
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2
	_game = get_node_or_null(^"/root/Game")
	_build()
	load_world(area_name)


## The level whose Forest the hidden wood is read from. Main calls this as it does for the HUD.
func bind_level(level: Node) -> void:
	_level = level
	load_world(area_name)


## Reads the area, its sites and the names. Public so a test can hand it a world without a scene tree.
func load_world(area: String) -> void:
	_world = gather(area, _grove_of(_level))
	# The relief is sampled from the Heightfield once per area and kept: bind_level calls this a second
	# time for the grove, and the grove is drawn over the relief, not into it.
	if _relief == null or _relief.key != area:
		_relief = MapRelief.create(_world["area"], area, MapRelief.DEFAULT_PX, full_span)
	_mini.relief = _relief
	_full.relief = _relief
	_mini.world = _world
	_full.world = _world


## The cached land picture both views draw. Public so a test can check it is one object, built once.
func relief() -> MapRelief:
	return _relief


## Everything a map needs, in one dictionary. Pure apart from reading files, so a test can call it.
static func gather(area: String, grove: Dictionary = {}) -> Dictionary:
	var path: String = "res://data/areas/%s.json" % area
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return {
		"area": parsed if parsed is Dictionary else {},
		"sites": SiteRegistry.load_area(area),
		"places": Places.load_file(),
		"grove": grove,
	}


func bind_player(player: Node3D) -> void:
	_player = player


func is_open() -> bool:
	return _open


func world() -> Dictionary:
	return _world


func open() -> void:
	if _open or _game == null or _game.state != _game.State.PLAYING:
		return
	_open = true
	_game.state = _game.State.PAUSED
	UiUtil.set_mouse_captured(false)
	_full_root.visible = true
	# Opened before the per-frame slices finished: finish now, once, rather than show half a map.
	if _relief != null and not _relief.is_ready():
		_relief.build_all()
		_full.queue_redraw()
		_mini.queue_redraw()
	_refresh()
	_fade_to(1.0, fade_in_sec)
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	var restored: bool = _game != null and _game.state == _game.State.PAUSED
	if restored:
		_game.state = _game.State.PLAYING
	UiUtil.set_mouse_captured(restored)
	_fade_to(0.0, fade_out_sec)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map"):
		get_viewport().set_input_as_handled()
		if _open:
			close()
		else:
			open()


func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(&"pause"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if _relief != null and not _relief.is_ready() and _relief.step(RELIEF_BUDGET_USEC):
		_mini.queue_redraw()
		_full.queue_redraw()
	_refresh()


func _refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var at := Vector2(_player.global_position.x, _player.global_position.z)
	# The player model faces -Z at rest, which is north, so its yaw IS a compass bearing already.
	var bearing: float = fposmod(rad_to_deg(_player.global_rotation.y) * -1.0, 360.0)
	_mini.centre = at
	_mini.refresh(at, bearing)
	if not _open:
		return
	_full.refresh(at, bearing)
	var places: Dictionary = _world.get("places", {})
	var region: Dictionary = Places.region_at(places, at)
	_title.text = str(places.get("area", "")) if not places.is_empty() else ""
	_where.text = "%s  —  %s" % [str(region.get("name", "")), Places.describe(places, at)] \
			if not region.is_empty() else Places.describe(places, at)


func _build() -> void:
	_mini = MapView.new()
	_mini.name = "MiniMap"
	_mini.clip_contents = true
	_mini.span = MapDraw.MINI_SPAN
	_mini.dot_size = MapDraw.MINI_DOT
	_mini.show_names = false
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mini.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_mini.position = Vector2(mini_margin, mini_margin)
	_mini.size = Vector2(mini_size, mini_size)
	var frame := Panel.new()
	frame.name = "MiniFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	frame.position = _mini.position - Vector2(2.0, 2.0)
	frame.size = _mini.size + Vector2(4.0, 4.0)
	frame.modulate = Color(1.0, 1.0, 1.0, 0.55)
	add_child(frame)
	add_child(_mini)
	var key := Label.new()
	key.name = "MiniHint"
	key.text = "M"
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key.position = _mini.position + Vector2(mini_size - 16.0, mini_size - 2.0)
	key.modulate = Color(0.80, 0.76, 0.66, 0.75)
	add_child(key)

	_full_root = Control.new()
	_full_root.name = "FullMap"
	_full_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_root.visible = false
	_full_root.modulate.a = 0.0
	add_child(_full_root)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.02, 0.02, 0.88)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_root.add_child(shade)
	_full = MapView.new()
	_full.name = "FullView"
	_full.clip_contents = true
	_full.span = full_span
	_full.dot_size = MapDraw.FULL_DOT
	_full.show_names = true
	_full.centre = Vector2.ZERO
	_full.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full.set_anchors_preset(Control.PRESET_FULL_RECT)
	_full.offset_left = 40.0
	_full.offset_top = 64.0
	_full.offset_right = -40.0
	_full.offset_bottom = -56.0
	_full_root.add_child(_full)
	_title = _label("Title", Vector2(40.0, 18.0), 26)
	_where = _label("Where", Vector2(40.0, 48.0), 15)
	_hint = _label("Hint", Vector2(40.0, 0.0), 13)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_top = -34.0
	_hint.offset_left = 40.0
	_hint.text = "M or Esc to close.  North is up."


func _label(node_name: String, at: Vector2, em: int) -> Label:
	var l := Label.new()
	l.name = node_name
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", em)
	_full_root.add_child(l)
	return l


func _fade_to(alpha: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_full_root, ^"modulate:a", alpha, seconds)
	if is_equal_approx(alpha, 0.0):
		_tween.tween_callback(func() -> void: _full_root.visible = false)


## The hidden wood, read off the level's Forest so the map shows it without being told twice.
func _grove_of(level: Node) -> Dictionary:
	if level == null:
		return {}
	var forest: Node = level.get_node_or_null(^"%Forest")
	if forest == null or float(forest.get("grove_radius")) <= 0.0:
		return {}
	return {"centre": forest.get("grove_centre"), "radius": forest.get("grove_radius")}
