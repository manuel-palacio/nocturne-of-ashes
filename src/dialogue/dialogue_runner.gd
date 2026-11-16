class_name DialogueRunner
extends Node
## Runs one conversation at a time through the Dialogue Manager add-on, the only place that knows the
## add-on's API: shows each line with the choices whose condition holds, and goes on when told to.
##
## A conversation reaches the game only through the `StoryHooks` it is started with: the add-on is
## told not to look in the current scene, singletons, classes or autoloads, and not to load files.
## Lines and choices are given as written. Each conversation gets its own copy of the hooks it is
## started with, revoked when it ends, so nothing left running in the add-on can change the game
## afterwards, while the hooks given can start another conversation.
##
## A conversation that goes wrong never holds the game: an error logged while a line is being found
## (a refused or missing call, a call with the wrong arguments) ends it at once, and so does waiting
## more than `WATCHDOG_SECONDS` for a line. The add-on reports those errors; the runner reports a
## missing cue and the watchdog. `ended_in_error()` tells such an end from a normal one.

## A line is shown. `choices` lists the open choices in order; it is empty for a plain line.
signal line_shown(speaker: String, text: String, choices: Array[String])
## The conversation ended: it ran out, went wrong, or `stop()` was called.
signal finished

## Real seconds the runner waits for a line before it gives the conversation up.
const WATCHDOG_SECONDS: float = 2.0
const _ONLY_HOOKS: String = "A conversation may only use the story hooks, not %s.%s"


## Notes errors logged by anyone, so the runner can tell that a line request went wrong.
class ErrorWatch extends Logger:
	var seen: bool = false

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			seen = true


var _resource: DialogueResource
var _hooks: StoryHooks
var _running: bool = false
## The line on show, or null while the next one is being found.
var _line: DialogueLine
## The open choices of the line on show.
var _choices: Array[DialogueResponse] = []
## Counts the lines asked for, so a line that arrives after a stop or a newer request is dropped.
var _request: int = 0
## When the line being found was asked for, in milliseconds since start; −1 while none is awaited.
var _waiting_since: int = -1
var _ended_in_error: bool = false
var _errors := ErrorWatch.new()


func _enter_tree() -> void:
	OS.add_logger(_errors)


func _exit_tree() -> void:
	OS.remove_logger(_errors)


func _process(_delta: float) -> void:
	if _waiting_since >= 0 and Time.get_ticks_msec() - _waiting_since > WATCHDOG_SECONDS * 1000.0:
		push_error("The conversation waited more than %.0f s for its next line; it is ended" % WATCHDOG_SECONDS)
		_end(true)


## Starts the conversation at the cue `title` of `resource`, a compiled `.dialogue` file. Ignored
## while a conversation runs. A missing cue is an error that ends the conversation at once.
func start(resource: Resource, title: String, hooks: StoryHooks) -> void:
	if _running:
		return
	_confine_the_add_on()
	_resource = resource as DialogueResource
	_hooks = hooks.copy()
	_running = true
	_ended_in_error = false
	if _resource == null or not _resource.cues.has(title):
		push_error("The conversation %s has no cue %s" % [resource, title])
		_end(true)
		return
	_fetch(title)


## Goes on from a plain line. Does nothing on a line with choices, or while no line is on show.
func advance() -> void:
	if _line == null or not _choices.is_empty():
		return
	_fetch(_line.next_id)


## Takes the open choice at `index` of the line on show. Does nothing for an index out of range.
func choose(index: int) -> void:
	if _line == null or index < 0 or index >= _choices.size():
		return
	_fetch(_choices[index].next_id)


## Ends the conversation without running anything further and emits `finished`.
func stop() -> void:
	_end(false)


func is_running() -> bool:
	return _running


## Whether the last conversation ended because it went wrong or its next line never came.
func ended_in_error() -> bool:
	return _ended_in_error


## Ends the conversation, revoking its hooks, and emits `finished`.
func _end(in_error: bool) -> void:
	if not _running:
		return
	_running = false
	_ended_in_error = in_error
	_request += 1
	_waiting_since = -1
	_line = null
	_choices = []
	_resource = null
	_hooks.revoke()
	_hooks = null
	finished.emit()


## Asks the add-on for the next line from `key`, running any mutations on the way, and shows it;
## ends the conversation when there is none.
func _fetch(key: String) -> void:
	_request += 1
	var request: int = _request
	_line = null
	_choices = []
	_waiting_since = Time.get_ticks_msec()
	_errors.seen = false
	var line: DialogueLine = await _manager().get_next_dialogue_line(_resource, key, [_hooks])
	if request != _request:
		return
	_waiting_since = -1
	if _errors.seen or line == null:
		_end(_errors.seen)
		return
	_line = line
	var texts: Array[String] = []
	for response: DialogueResponse in line.responses:
		if response.is_allowed:
			_choices.append(response)
			texts.append(response.text)
	line_shown.emit(line.character, line.text, texts)


## Narrows what conversations can reach to the hooks passed with each line request.
func _confine_the_add_on() -> void:
	var manager: Node = _manager()
	manager.get_current_scene = Callable()
	manager.load_from_within_dialogue = Callable()
	manager.include_singletons = false
	manager.include_classes = false
	# A refused or missing call is reported as an error and the line goes on, in debug builds too.
	manager.ignore_missing_state_values = true
	manager.validate_member_access = func(thing: Variant, member: StringName, _kind: StringName) -> String:
		return "" if thing is StoryHooks else _ONLY_HOOKS % [thing, member]


func _manager() -> Node:
	return Engine.get_singleton(&"DialogueManager") as Node
