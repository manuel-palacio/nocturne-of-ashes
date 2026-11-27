class_name Hints
extends Node
## The fight's rules, taught once each at the moment they first apply: a hint is the HUD's notice, drawn
## in the hints' band (`Hud.show_hint()`), on show for `SHOW_TIME`, at most one every `GAP` seconds, the most urgent first (`ORDER`). A hint
## applies while its moment lasts (an enemy is marked, Álvar's Blood is under a third, ...): one that
## falls due while the world is held by a conversation, the controls or closing card, the fall prompt
## or the title, or while another notice is up, waits; if its moment passes meanwhile it is dropped,
## and comes when it next applies. A hint on show is put away when one of those opens, and a game
## notice shown over it replaces it. A Rite the player uses before its hint counts the Rites hint as
## seen without showing. A feed does not count (a clicker feeds by chance): the player's first feed
## before the feeding hint has shown makes that hint due as if an enemy were marked, so it comes as
## soon as it may and explains what just happened. Running dry, Álvar's alone (the companions' brains
## feed on their own), says "Feed" and so never comes before the feeding hint: when it falls due first,
## the feeding hint is due instead, and running dry waits its turn.
##
## In a story each hint seen is a flag of the state (`flag()`), kept by `Main.keep_flag()` so that a
## fall or a reload does not bring it back; a new game starts them afresh. In a skirmish, which has no
## save, they are remembered for as long as this node lives: once per page load. The door hint is the
## story's alone, as only the story's doors lead anywhere.

## A hint was shown; `id` is one of `ORDER`.
signal shown(id: StringName)

## Seconds a hint stays on show, unless a notice or a card takes its place.
const SHOW_TIME: float = 5.0
## The fewest seconds from one hint's start to the next's.
const GAP: float = 6.0
## Seconds into a fight, from its first blow, before the Rites hint is due.
const RITE_DELAY: float = 4.0
## A sergeant this near a party member, flat, in metres, in a fight, brings the sergeant hint.
const SERGEANT_NEAR: float = 6.0
## Every hint, most urgent first.
const ORDER: Array[StringName] = [&"door", &"sergeant", &"feed", &"rites", &"dry", &"fury", &"pause"]
## Each hint's text, an English source text; `%s` is the member it is about.
const TEXTS: Dictionary = {
	&"pause": "Space pauses the fight: give your orders, then let it run.",
	&"rites": "1: Iron Sinew, to strike harder. 2: Baleful Eye, then click a foe to still him.",
	&"sergeant": "The helmed sergeants hit hardest. Still one with Baleful Eye, and drink when he weakens.",
	&"feed": "Click a weakened foe to feed: it restores Blood and mends wounds.",
	&"dry": "%s is running dry. Feed, or the Fury will choose for you.",
	&"fury": "The Fury has %s. It ends when the hunger is fed or burns out.",
	&"door": "The west door is a way out. The guard will close ranks again.",
}

var _party: Party
var _encounter: Encounter
var _hud: Hud
## Whether the screen is held by something no hint may show over.
var _held: Callable
## Keeps a flag in the story's state and its checkpoint, as `Main.keep_flag()`.
var _keep: Callable
var _state: GameState
var _story: bool = false
## In a skirmish, the hints seen since this node was made, by id.
var _seen_here: Dictionary = {}  # StringName -> true
## The hint on show, or empty.
var _on_show: StringName = &""
## Whether the player fed before the feeding hint showed, which makes it due until it shows.
var _fed_unhinted: bool = false
## Seconds since the last hint was shown.
var _since_last: float = GAP


## Called once by `Main`, before any room: what to watch, where to show, what holds the screen
## (`held`, called each tick) and how a story keeps a flag (`keep`, called with the flag).
func setup(party: Party, encounter: Encounter, hud: Hud, held: Callable, keep: Callable) -> void:
	_party = party
	_encounter = encounter
	_hud = hud
	_held = held
	_keep = keep
	party.member_added.connect(_watch)


## Follows the room just entered, with `state`, the state `Main` now holds, in a story when `story`.
## Called at each room start, once the party is in place.
func begin_room(state: GameState, story: bool) -> void:
	_state = state
	_story = story
	_on_show = &""
	_fed_unhinted = false
	for member: Unit in _party.members:
		_watch(member)


## The state flag that records the hint `id` as seen.
static func flag(id: StringName) -> StringName:
	return StringName("hint_%s" % id)


## Whether the hint `id` has been seen, or counted as seen.
func is_seen(id: StringName) -> bool:
	if _story:
		return _state != null and _state.has_flag(flag(id))
	return _seen_here.has(id)


## The hint on show, or empty.
func on_show() -> StringName:
	return _on_show


func _physics_process(delta: float) -> void:
	_since_last += delta
	if _state == null or _party.leader == null:
		return
	if _on_show != &"" and _hud.notice() != TEXTS[_on_show]:
		_on_show = &""
	if _held.call():
		if _on_show != &"":
			_hud.hide_notice()
			_on_show = &""
		return
	if _since_last < GAP or not _hud.notice().is_empty():
		return
	for id: StringName in ORDER:
		if is_seen(id):
			continue
		if _applies(id):
			_show(id)
			return


func _show(id: StringName) -> void:
	var about: Unit = _about(id)
	var args: Array = [about.display_name] if about != null else []
	_remember(id)
	_on_show = id
	_since_last = 0.0
	_hud.show_hint(TEXTS[id], args, SHOW_TIME)
	shown.emit(id)


func _remember(id: StringName) -> void:
	if is_seen(id):
		return
	if _story:
		_keep.call(flag(id))
	else:
		_seen_here[id] = true


## Whether the hint `id` applies now.
func _applies(id: StringName) -> bool:
	var leader: Unit = _party.leader
	if not leader.is_alive():
		return false
	if id == &"fury":
		return _about(id) != null
	if _encounter.is_cleared() or _encounter.enemies_alive() == 0:
		return false
	var fighting: bool = _encounter.fight_time() >= 0.0
	match id:
		&"pause":
			return true
		&"rites":
			return fighting and _encounter.fight_time() >= RITE_DELAY and _rite_ready(leader)
		&"sergeant":
			return fighting and _sergeant_near()
		&"feed":
			return _fed_unhinted or _running_dry(leader) or _encounter.enemies.any(
					func(enemy: Unit) -> bool: return enemy.has_feed_mark())
		&"dry":
			return is_seen(&"feed") and _about(id) != null
		&"door":
			# Under half, with time left to reach the door.
			return _story and fighting and leader.stats.health * 2 < leader.stats.max_health
	return false


## The member the hint `id` is about (whom the Fury has; Álvar, when he is running dry); null for the
## others.
func _about(id: StringName) -> Unit:
	match id:
		&"fury":
			return _first_member(func(member: Unit) -> bool: return member.is_in_fury())
		&"dry":
			var leader: Unit = _party.leader
			return leader if leader.is_alive() and _running_dry(leader) else null
	return null


## Whether `member`'s Blood is under a third.
static func _running_dry(member: Unit) -> bool:
	return member.stats.blood * 3 < member.stats.max_blood


## The first living member, Álvar first, for whom `test` holds; null when none.
func _first_member(test: Callable) -> Unit:
	for member: Unit in _party.members:
		if member.is_alive() and test.call(member):
			return member
	return null


## Whether the selected member is Álvar and one of his Rites could be called now.
func _rite_ready(leader: Unit) -> bool:
	if _party.selected != leader:
		return false
	var gifts := leader.get_node_or_null(^"Gifts") as GiftUser
	if gifts == null:
		return false
	for index: int in gifts.count():
		if gifts.is_ready(index):
			return true
	return false


func _sergeant_near() -> bool:
	for enemy: Unit in _encounter.enemies:
		if not enemy.is_alive() or not Encounter.is_sergeant(enemy):
			continue
		for member: Unit in _party.members:
			var gap: Vector3 = enemy.global_position - member.global_position
			if member.is_alive() and Vector2(gap.x, gap.z).length() <= SERGEANT_NEAR:
				return true
	return false


## Hears of `member`'s Rites and feeds, those the player makes.
func _watch(member: Unit) -> void:
	var on_fed: Callable = _on_fed.bind(member)
	if not member.fed.is_connected(on_fed):
		member.fed.connect(on_fed)
	var gifts := member.get_node_or_null(^"Gifts") as GiftUser
	var on_gift_used: Callable = _on_gift_used.bind(member)
	if gifts != null and not gifts.gift_used.is_connected(on_gift_used):
		gifts.gift_used.connect(on_gift_used)


## A Rite called by the player (the selected member's: the others' are their brains') teaches the keys.
func _on_gift_used(_index: int, _target: Unit, member: Unit) -> void:
	if member == _party.selected and _state != null:
		_remember(&"rites")


## A feed of the player's own before the feeding hint makes the hint due, to explain it.
func _on_fed(_target: Unit, member: Unit) -> void:
	if member == _party.selected and _state != null and not is_seen(&"feed"):
		_fed_unhinted = true
