extends Node
## Story/quest flags. Pure state: references no other autoload so tests can instance it directly.

signal flag_set(id: StringName)
signal flag_cleared(id: StringName)

var _flags: Dictionary = {}


func set_flag(id: StringName) -> void:
	if _flags.has(id):
		return
	_flags[id] = true
	flag_set.emit(id)


func clear_flag(id: StringName) -> void:
	if not _flags.erase(id):
		return
	flag_cleared.emit(id)


func has(id: StringName) -> bool:
	return _flags.has(id)


func has_all(ids: Array) -> bool:
	for id: Variant in ids:
		if not _flags.has(StringName(id)):
			return false
	return true


func count_with_prefix(prefix: String) -> int:
	var n: int = 0
	for id: StringName in _flags:
		if String(id).begins_with(prefix):
			n += 1
	return n


func all_flags() -> Array:
	var out: Array = []
	for id: StringName in _flags:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


func restore(ids: Array) -> void:
	_flags.clear()
	for id: Variant in ids:
		_flags[StringName(id)] = true
