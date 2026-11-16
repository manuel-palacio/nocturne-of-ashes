extends GutTest

var state: GameState

func before_each() -> void:
	state = GameState.new_game()

func test_a_new_game_starts_in_the_haven_with_alvar_alone() -> void:
	assert_eq(state.conscience, 7)
	assert_eq(state.room, &"haven")
	assert_eq(state.entry, &"start")
	assert_eq(state.joined(), [&"alvar"] as Array[StringName])
	assert_eq(state.known_gifts(&"alvar"), [] as Array[StringName])
	assert_eq(state.known_gifts(&"zahra"), [&"mend_flesh", &"blood_lance"] as Array[StringName])
	assert_eq(state.vitals(&"alvar"), Vector2i(-1, -1))

func test_a_skirmish_has_everyone_and_everything() -> void:
	var s := GameState.skirmish()
	assert_eq(s.room, &"vault")
	assert_eq(s.joined(), [&"alvar", &"zahra", &"gonzalo"] as Array[StringName])
	assert_true(s.knows(&"alvar", &"baleful_eye"))

func test_conscience_is_clamped_and_signals_only_on_change() -> void:
	watch_signals(state)
	state.change_conscience(-2)
	assert_eq(state.conscience, 5)
	state.change_conscience(-99)
	assert_eq(state.conscience, 0)
	state.change_conscience(-1)
	state.change_conscience(99)
	assert_eq(state.conscience, 10)
	assert_signal_emit_count(state, "conscience_changed", 3)

func test_flags() -> void:
	watch_signals(state)
	assert_false(state.has_flag(&"met_malakor"))
	state.set_flag(&"met_malakor")
	assert_true(state.has_flag(&"met_malakor"))
	state.set_flag(&"met_malakor", false)
	assert_false(state.has_flag(&"met_malakor"))
	assert_signal_emit_count(state, "flag_changed", 2)

func test_flag_and_member_names_given_as_plain_strings_work() -> void:
	state.set_flag("order_given")
	state.join("zahra")
	assert_true(state.has_flag(&"order_given"))
	assert_true(state.has_joined(&"zahra"))

func test_joining_is_once_in_order_and_only_for_real_members() -> void:
	watch_signals(state)
	state.join(&"gonzalo")
	state.join(&"gonzalo")
	state.join(&"zahra")
	state.join(&"malakor")
	assert_eq(state.joined(), [&"alvar", &"zahra", &"gonzalo"] as Array[StringName])
	assert_signal_emit_count(state, "member_joined", 2)

func test_learning_gifts() -> void:
	watch_signals(state)
	state.learn(&"alvar", &"baleful_eye")
	state.learn(&"alvar", &"iron_sinew")
	state.learn(&"alvar", &"iron_sinew")
	state.learn(&"alvar", &"hammerfall")
	assert_eq(state.known_gifts(&"alvar"), [&"iron_sinew", &"baleful_eye"] as Array[StringName])
	assert_signal_emit_count(state, "gift_learned", 2)

func test_vitals_are_kept_per_member() -> void:
	state.set_vitals(&"alvar", 55, 20)
	assert_eq(state.vitals(&"alvar"), Vector2i(55, 20))
	assert_eq(state.vitals(&"zahra"), Vector2i(-1, -1))

func test_a_round_trip_through_json_keeps_everything() -> void:
	state.change_conscience(-3)
	state.set_flag(&"captive_done")
	state.join(&"zahra")
	state.learn(&"alvar", &"iron_sinew")
	state.set_vitals(&"alvar", 80, 35)
	state.room = &"vault"
	state.entry = &"from_haven"
	var text: String = JSON.stringify(state.to_dict())
	var back := GameState.from_dict(JSON.parse_string(text))
	assert_not_null(back)
	assert_eq(back.to_dict(), state.to_dict())
	assert_eq(back.conscience, 4)
	assert_eq(back.room, &"vault")
	assert_true(back.has_flag(&"captive_done"))
	assert_eq(back.joined(), [&"alvar", &"zahra"] as Array[StringName])
	assert_eq(back.vitals(&"alvar"), Vector2i(80, 35))

func test_unusable_data_gives_null() -> void:
	assert_null(GameState.from_dict(null))
	assert_null(GameState.from_dict("save"))
	assert_null(GameState.from_dict({}))
	var old: Dictionary = state.to_dict()
	old["version"] = 0
	assert_null(GameState.from_dict(old))
	var newer: Dictionary = state.to_dict()
	newer["version"] = GameState.VERSION + 1
	assert_null(GameState.from_dict(newer))
	var broken: Dictionary = state.to_dict()
	broken["conscience"] = "seven"
	assert_null(GameState.from_dict(broken))

func test_extra_keys_are_ignored_and_values_are_sanitised() -> void:
	var data: Dictionary = state.to_dict()
	data["something_new"] = 42
	data["conscience"] = 99
	var back := GameState.from_dict(data)
	assert_not_null(back)
	assert_eq(back.conscience, 10)

func _with(key: String, value: Variant) -> Dictionary:
	var data: Dictionary = state.to_dict()
	data[key] = value
	return data

func test_whole_floats_are_integers_and_fractions_are_unusable() -> void:
	var back := GameState.from_dict(_with("conscience", 7.0))
	assert_not_null(back)
	assert_eq(back.conscience, 7)
	assert_null(GameState.from_dict(_with("conscience", 7.5)))
	assert_null(GameState.from_dict(_with("conscience", INF)))
	assert_null(GameState.from_dict(_with("conscience", NAN)))

func test_a_boolean_where_a_number_belongs_is_unusable() -> void:
	assert_null(GameState.from_dict(_with("conscience", true)))
	assert_null(GameState.from_dict(_with("version", true)))

func test_huge_whole_numbers_are_clamped() -> void:
	assert_eq(GameState.from_dict(_with("conscience", 1e300)).conscience, 10)
	assert_eq(GameState.from_dict(_with("conscience", -1e300)).conscience, 0)

func test_vitals_are_clamped() -> void:
	state.set_vitals(&"alvar", 5000000000000, -50)
	assert_eq(state.vitals(&"alvar"), Vector2i(10000, -1))
	state.set_vitals(&"zahra", 2147483648, 4294967295)
	assert_eq(state.vitals(&"zahra"), Vector2i(10000, 10000))
	var back := GameState.from_dict(_with("vitals", {"alvar": [5e12, -50.0]}))
	assert_eq(back.vitals(&"alvar"), Vector2i(10000, -1))

func test_vitals_must_be_pairs_of_numbers_for_real_members_only() -> void:
	assert_null(GameState.from_dict(_with("vitals", {"alvar": "full"})))
	assert_null(GameState.from_dict(_with("vitals", {"alvar": [1]})))
	assert_null(GameState.from_dict(_with("vitals", {"alvar": [1, "two"]})))
	var back := GameState.from_dict(_with("vitals", {"malakor": "full", "zahra": [3, 4]}))
	assert_not_null(back)
	assert_eq(back.vitals(&"zahra"), Vector2i(3, 4))

func test_gifts_must_be_lists_of_names_for_real_members_only() -> void:
	assert_null(GameState.from_dict(_with("gifts", {"zahra": "all"})))
	var back := GameState.from_dict(_with("gifts", {"malakor": 3, "zahra": ["blood_lance", "fly"]}))
	assert_not_null(back)
	assert_eq(back.known_gifts(&"zahra"), [&"blood_lance"] as Array[StringName])

func test_alvar_is_always_joined() -> void:
	var back := GameState.from_dict(_with("joined", []))
	assert_not_null(back)
	assert_eq(back.joined(), [&"alvar"] as Array[StringName])

func test_an_empty_room_or_entry_is_unusable() -> void:
	assert_null(GameState.from_dict(_with("room", "")))
	assert_null(GameState.from_dict(_with("entry", "")))
