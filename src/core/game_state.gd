class_name GameState
extends RefCounted
## The story progress that outlives a room: Conscience, story flags, who has joined, the Gifts each
## member knows, each member's health and Blood, and where the party is. Plain data; it knows nothing
## of units, rooms or the scene tree. `to_dict()` and `from_dict()` turn it into JSON-safe data and back.

signal conscience_changed(value: int)
signal flag_changed(key: StringName)
signal member_joined(member: StringName)
signal gift_learned(member: StringName, gift: StringName)

## Format of `to_dict()`; data from any other version is not read.
const VERSION: int = 1
const CONSCIENCE_MAX: int = 10
const CONSCIENCE_START: int = 7
## Everyone who can be in the party, in party order.
const MEMBERS: Array[StringName] = [&"alvar", &"zahra", &"gonzalo"]
## Each member's Gifts, in the order they are listed.
const ALL_GIFTS: Dictionary = {
	&"alvar": [&"iron_sinew", &"baleful_eye"],
	&"zahra": [&"mend_flesh", &"blood_lance"],
	&"gonzalo": [&"stone_hide", &"hammerfall"],
}
## Health and Blood of a member with nothing stored: full health, starting Blood.
const NO_VITALS := Vector2i(-1, -1)
## The largest magnitude a float can hold as an exact whole number.
const _EXACT_FLOAT_LIMIT: float = 9007199254740992.0

var conscience: int = CONSCIENCE_START
var room: StringName
var entry: StringName

var _flags: Dictionary = {}  # StringName -> true
var _joined: Dictionary = {}  # StringName -> true
var _gifts: Dictionary = {}  # StringName member -> {StringName gift: true}
var _vitals: Dictionary = {}  # StringName member -> Vector2i


static func new_game() -> GameState:
	var state := GameState.new()
	state.room = &"haven"
	state.entry = &"start"
	state._joined[&"alvar"] = true
	for member: StringName in [&"zahra", &"gonzalo"]:
		for gift: StringName in ALL_GIFTS[member]:
			state._add_gift(member, gift)
	return state


static func skirmish() -> GameState:
	var state := GameState.new()
	state.room = &"vault"
	state.entry = &"start"
	for member: StringName in MEMBERS:
		state._joined[member] = true
		for gift: StringName in ALL_GIFTS[member]:
			state._add_gift(member, gift)
	return state


func change_conscience(delta: int) -> void:
	var value: int = clampi(conscience + delta, 0, CONSCIENCE_MAX)
	if value == conscience:
		return
	conscience = value
	conscience_changed.emit(conscience)


func set_flag(key: StringName, on: bool = true) -> void:
	if has_flag(key) == on:
		return
	if on:
		_flags[key] = true
	else:
		_flags.erase(key)
	flag_changed.emit(key)


func has_flag(key: StringName) -> bool:
	return _flags.has(key)


func join(member: StringName) -> void:
	if not MEMBERS.has(member) or has_joined(member):
		return
	_joined[member] = true
	member_joined.emit(member)


func has_joined(member: StringName) -> bool:
	return _joined.has(member)


## Members who have joined, in `MEMBERS` order.
func joined() -> Array[StringName]:
	var result: Array[StringName] = []
	for member: StringName in MEMBERS:
		if has_joined(member):
			result.append(member)
	return result


func learn(member: StringName, gift: StringName) -> void:
	if not _is_gift_of(member, gift) or knows(member, gift):
		return
	_add_gift(member, gift)
	gift_learned.emit(member, gift)


func knows(member: StringName, gift: StringName) -> bool:
	return _gifts.has(member) and (_gifts[member] as Dictionary).has(gift)


## The Gifts `member` knows, in `ALL_GIFTS` order.
func known_gifts(member: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for gift: StringName in ALL_GIFTS.get(member, []):
		if knows(member, gift):
			result.append(gift)
	return result


## Stores `member`'s health and Blood; -1 stands for full health or starting Blood.
func set_vitals(member: StringName, health: int, blood: int) -> void:
	if not MEMBERS.has(member):
		return
	_vitals[member] = Vector2i(maxi(health, -1), maxi(blood, -1))


## `member`'s health and Blood; `NO_VITALS` when none are stored.
func vitals(member: StringName) -> Vector2i:
	return _vitals.get(member, NO_VITALS)


func to_dict() -> Dictionary:
	var flags: Array[String] = []
	for key: StringName in _flags:
		flags.append(String(key))
	flags.sort()
	var members: Array[String] = []
	var gifts: Dictionary = {}
	var vitals_data: Dictionary = {}
	for member: StringName in MEMBERS:
		if has_joined(member):
			members.append(String(member))
		var known: Array[String] = []
		for gift: StringName in known_gifts(member):
			known.append(String(gift))
		gifts[String(member)] = known
		if _vitals.has(member):
			var value: Vector2i = _vitals[member]
			vitals_data[String(member)] = [value.x, value.y]
	return {
		"version": VERSION,
		"conscience": conscience,
		"room": String(room),
		"entry": String(entry),
		"flags": flags,
		"joined": members,
		"gifts": gifts,
		"vitals": vitals_data,
	}


## The state `data` describes, or null when `data` is not a dictionary from `to_dict()` of this
## `VERSION` with fields of the right types. Numbers may come as floats, names as strings (as JSON
## gives them); out-of-range numbers are clamped; unknown members and Gifts are dropped; extra keys
## are ignored.
static func from_dict(data: Variant) -> GameState:
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	if _as_int(d.get("version")) != VERSION:
		return null
	var conscience_value: Variant = _as_int(d.get("conscience"))
	var room_value: Variant = d.get("room")
	var entry_value: Variant = d.get("entry")
	var flags_value: Variant = d.get("flags")
	var joined_value: Variant = d.get("joined")
	var gifts_value: Variant = d.get("gifts")
	var vitals_value: Variant = d.get("vitals")
	if conscience_value == null or not _is_name(room_value) or not _is_name(entry_value):
		return null
	if not _is_name_list(flags_value) or not _is_name_list(joined_value):
		return null
	if not gifts_value is Dictionary or not vitals_value is Dictionary:
		return null

	var state := GameState.new()
	state.conscience = clampi(conscience_value, 0, CONSCIENCE_MAX)
	state.room = StringName(room_value)
	state.entry = StringName(entry_value)
	for key: Variant in flags_value:
		state._flags[StringName(key)] = true
	for member: Variant in joined_value:
		if MEMBERS.has(StringName(member)):
			state._joined[StringName(member)] = true
	for member: Variant in gifts_value:
		var list: Variant = gifts_value[member]
		if not _is_name(member) or not _is_name_list(list):
			return null
		for gift: Variant in list:
			if _is_gift_of(StringName(member), StringName(gift)):
				state._add_gift(StringName(member), StringName(gift))
	for member: Variant in vitals_value:
		var pair: Variant = vitals_value[member]
		if not _is_name(member) or not pair is Array or (pair as Array).size() != 2:
			return null
		var health: Variant = _as_int(pair[0])
		var blood: Variant = _as_int(pair[1])
		if health == null or blood == null:
			return null
		state.set_vitals(StringName(member), health, blood)
	return state


func _add_gift(member: StringName, gift: StringName) -> void:
	if not _gifts.has(member):
		_gifts[member] = {}
	(_gifts[member] as Dictionary)[gift] = true


static func _is_gift_of(member: StringName, gift: StringName) -> bool:
	return (ALL_GIFTS.get(member, []) as Array).has(gift)


## `value` as an int when it is a whole number (JSON gives floats such as 7.0), else null.
static func _as_int(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and absf(number) <= _EXACT_FLOAT_LIMIT:
			return int(number)
	return null


static func _is_name(value: Variant) -> bool:
	return value is String or value is StringName


static func _is_name_list(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value:
		if not _is_name(item):
			return false
	return true
