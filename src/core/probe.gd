extends Node
## Lets browser tests read the game. Active only on the web with `probe=1` in the page URL:
## sets `window.nocturneStarted` once `Main` is ready and installs `window.nocturneProbe()`,
## which writes the room's state to `window.nocturneState`. With `calm=1` as well, the enemies'
## brains are removed at every room start, so a test can walk without being attacked.

var _main: Main
var _calm: bool = false
## Held so the JavaScript callback stays alive.
var _probe_callback: JavaScriptObject


func _ready() -> void:
	if not OS.has_feature("web") or _query("probe") != "1":
		return
	_calm = _query("calm") == "1"
	_probe_callback = JavaScriptBridge.create_callback(_write_state)
	JavaScriptBridge.get_interface("window").nocturneProbe = _probe_callback
	# The main scene is already in the tree, but autoloads are made ready first,
	# so Main is caught before its first room starts.
	for node: Node in get_tree().root.get_children():
		if node is Main:
			_main = node
			_main.room_started.connect(_on_room_started)
			_main.ready.connect(_on_main_ready, CONNECT_ONE_SHOT)
			return
	push_warning("Probe found no Main scene to watch.")


func _on_main_ready() -> void:
	JavaScriptBridge.eval("window.nocturneStarted = true;")


func _on_room_started() -> void:
	if not _calm:
		return
	for enemy: Unit in _main.enemies:
		for child: Node in enemy.get_children():
			if child is EnemyBrain:
				enemy.remove_child(child)
				child.queue_free()


func _write_state(_args: Array) -> void:
	if not is_instance_valid(_main) or not is_instance_valid(_main.player):
		return
	var player: Unit = _main.player
	var view: Vector2 = Vector2(get_window().size) / DisplayServer.screen_get_scale()
	var state: Dictionary = {
		"pos": [player.global_position.x, player.global_position.z],
		"health": player.stats.health,
		"enemies": _main.enemies_alive(),
		"fallen": not player.is_alive(),
		"fps": int(Engine.get_frames_per_second()),
		"view": [roundi(view.x), roundi(view.y)],
	}
	JavaScriptBridge.eval("window.nocturneState = %s;" % JSON.stringify(state))


## The value of `key` in the page URL's query string, or "" when absent.
func _query(key: String) -> String:
	var value: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get(%s) || ''" % JSON.stringify(key)
	)
	return str(value) if value != null else ""
