class_name DialogueRunner
extends Node
## Runs one conversation at a time through the Dialogue Manager add-on, the only place that knows the
## add-on's API: shows each line with the choices whose condition holds, and goes on when told to.
##
## A conversation reaches the game only through the `StoryHooks` it is started with: the add-on is
## told not to look in the current scene, singletons, classes or autoloads, and not to load files.
## Lines and choices are given as written.

## A line is shown. `choices` lists the open choices in order; it is empty for a plain line.
signal line_shown(speaker: String, text: String, choices: Array[String])
## The conversation ended: it ran out, or `stop()` was called.
signal finished

const _ONLY_HOOKS: String = "A conversation may only use the story hooks, not %s.%s"

var _resource: DialogueResource
var _hooks: StoryHooks
var _running: bool = false
## The line on show, or null while the next one is being found.
var _line: DialogueLine
## The open choices of the line on show.
var _choices: Array[DialogueResponse] = []
## Counts the lines asked for, so a line that arrives after a stop or a newer request is dropped.
var _request: int = 0


## Starts the conversation at the cue `title` of `resource`, a compiled `.dialogue` file. Ignored
## while a conversation runs.
func start(resource: Resource, title: String, hooks: StoryHooks) -> void:
	if _running:
		return
	_confine_the_add_on()
	_resource = resource as DialogueResource
	_hooks = hooks
	_running = true
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
	if not _running:
		return
	_running = false
	_request += 1
	_line = null
	_choices = []
	_resource = null
	_hooks = null
	finished.emit()


func is_running() -> bool:
	return _running


## Asks the add-on for the next line from `key`, running any mutations on the way, and shows it;
## ends the conversation when there is none.
func _fetch(key: String) -> void:
	_request += 1
	var request: int = _request
	_line = null
	_choices = []
	var line: DialogueLine = await _manager().get_next_dialogue_line(_resource, key, [_hooks])
	if request != _request:
		return
	if line == null:
		stop()
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
	manager.validate_member_access = func(thing: Variant, member: StringName, _kind: StringName) -> String:
		return "" if thing is StoryHooks else _ONLY_HOOKS % [thing, member]


func _manager() -> Node:
	return Engine.get_singleton(&"DialogueManager") as Node
