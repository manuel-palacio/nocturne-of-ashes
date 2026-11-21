# tests/core/test_export_presets.gd
extends GutTest
## The two web export presets, "Web" (the test build) and "Web public" (the site's), stay the same in
## every setting and option apart from their name, their export path and the public build's feature,
## and `runnable`: the editor lets only one preset per platform be run with one click.

## The settings allowed to differ.
const OWN: Array[String] = ["name", "export_path", "custom_features", "runnable"]

var presets := ConfigFile.new()


func before_all() -> void:
	assert_eq(presets.load("res://export_presets.cfg"), OK)


## The section of the preset named `preset_name`, as "preset.N"; "" when there is none.
func _section(preset_name: String) -> String:
	for section: String in presets.get_sections():
		if section.count(".") == 1 and presets.get_value(section, "name", "") == preset_name:
			return section
	return ""


func test_both_presets_exist() -> void:
	assert_ne(_section("Web"), "")
	assert_ne(_section("Web public"), "")


func test_only_the_public_preset_has_the_public_feature() -> void:
	assert_eq(presets.get_value(_section("Web public"), "custom_features"), ProbeGate.PUBLIC_FEATURE)
	assert_false(String(presets.get_value(_section("Web"), "custom_features", "")).contains(ProbeGate.PUBLIC_FEATURE))


func test_they_export_to_their_own_directories() -> void:
	assert_eq(presets.get_value(_section("Web"), "export_path"), "build/web/index.html")
	assert_eq(presets.get_value(_section("Web public"), "export_path"), "build/public/index.html")


func _assert_same(test_section: String, public_section: String, skip: Array[String]) -> void:
	var keys: PackedStringArray = presets.get_section_keys(test_section)
	assert_eq(Array(presets.get_section_keys(public_section)).filter(func(k: String) -> bool: return not keys.has(k)),
			[], "%s has no setting %s lacks" % [public_section, test_section])
	for key: String in keys:
		if skip.has(key):
			continue
		assert_true(presets.has_section_key(public_section, key), "%s lacks %s" % [public_section, key])
		assert_eq(presets.get_value(public_section, key, null), presets.get_value(test_section, key),
				"%s differs" % key)


func test_every_other_setting_is_the_same() -> void:
	_assert_same(_section("Web"), _section("Web public"), OWN)


func test_every_option_is_the_same() -> void:
	_assert_same(_section("Web") + ".options", _section("Web public") + ".options", [] as Array[String])
