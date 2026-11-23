# tests/story/test_fight_balance.gd
extends GutTest
## The vault's fight needs the Blood: scripted players (`VaultFight`) play the story's vault over varied
## runs, and plain clicking must lose while playing with the Rites and feeding wins, from any Blood the
## story can bring. Each row plays `RUNS` fights (the environment's `FIGHT_RUNS` overrides it, as for
## the ten-run table) and prints its table.

## Fights per row in the suite; the full table is played with FIGHT_RUNS=10.
const RUNS: int = 6
## The longest a scripted fight may take, in seconds of game time.
const LIMIT: float = 150.0

var main: Main


func after_each() -> void:
	VaultFight.slow_down()
	Story.finish(main)


func _runs() -> int:
	var asked: String = OS.get_environment("FIGHT_RUNS")
	return int(asked) if asked.is_valid_int() and int(asked) > 0 else RUNS


## Plays one fight from `start` as `kind`, seeded with `seed_value`.
func _fight(start: VaultFight.Start, kind: VaultFight.Kind, seed_value: int) -> Dictionary:
	if is_instance_valid(main):
		Story.finish(main)
		main.queue_free()
		await wait_physics_frames(2)
	seed(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	main = Story.boot(self, VaultFight.state_for(start))
	await wait_physics_frames(3)
	VaultFight.jitter(main, rng)
	VaultFight.speed_up()
	var script := VaultFight.new(main, kind)
	var result: Dictionary = await script.play(self, LIMIT)
	VaultFight.slow_down()
	return result


## Plays a row and prints its table line; returns the runs.
func _row(label: String, start: VaultFight.Start, kind: VaultFight.Kind) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	for run: int in _runs():
		runs.append(await _fight(start, kind, 1000 + run))
	gut.p(_table_line(label, runs))
	return runs


static func _count(runs: Array[Dictionary], outcome: String) -> int:
	return runs.filter(func(r: Dictionary) -> bool: return r.outcome == outcome).size()


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	var mid: int = sorted.size() / 2
	return sorted[mid] if sorted.size() % 2 == 1 else (sorted[mid - 1] + sorted[mid]) / 2.0


static func _table_line(label: String, runs: Array[Dictionary]) -> String:
	var pick := func(key: String) -> Array: return runs.map(func(r: Dictionary) -> Variant: return r[key])
	var won: Array = runs.filter(func(r: Dictionary) -> bool: return r.outcome == "cleared").map(
			func(r: Dictionary) -> float: return r.time)
	var lost: Array = runs.filter(func(r: Dictionary) -> bool: return r.outcome == "fall").map(
			func(r: Dictionary) -> float: return r.time)
	return ("BALANCE | %s | runs %d | cleared %d | fall %d | left %d | timeout %d | median time %.1f s"
			+ " (won %.1f, fell %.1f) | Alvar health %.0f, Blood %.0f | feeds %.1f | Rites %.1f (companions %.1f)"
			+ " | Furies %d | times %s | outcomes %s") % [
		label, runs.size(), _count(runs, "cleared"), _count(runs, "fall"), _count(runs, "left"),
		_count(runs, "timeout"), _median(pick.call("time")), _median(won), _median(lost),
		_median(pick.call("health")), _median(pick.call("blood")), _median(pick.call("feeds")),
		_median(pick.call("rites")), _median(pick.call("companion_rites")),
		pick.call("furies").reduce(func(a: int, b: int) -> int: return a + b, 0),
		pick.call("time").map(func(t: float) -> String: return "%.0f" % t),
		pick.call("outcome"),
	]


## At least `share` of `runs` (rounded up), as "7 of 10" scales to the suite's run count.
static func _at_least(share: float, runs: int) -> int:
	return ceili(share * runs - 0.0001)


func test_a_clicker_with_the_least_blood_falls() -> void:
	var runs: Array[Dictionary] = await _row("spared, clicker", VaultFight.Start.SPARED, VaultFight.Kind.CLICKER)
	assert_eq(_count(runs, "timeout"), 0, "no fight stalls")
	assert_gte(_count(runs, "fall"), _at_least(0.7, runs.size()), "the clicker falls in 7 of 10")


func test_a_player_with_the_least_blood_clears_in_45_to_90_seconds() -> void:
	var runs: Array[Dictionary] = await _row("spared, player", VaultFight.Start.SPARED, VaultFight.Kind.PLAYER)
	var in_time: int = runs.filter(func(r: Dictionary) -> bool:
		return r.outcome == "cleared" and r.time >= 45.0 and r.time <= 90.0).size()
	assert_gte(in_time, _at_least(0.8, runs.size()), "the player clears in 8 of 10, in 45-90 s")


func test_a_player_who_drained_the_captive_clears() -> void:
	var runs: Array[Dictionary] = await _row("drained, player", VaultFight.Start.DRAINED, VaultFight.Kind.PLAYER)
	assert_gte(_count(runs, "cleared"), _at_least(0.9, runs.size()), "the player clears in 9 of 10")


func test_a_player_with_no_blood_at_all_can_feed_his_way_out() -> void:
	var runs: Array[Dictionary] = await _row("dry, player", VaultFight.Start.DRY, VaultFight.Kind.PLAYER)
	assert_gte(_count(runs, "cleared"), _at_least(0.6, runs.size()), "the player clears in 6 of 10")


func test_a_coward_reaches_the_fragua() -> void:
	var runs: Array[Dictionary] = await _row("spared, coward", VaultFight.Start.SPARED, VaultFight.Kind.COWARD)
	var turned: Array[Dictionary] = runs.filter(func(r: Dictionary) -> bool: return r.turned)
	gut.p("BALANCE | coward turned in %d of %d" % [turned.size(), runs.size()])
	assert_gt(turned.size(), 0, "he turned at least once")
	assert_gte(_count(turned, "left"), _at_least(0.8, turned.size()), "once he turns, he reaches the Fragua in 8 of 10")
