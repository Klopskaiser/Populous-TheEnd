class_name TestBase extends RefCounted

## Minimal assertion base class for the headless test runner.
## Uses check() (which collects failures) instead of assert(), because assert()
## is a no-op in release builds.

var passed: int = 0
var failed: int = 0
var errors: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		errors.append(msg)

## Float comparison with tolerance.
func check_near(a: float, b: float, msg: String, eps: float = 0.0001) -> void:
	check(absf(a - b) <= eps, "%s (got %f, expected %f)" % [msg, a, b])
