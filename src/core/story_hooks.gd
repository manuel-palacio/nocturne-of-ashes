class_name StoryHooks
extends RefCounted
## The only object a conversation can call: reads and changes the story through a `GameState`, and
## gives Blood to Álvar. Conversation files name these methods directly, e.g. `do set_flag("spared")`
## or `[if conscience() >= 8 /]`. Names arrive from conversations as strings. Once revoked, at the
## end of its conversation, every hook does nothing and answers 0 or false.

var _state: GameState
## Returns Álvar's unit, or null when there is none; asked each time, so no stale unit is kept.
var _alvar: Callable
var _revoked: bool = false


func _init(state: GameState, alvar: Callable) -> void:
	_state = state
	_alvar = alvar


## New hooks on the same state and Álvar, not revoked.
func copy() -> StoryHooks:
	return StoryHooks.new(_state, _alvar)


## Makes every hook do nothing from now on.
func revoke() -> void:
	_revoked = true


func conscience() -> int:
	if _revoked:
		return 0
	return _state.conscience


func change_conscience(delta: int) -> void:
	if _revoked:
		return
	_state.change_conscience(delta)


func has_flag(key: String) -> bool:
	if _revoked:
		return false
	return _state.has_flag(StringName(key))


func set_flag(key: String) -> void:
	if _revoked:
		return
	_state.set_flag(StringName(key))


func join(member: String) -> void:
	if _revoked:
		return
	_state.join(StringName(member))


func has_joined(member: String) -> bool:
	if _revoked:
		return false
	return _state.has_joined(StringName(member))


func learn(member: String, gift: String) -> void:
	if _revoked:
		return
	_state.learn(StringName(member), StringName(gift))


## Gives Álvar `amount` Blood, capped at his maximum. Does nothing when he is not there.
func give_blood(amount: int) -> void:
	var alvar: Unit = _unit()
	if alvar != null:
		alvar.stats.gain_blood(amount)


## Álvar's Blood; 0 when he is not there.
func blood() -> int:
	var alvar: Unit = _unit()
	return alvar.stats.blood if alvar != null else 0


## Álvar's unit; null when he is not there or the hooks are revoked.
func _unit() -> Unit:
	if _revoked:
		return null
	var found: Variant = _alvar.call()
	return found as Unit if is_instance_valid(found) else null
