extends RefCounted
class_name TestCase
## Base for tests/test_*.gd. Assertions record failures instead of crashing so a run reports every test.

var failures: Array[String] = []
## Assertions reached in the current test. A GDScript runtime error aborts the function it happens in
## WITHOUT raising anything the runner can catch, so a test that dies before asserting used to be counted as
## a pass -- which is how a test that proves nothing hides in a green suite. The runner treats zero as a
## failure. (A mid-test error still slips through this, so the suite's output is also checked for
## "SCRIPT ERROR" lines; see docs/TOOLS.md.)
var assertions: int = 0
var _current: String = ""


func _begin(test_name: String) -> void:
	_current = test_name
	assertions = 0


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(v: bool, msg: String) -> void:
	assertions += 1
	if not v:
		_fail(msg)


func assert_false(v: bool, msg: String) -> void:
	assertions += 1
	if v:
		_fail(msg)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	assertions += 1
	if a != b:
		_fail("%s (expected %s, got %s)" % [msg, str(b), str(a)])


func assert_ne(a: Variant, b: Variant, msg: String) -> void:
	assertions += 1
	if a == b:
		_fail("%s (both %s)" % [msg, str(a)])


func assert_null(v: Variant, msg: String) -> void:
	assertions += 1
	if v != null:
		_fail("%s (got %s)" % [msg, str(v)])


func assert_not_null(v: Variant, msg: String) -> void:
	assertions += 1
	if v == null:
		_fail(msg)
