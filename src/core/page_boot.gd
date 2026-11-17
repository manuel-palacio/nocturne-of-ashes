class_name PageBoot
extends RefCounted
## What the page's parameters do to how `Main` starts; applied before `Main` is ready. Off the web
## there are none, and `Main` starts as it was set up.
##
## - `skirmish=1`: the vault skirmish, with no title and no save, whatever scene holds `Main`.
## - `fresh=1`: in a story, the save is cleared before anything reads it.
## - `probe=1`: in a story, the title is skipped, unless `title=1`: the game goes on from a usable
##   save, else starts new.
## - `at=vault`, with `probe=1` and `fresh=1`: the story starts as `haven_finished()`, with no opening.

## The story flags set by the end of the haven.
const HAVEN_FLAGS: Array[StringName] = [
	&"met_malakor", &"zahra_joined", &"gonzalo_joined", &"captive_done", &"order_given",
]


static func configure(main: Main) -> void:
	if PageParams.is_on("skirmish"):
		main.boot = Main.Boot.SKIRMISH
		main.state = GameState.skirmish()
		main.store = null
		return
	if main.boot != Main.Boot.STORY:
		return
	var fresh: bool = PageParams.is_on("fresh")
	if fresh:
		_store(main).clear()
	if not PageParams.is_on("probe"):
		return
	main.show_title = PageParams.is_on("title")
	if fresh and PageParams.value("at") == "vault":
		main.state = haven_finished()
		main.opening_enabled = false
	elif main.state == null:
		main.state = _store(main).load_state()


## A story state as if the haven were finished: everyone has joined, Álvar knows both his Gifts, the
## haven's flags are set, and the party is entering the vault from the haven.
static func haven_finished() -> GameState:
	var state := GameState.new_game()
	for member: StringName in GameState.MEMBERS:
		state.join(member)
		for gift: StringName in GameState.ALL_GIFTS[member]:
			state.learn(member, gift)
	for flag: StringName in HAVEN_FLAGS:
		state.set_flag(flag)
	state.room = &"vault"
	state.entry = &"from_haven"
	return state


## The store of `main`, made now if it has none yet.
static func _store(main: Main) -> SaveStore:
	if main.store == null:
		main.store = SaveStore.new()
	return main.store
