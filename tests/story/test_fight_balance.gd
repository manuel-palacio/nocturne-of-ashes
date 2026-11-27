# tests/story/test_fight_balance.gd
extends GutTest
## The vault's fight needs the Blood, the steel and the Rites: scripted people (`VaultFight`), clicking
## once a second, play the story's vault over varied runs. Each row plays `RUNS` fights (row B
## `PLAYER_RUNS`; the environment's `FIGHT_RUNS` overrides both, `FIGHT_SEED` moves the first seed from
## 1000), prints its line, and asserts its bar scaled to the runs played. A row is replayed once
## before failing: under load a run can drift; a regression fails both. A row that misses a bar is
## played again from a fresh game with the same seeds, both plays' lines are printed, and the test
## holds the second play to the same bars (`_row()`).
##
## Bars and measurements. The design targets are fixed; each bar is one win looser than the worse of two
## measured 10-run passes (a ceiling one looser than the higher), and never looser than the target's
## limit. Measured with the numbers of fix round 4, the file's own row order, seeds 1000-1009 / 1010-1019:
##
##   row  bar (of 10)                      measured            limit
##   A    clears <= 1                      0 / 0               <= 4
##   B    clears >= 6                      7 / 8               >= 6
##        median end health <= 90 of 120   80 / 73             <= 90
##        median won time 35-75 s          39.0 / 40.0 s       35-75 s
##        a companion fallen in >= 2 runs  3 / 2               >= 2 (**)
##   C    clears <= 6; B - C >= 4 of 20    4 / 5; 15 - 9 = 6   <= 6; >= 4
##   D    falls >= 9                       10 / 10             >= 7
##   E    clears >= 8                      10 / 9              >= 4
##   F    clears >= 5                      10 / 6              >= 4 (*)
##   G    reaches the Fragua >= 8, turned  10 / 9              >= 7
##   H    clears >= 8                      10 / 10 (*3)        >= 8
##   I    clears >= 6                      10 / 10 (*3)        >= 6
##
## (*) F's limit is 4: by the owner's ruling the drained start is equal to the spared one within noise
## while Blood is plentiful (a feed gives 80); a review measured 15 of 20 against 13 of 20.
##
## (*3) Rows H and I play at the tiring floor, `Main.TIRING_FLOOR`; measured at 0.15. Row I, the spam
## clicker with every member at 0 Blood, is the floor under "nobody gets stuck" for the weakest start;
## its bar, 6 of 10, is the owner's, and the floor was lowered until H and I both held it with a win to
## spare. Row I at ten runs, seeds 1000-1009 / 1010-1019: floor 0.5, 0 / 0 (falls in 12-16 s); 0.3, 2;
## 0.2, 3; 0.17, 8 / 8; 0.15, 10 / 10; 0.1, 10. H at 0.5 was 10 / 9. The tiring guard loses health, not
## damage, so a dry party with no Rites wins only once the guard dies in a blow or two: a steep step
## between 0.2 and 0.15. At 0.15 the floor is reached at the seventh fall (was the fifth).
##
## (**) B's fallen-companion limit is 2 runs in 10, by the controller's ruling: wins still cost something,
## as Álvar ends at 73-80 of 120.
##
## Not bars, measured: the dry start's won fights take 43.7 / 42.0 s against the player's 39.0 / 40.0 s;
## no Fury in any row. Row run-to-run spread is about two wins in ten. At the suite's five runs per row the
## rounding up of `_at_least` makes rows D, E and H stricter than their ten-run rate (9 of 10 becomes 5 of
## 5; 8 of 10, 4 of 5): after a retune, re-measure at ten runs before trusting a failure there.

## Fights per row in the suite; the full table is played with FIGHT_RUNS=10.
const RUNS: int = 5
## Row B, the player whom rows C and E are held against, plays the full ten in the suite: its wins hang
## near its bar, and five seeds are too few to tell 8 of 10 from 6.
const PLAYER_RUNS: int = 10
## The longest a scripted fight may take, in seconds of game time.
const LIMIT: float = 180.0

## Rows already played in this run of the file, by label: row C is held against row B. A member, not a
## static: GUT runs every test of the file on one instance, and a static left the instance orphaned.
var _played: Dictionary = {}

var main: Main


func after_each() -> void:
	VaultFight.slow_down()
	Story.finish(main)


## The first seed: 1000, or the environment's `FIGHT_SEED` (a second pass plays 1010 on).
func _seed_base() -> int:
	var asked: String = OS.get_environment("FIGHT_SEED")
	return int(asked) if asked.is_valid_int() else 1000


func _runs(fallback: int = RUNS) -> int:
	var asked: String = OS.get_environment("FIGHT_RUNS")
	return int(asked) if asked.is_valid_int() and int(asked) > 0 else fallback


## Plays one fight from `start` as `kind`, seeded with `seed_value`; with `tired`, after as many falls
## as bring the guard to the tiring floor.
func _fight(start: VaultFight.Start, kind: VaultFight.Kind, seed_value: int, tired: bool) -> Dictionary:
	if is_instance_valid(main):
		Story.finish(main)
		main.queue_free()
		await wait_physics_frames(2)
	seed(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	main = Story.boot(self, VaultFight.state_for(start))
	await wait_physics_frames(3)
	if tired:
		while main.guard_health() > Main.TIRING_FLOOR:
			main.player.take_hit(Arena.LETHAL)
			await wait_physics_frames(1)
			main.reload_checkpoint()
			await wait_physics_frames(3)
	await VaultFight.settle(self, main)
	VaultFight.jitter(main, rng)
	VaultFight.speed_up()
	var script := VaultFight.new(main, kind)
	var result: Dictionary = await script.play(self, LIMIT)
	VaultFight.slow_down()
	return result


## Plays a row (or returns it, played before in this run) and prints its table line. `misses` gives
## the row's bars it misses, as messages (none when it holds them): a row that misses any is played
## once more from a fresh game, both plays printed, and the second play is the row's.
func _row(label: String, start: VaultFight.Start, kind: VaultFight.Kind, misses: Callable,
		tired: bool = false, runs_in_suite: int = RUNS) -> Array[Dictionary]:
	if _played.has(label):
		return _played[label]
	var runs: Array[Dictionary] = await _play_row(start, kind, tired, runs_in_suite)
	gut.p(_table_line(label, runs))
	var missed: Array[String] = misses.call(runs)
	if not missed.is_empty():
		gut.p("BALANCE | %s | first play missed: %s | replaying once" % [label, "; ".join(missed)])
		runs = await _play_row(start, kind, tired, runs_in_suite)
		gut.p(_table_line(label + " (replay)", runs))
		missed = misses.call(runs)
		gut.p("BALANCE | %s | replay %s" % [label, "missed: " + "; ".join(missed) if not missed.is_empty() else "held every bar"])
	_played[label] = runs
	return runs


func _play_row(start: VaultFight.Start, kind: VaultFight.Kind, tired: bool, runs_in_suite: int) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for run: int in _runs(runs_in_suite):
		runs.append(await _fight(start, kind, _seed_base() + run, tired))
	return runs


## Each message of `checks`, pairs of [holds, message], whose check does not hold.
static func _failed(checks: Array) -> Array[String]:
	var failed: Array[String] = []
	for check: Array in checks:
		if not check[0]:
			failed.append(check[1])
	return failed


static func _count(runs: Array[Dictionary], outcome: String) -> int:
	return runs.filter(func(r: Dictionary) -> bool: return r.outcome == outcome).size()


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var mid: int = sorted.size() / 2
	return sorted[mid] if sorted.size() % 2 == 1 else (sorted[mid - 1] + sorted[mid]) / 2.0


static func _pick(runs: Array[Dictionary], key: String) -> Array:
	return runs.map(func(r: Dictionary) -> Variant: return r[key])


static func _table_line(label: String, runs: Array[Dictionary]) -> String:
	var won: Array = _pick(runs.filter(func(r: Dictionary) -> bool: return r.outcome == "cleared"), "time")
	return ("BALANCE | %s | runs %d | cleared %d | fall %d | left %d | timeout %d | median time %.1f s (won %.1f)"
			+ " | Alvar health %.0f, Blood %.0f | companions fallen in %d runs | feeds %.1f | Rites %.1f"
			+ " (companions %.1f) | Furies %d in %d runs | %s") % [
		label, runs.size(), _count(runs, "cleared"), _count(runs, "fall"), _count(runs, "left"),
		_count(runs, "timeout"), _median(_pick(runs, "time")), _median(won),
		_median(_pick(runs, "health")), _median(_pick(runs, "blood")),
		runs.filter(func(r: Dictionary) -> bool: return r.companions_fallen > 0).size(),
		_median(_pick(runs, "feeds")), _median(_pick(runs, "rites")), _median(_pick(runs, "companion_rites")),
		_pick(runs, "furies").reduce(func(a: int, b: int) -> int: return a + b, 0),
		runs.filter(func(r: Dictionary) -> bool: return r.furies > 0).size(),
		" ".join(runs.map(func(r: Dictionary) -> String: return "%s%.0f" % [r.outcome.left(1), r.time])),
	]


## At least `share` of `runs`, rounded up: "8 of 10" scaled to the runs played.
static func _at_least(share: float, runs: int) -> int:
	return ceili(share * runs - 0.0001)


## At most `share` of `runs`, rounded down.
static func _at_most(share: float, runs: int) -> int:
	return floori(share * runs + 0.0001)


static func _won_time(runs: Array[Dictionary]) -> float:
	return _median(_pick(runs.filter(func(r: Dictionary) -> bool: return r.outcome == "cleared"), "time"))


# --- The rows' bars, each the messages of those a play misses ---

static func _a_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([
		[_count(runs, "timeout") == 0, "no fight stalls"],
		[_count(runs, "cleared") <= _at_most(0.1, runs.size()), "the spam clicker clears at most 1 of 10"],
	])


static func _b_misses(runs: Array[Dictionary]) -> Array[String]:
	var won_time: float = _won_time(runs)
	var lost: int = runs.filter(func(r: Dictionary) -> bool: return r.companions_fallen > 0).size()
	return _failed([
		[_count(runs, "cleared") >= _at_least(0.6, runs.size()), "the player clears 6 of 10"],
		[won_time >= 35.0 and won_time <= 75.0, "a won fight takes 35-75 s (%.1f)" % won_time],
		[_median(_pick(runs, "health")) <= 0.75 * 120,
				"Álvar ends with at most three quarters of his health (%.0f)" % _median(_pick(runs, "health"))],
		[lost >= _at_least(0.2, runs.size()), "a companion falls in 2 of 10"],
	])


## Row C's bars, held against `player`, row B as played.
static func _c_misses(runs: Array[Dictionary], player: Array[Dictionary]) -> Array[String]:
	var share: float = float(_count(runs, "cleared")) / runs.size()
	return _failed([
		[_count(runs, "cleared") <= _at_most(0.6, runs.size()), "without the Rites he clears at most 6 of 10"],
		[float(_count(player, "cleared")) / player.size() - share >= 0.2 - 0.0001, "the Rites are worth 4 wins in 20"],
	])


static func _d_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([[_count(runs, "fall") >= _at_least(0.9, runs.size()), "without feeding he falls 9 of 10"]])


static func _e_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([[_count(runs, "cleared") >= _at_least(0.8, runs.size()), "with no Blood he clears 8 of 10"]])


static func _f_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([[_count(runs, "cleared") >= _at_least(0.5, runs.size()), "after draining he clears 5 of 10"]])


static func _g_misses(runs: Array[Dictionary]) -> Array[String]:
	var turned: Array[Dictionary] = runs.filter(func(r: Dictionary) -> bool: return r.turned)
	return _failed([
		[turned.size() > 0, "he turned at least once"],
		[_count(turned, "left") >= _at_least(0.8, turned.size()), "once he turns, he reaches the Fragua 8 of 10"],
	])


static func _h_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([[_count(runs, "cleared") >= _at_least(0.8, runs.size()), "at the floor the spam clicker clears 8 of 10"]])


static func _i_misses(runs: Array[Dictionary]) -> Array[String]:
	return _failed([[_count(runs, "cleared") >= _at_least(0.6, runs.size()),
			"at the floor the dry spam clicker clears 6 of 10"]])


# --- The rows ---

func _player_row() -> Array[Dictionary]:
	return await _row("B spared, player", VaultFight.Start.SPARED, VaultFight.Kind.PLAYER, _b_misses, false, PLAYER_RUNS)


func test_a_spam_clicker_rarely_wins() -> void:
	var runs: Array[Dictionary] = await _row("A spared, spam clicker", VaultFight.Start.SPARED, VaultFight.Kind.SPAM, _a_misses)
	assert_eq(_a_misses(runs), [] as Array[String])


func test_the_player_wins_hurt() -> void:
	var runs: Array[Dictionary] = await _player_row()
	assert_eq(_b_misses(runs), [] as Array[String])


func test_without_the_rites_the_player_mostly_loses() -> void:
	var player: Array[Dictionary] = await _player_row()
	var misses := func(runs: Array[Dictionary]) -> Array[String]: return _c_misses(runs, player)
	var runs: Array[Dictionary] = await _row("C spared, no Rites", VaultFight.Start.SPARED, VaultFight.Kind.NO_RITES, misses)
	assert_eq(_c_misses(runs, player), [] as Array[String])


func test_without_feeding_the_player_falls() -> void:
	var runs: Array[Dictionary] = await _row("D spared, never feeds", VaultFight.Start.SPARED, VaultFight.Kind.NO_FEED, _d_misses)
	assert_eq(_d_misses(runs), [] as Array[String])


func test_with_no_blood_the_player_feeds_his_way_out() -> void:
	var player: Array[Dictionary] = await _player_row()
	var runs: Array[Dictionary] = await _row("E dry, player", VaultFight.Start.DRY, VaultFight.Kind.PLAYER, _e_misses)
	assert_eq(_e_misses(runs), [] as Array[String])
	gut.p("BALANCE | dry won fights %.1f s against the player's %.1f s" % [_won_time(runs), _won_time(player)])


func test_a_player_who_drained_the_captive_clears() -> void:
	var runs: Array[Dictionary] = await _row("F drained, player", VaultFight.Start.DRAINED, VaultFight.Kind.PLAYER, _f_misses)
	assert_eq(_f_misses(runs), [] as Array[String])


func test_a_coward_reaches_the_fragua() -> void:
	var runs: Array[Dictionary] = await _row("G spared, coward", VaultFight.Start.SPARED, VaultFight.Kind.COWARD, _g_misses)
	var turned: Array[Dictionary] = runs.filter(func(r: Dictionary) -> bool: return r.turned)
	gut.p("BALANCE | coward turned in %d of %d" % [turned.size(), runs.size()])
	assert_eq(_g_misses(runs), [] as Array[String])


func test_at_the_tiring_floor_even_the_spam_clicker_wins() -> void:
	var runs: Array[Dictionary] = await _row("H spam clicker, guard at the floor", VaultFight.Start.SPARED,
			VaultFight.Kind.SPAM, _h_misses, true)
	assert_eq(_h_misses(runs), [] as Array[String])


func test_at_the_tiring_floor_even_a_dry_spam_clicker_wins() -> void:
	var runs: Array[Dictionary] = await _row("I dry spam clicker, guard at the floor", VaultFight.Start.DRY,
			VaultFight.Kind.SPAM, _i_misses, true)
	assert_eq(_i_misses(runs), [] as Array[String])
