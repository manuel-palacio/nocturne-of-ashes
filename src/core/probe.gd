extends Node
## Lets browser tests read the game. Active only on the web with `probe=1` in the page URL:
## `Main` registers itself through `watch()`; the probe then sets `window.nocturneStarted` once `Main`
## is ready and installs `window.nocturneProbe()`, which writes the room's state to
## `window.nocturneState`. With `calm=1` as well, the enemies' brains are removed at every room start,
## so a test can walk without being attacked. Elsewhere `watch()` does nothing.

var _main: Main
var _calm: bool = false
## Held so the JavaScript callback stays alive.
var _probe_callback: JavaScriptObject


## Starts reporting `main`, if the page asked for the probe.
func watch(main: Main) -> void:
	if not OS.has_feature("web") or _query("probe") != "1":
		return
	_main = main
	_calm = _query("calm") == "1"
	_probe_callback = JavaScriptBridge.create_callback(_write_state)
	JavaScriptBridge.get_interface("window").nocturneProbe = _probe_callback
	_main.room_started.connect(_on_room_started)
	_main.ready.connect(_on_main_ready, CONNECT_ONE_SHOT)


func _on_main_ready() -> void:
	JavaScriptBridge.eval("window.nocturneStarted = true;")


func _on_room_started() -> void:
	if not _calm:
		return
	for enemy: Unit in _main.enemies:
		for child: Node in enemy.get_children():
			if child is CombatBrain:
				enemy.remove_child(child)
				child.queue_free()


func _write_state(_args: Array) -> void:
	if not is_instance_valid(_main) or not is_instance_valid(_main.player):
		return
	var party: Array[Dictionary] = []
	for member: Unit in _main.party:
		party.append(_member_state(member))
	var selected: Unit = _main.selected
	var view: Vector2 = Vector2(get_window().size) / DisplayServer.screen_get_scale()
	var state: Dictionary = {
		"party": party,
		"selected": _main.party.find(selected),
		"enemies": _main.enemies_alive(),
		"fallen": not _main.player.is_alive(),
		"paused": _main.is_paused(),
		"cleared": _main.is_cleared(),
		"targeting": _main.input.targeting_gift(),
		"fps": int(Engine.get_frames_per_second()),
		"view": [roundi(view.x), roundi(view.y)],
	}
	# The selected member's, under the names the single-character tests read.
	if is_instance_valid(selected):
		state["pos"] = [selected.global_position.x, selected.global_position.z]
		state["health"] = selected.stats.health
	JavaScriptBridge.eval("window.nocturneState = %s;" % JSON.stringify(state))


func _member_state(member: Unit) -> Dictionary:
	var effects: Array[String] = []
	for id: StringName in member.effect_ids():
		effects.append(String(id))
	return {
		"name": member.display_name,
		"pos": [member.global_position.x, member.global_position.z],
		"health": member.stats.health,
		"blood": member.stats.blood,
		"alive": member.is_alive(),
		"fury": member.is_in_fury(),
		"effects": effects,
	}


## The value of `key` in the page URL's query string, or "" when absent.
func _query(key: String) -> String:
	var value: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get(%s) || ''" % JSON.stringify(key)
	)
	return str(value) if value != null else ""
