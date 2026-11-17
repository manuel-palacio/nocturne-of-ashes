class_name PageParams
extends RefCounted
## The query parameters of the page the game runs in, read once, on the first question. Off the web
## every parameter reads as absent.

## Each parameter's value by name; null until read.
static var _values: Variant = null


## The value of `key`, or "" when absent.
static func value(key: String) -> String:
	return all().get(key, "")


## Every parameter given, by name; empty off the web.
static func all() -> Dictionary:
	if _values == null:
		_values = _read()
	return _values


## Whether `key` is given as "1".
static func is_on(key: String) -> bool:
	return value(key) == "1"


static func _read() -> Dictionary:
	var values: Dictionary = {}
	if not OS.has_feature("web"):
		return values
	var text: Variant = JavaScriptBridge.eval(
		"JSON.stringify(Object.fromEntries(new URLSearchParams(window.location.search)))"
	)
	var parsed: Variant = JSON.parse_string(str(text)) if text != null else null
	if parsed is Dictionary:
		for key: Variant in parsed:
			values[str(key)] = str(parsed[key])
	return values
