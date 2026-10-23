extends SceneTree
## Headless runner: godot --headless --script tests/run_tests.gd. No autoloads exist here; tests instance scripts.

const TESTS_DIR := "res://tests"


func _init() -> void:
	var passed: int = 0
	var failed: int = 0
	for path: String in _find_test_files():
		var result: Vector2i = _run_file(path)
		passed += result.x
		failed += result.y
	print("PASS %d / FAIL %d" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _find_test_files() -> Array[String]:
	var out: Array[String] = []
	for name: String in DirAccess.get_files_at(TESTS_DIR):
		if name.begins_with("test_") and name.ends_with(".gd") and name != "test_case.gd":
			out.append(TESTS_DIR + "/" + name)
	out.sort()
	return out


func _run_file(path: String) -> Vector2i:
	var script: GDScript = load(path)
	var case: TestCase = script.new()
	if case.has_method("setup"):
		case.call("setup")
	var passed: int = 0
	var failed: int = 0
	for method: Dictionary in script.get_script_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue
		var before: int = case.failures.size()
		case._begin(name)
		case.call(name)
		if case.failures.size() == before:
			passed += 1
		else:
			failed += 1
	if case.has_method("teardown"):
		case.call("teardown")
	print("%s: %d passed, %d failed" % [path.get_file(), passed, failed])
	for msg: String in case.failures:
		print("  FAIL %s" % msg)
	return Vector2i(passed, failed)
