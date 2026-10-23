extends VBoxContainer
class_name ItemToasts
## Quiet "Acquired — ..." lines stacked at the lower right. At most MAX_LINES; the oldest line gives way.

const MAX_LINES := 3

@export var lifetime_sec: float = 3.0
@export var fade_sec: float = 0.4
@export var font_size: int = 18

var _lines: Array[Label] = []
var _time_left: Array[float] = []


func push(text: String) -> void:
	if _lines.size() >= MAX_LINES:
		_drop(0)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", UiUtil.BONE)
	label.modulate.a = 0.0
	add_child(label)
	_lines.append(label)
	_time_left.append(lifetime_sec)
	create_tween().tween_property(label, ^"modulate:a", 1.0, fade_sec * 0.5)


func line_count() -> int:
	return _lines.size()


func _process(delta: float) -> void:
	var i: int = _lines.size() - 1
	while i >= 0:
		_time_left[i] -= delta
		if _time_left[i] <= 0.0:
			_drop(i)
		i -= 1


func _drop(index: int) -> void:
	var label: Label = _lines[index]
	_lines.remove_at(index)
	_time_left.remove_at(index)
	var tween: Tween = create_tween()
	tween.tween_property(label, ^"modulate:a", 0.0, fade_sec)
	tween.tween_callback(label.queue_free)
