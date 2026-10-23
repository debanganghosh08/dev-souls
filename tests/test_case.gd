extends RefCounted
class_name TestCase
## Base for tests/test_*.gd. Assertions record failures instead of crashing so a run reports every test.

var failures: Array[String] = []
var _current: String = ""


func _begin(test_name: String) -> void:
	_current = test_name


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(v: bool, msg: String) -> void:
	if not v:
		_fail(msg)


func assert_false(v: bool, msg: String) -> void:
	if v:
		_fail(msg)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		_fail("%s (expected %s, got %s)" % [msg, str(b), str(a)])


func assert_ne(a: Variant, b: Variant, msg: String) -> void:
	if a == b:
		_fail("%s (both %s)" % [msg, str(a)])


func assert_null(v: Variant, msg: String) -> void:
	if v != null:
		_fail("%s (got %s)" % [msg, str(v)])


func assert_not_null(v: Variant, msg: String) -> void:
	if v == null:
		_fail(msg)
