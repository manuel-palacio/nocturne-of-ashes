extends Node
## Lets browser tests read the game. Active only when `ProbeGate` allows it: on the web with `probe=1`
## in the page URL, in the test build (never in the public build the site serves):
## `Main` registers itself through `watch()`; the probe then sets `window.nocturneStarted` once `Main`
## is ready and installs `window.nocturneProbe()`, which writes the game's state to
## `window.nocturneState`. Two test aids go with it: with `calm=1` the enemies' brains are removed at
## every room start, so a test can walk without being attacked; with `frail=1` Álvar's health is set
## to 1 whenever a room with enemies starts, after that room entry's checkpoint, so that save keeps his
## real health; a later checkpoint in the room (the end of a conversation, a cleared room) can save his
## low health. Elsewhere `watch()` does nothing.

## How high up a character or door its screen point is taken, in metres.
const PERSON_HEIGHT: float = 0.9
## How high up an enemy's head is, in metres: in a crowd seen from above, the part least often covered.
const HEAD_HEIGHT: float = 1.6

var _main: Main
var _calm: bool = false
var _frail: bool = false
## Held so the JavaScript callback stays alive.
var _probe_callback: JavaScriptObject


## Starts reporting `main`, if the page asked for the probe.
func watch(main: Main) -> void:
	if not ProbeGate.allows():
		return
	_main = main
	_calm = PageParams.is_on("calm")
	_frail = PageParams.is_on("frail")
	_probe_callback = JavaScriptBridge.create_callback(_write_state)
	JavaScriptBridge.get_interface("window").nocturneProbe = _probe_callback
	_main.room_started.connect(_on_room_started)
	_main.ready.connect(_on_main_ready, CONNECT_ONE_SHOT)


func _on_main_ready() -> void:
	JavaScriptBridge.eval("window.nocturneStarted = true;")


func _on_room_started() -> void:
	if _frail:
		# At the end of the frame: the room entry's checkpoint is taken right after this signal.
		_make_frail.call_deferred()
	if not _calm:
		return
	for enemy: Unit in _main.enemies:
		for child: Node in enemy.get_children():
			if child is CombatBrain:
				enemy.remove_child(child)
				child.queue_free()


func _make_frail() -> void:
	if is_instance_valid(_main.player) and _main.player.is_alive() and _main.enemies_alive() > 0:
		_main.player.stats.take_damage(_main.player.stats.health - 1)


func _write_state(_args: Array) -> void:
	if not is_instance_valid(_main) or not _main.is_node_ready():
		return
	var party: Array[Dictionary] = []
	for member: Unit in _main.party:
		party.append(_member_state(member))
	var selected: Unit = _main.selected
	var view: Vector2 = Vector2(get_window().size) / DisplayServer.screen_get_scale()
	var title: bool = _main.is_title_open()
	var story: GameState = _main.state
	var state: Dictionary = {
		"party": party,
		"selected": _main.party.find(selected),
		"enemies": _main.enemies_alive(),
		"marked": _enemy_points(view, true),
		"foes": _enemy_points(view, false),
		"foe_details": _foe_details(view),
		"fallen": is_instance_valid(_main.player) and not _main.player.is_alive(),
		"paused": _main.is_paused(),
		"cleared": _main.is_cleared(),
		"targeting": _main.input.targeting_gift(),
		"fps": int(Engine.get_frames_per_second()),
		"view": [roundi(view.x), roundi(view.y)],
		"room": String(_main.room.room_id) if _main.room != null and not title else "",
		"conscience": story.conscience if story != null else 0,
		"flags": story.to_dict()["flags"] if story != null else [],
		"talking": _main.is_talking(),
		"speaker": _main.dialogue.speaker(),
		"line": _main.dialogue.line_text(),
		"choices": _main.dialogue.choice_texts(),
		"notice": _main.hud.notice(),
		"closing": _main.is_closing_open(),
		"closing_ready": _main.hud.is_closing_answerable(),
		"title": title,
		"saved": _main.store != null and _main.store.has_save(),
		"asking": _title() != null and _title().is_asking(),
		"new_game": _title_point(view),
		"people": _people(view),
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
		"name": tr(member.display_name),
		"pos": [member.global_position.x, member.global_position.z],
		"health": member.stats.health,
		"blood": member.stats.blood,
		"alive": member.is_alive(),
		"fury": member.is_in_fury(),
		# Has a feed order: walking in to a weakened enemy, or drinking.
		"feeding": member.feed_target() != null,
		# Has an enemy to strike, walking to it or striking.
		"attacking": member.attack_target() != null,
		"effects": effects,
	}


## The screen point of each living enemy, or of each one showing the feed mark when `marked_only`,
## `PERSON_HEIGHT` up, in CSS pixels relative to the canvas, as `_people()` gives them, in no
## particular order; those behind the camera are left out.
func _enemy_points(view: Vector2, marked_only: bool) -> Array[Array]:
	var points: Array[Array] = []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return points
	var to_css: Vector2 = view / get_viewport().get_visible_rect().size
	for enemy: Unit in _main.enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		if marked_only and not enemy.has_feed_mark():
			continue
		var point: Vector3 = enemy.global_position + Vector3.UP * PERSON_HEIGHT
		if camera.is_position_behind(point):
			continue
		var at: Vector2 = camera.unproject_position(point) * to_css
		points.append([roundi(at.x), roundi(at.y)])
	return points


## Each living enemy in front of the camera, as `_enemy_points()` places it: its point and its head's
## (`HEAD_HEIGHT` up), its kind (its
## untranslated name in lower case: "crusader" or "sergeant"), whether it shows the feed mark, whether
## it is attacking a party member, and whether it is stunned. What a player sees on screen, no more.
func _foe_details(view: Vector2) -> Array[Dictionary]:
	var details: Array[Dictionary] = []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return details
	var to_css: Vector2 = view / get_viewport().get_visible_rect().size
	for enemy: Unit in _main.enemies:
		if not is_instance_valid(enemy) or not enemy.is_alive():
			continue
		var point: Vector3 = enemy.global_position + Vector3.UP * PERSON_HEIGHT
		if camera.is_position_behind(point):
			continue
		var at: Vector2 = camera.unproject_position(point) * to_css
		var head: Vector2 = camera.unproject_position(enemy.global_position + Vector3.UP * HEAD_HEIGHT) * to_css
		var victim: Unit = enemy.attack_target()
		details.append({
			"at": [roundi(at.x), roundi(at.y)],
			"head": [roundi(head.x), roundi(head.y)],
			"kind": enemy.display_name.to_lower(),
			"marked": enemy.has_feed_mark(),
			"attacking": victim != null and _main.party.has(victim),
			"stunned": enemy.is_stunned(),
		})
	return details


func _title() -> TitleScreen:
	return _main.find_child("TitleScreen", true, false) as TitleScreen


## The middle of the title's New game place, in CSS pixels relative to the canvas; empty without a
## title.
func _title_point(view: Vector2) -> Array[int]:
	var title: TitleScreen = _title()
	if title == null:
		return []
	var at: Vector2 = title.new_game_point() * view / get_viewport().get_visible_rect().size
	return [roundi(at.x), roundi(at.y)]


## Each visible character's and door's screen point, `PERSON_HEIGHT` up, in CSS pixels relative to the
## canvas, whose size is `view`: a character under its untranslated label, a door under its node name.
## A point off screen is reported as it is, outside the canvas; only those behind the camera are left out.
func _people(view: Vector2) -> Dictionary:
	var people: Dictionary = {}
	var camera: Camera3D = get_viewport().get_camera_3d()
	if _main.room == null or camera == null:
		return people
	var to_css: Vector2 = view / get_viewport().get_visible_rect().size
	for node: Node in _main.room.find_children("*", "Interactable", true, false):
		var thing := node as Interactable
		var key: String = ""
		if thing is Npc:
			key = thing.label
		elif thing is Door:
			key = String(thing.name)
		if key.is_empty() or not thing.is_visible_in_tree():
			continue
		var point: Vector3 = thing.global_position + Vector3.UP * PERSON_HEIGHT
		if camera.is_position_behind(point):
			continue
		var at: Vector2 = camera.unproject_position(point) * to_css
		people[key] = [roundi(at.x), roundi(at.y)]
	return people
