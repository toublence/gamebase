extends SceneTree
## Rule tests for "arrow-path-2". Run: godot --headless --path . -s res://tests/arrow_core_tests.gd
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _init() -> void:
	_test_shapes_and_heads()
	_test_escape_rules()
	_test_track()
	_test_structure_validation()
	_test_session()
	_test_save_restore()
	_test_generator()
	_test_shaped_generator()
	_test_fast_solver()
	_test_escape_events()
	_test_league_rules()
	_test_silhouettes()
	_test_checkpoint_and_warning()
	_test_first_hard_board()
	print("ARROW_CORE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _level(w: int, h: int, tokens: Array) -> Dictionary:
	var level := ArrowLevel.parse_authoring(w, h, PackedStringArray(tokens))
	level["id"] = "t"
	level["hash"] = ArrowLevel.content_hash(level)
	return level

func _test_shapes_and_heads() -> void:
	# straight, L, zigzag, U
	var board := ArrowBoard.from_level(_level(8, 8, ["0,0:RRR", "0,2:RRDD", "5,0:DRDRD", "0,5:DDRRUU"]))
	check(board.dirs[0] == Dir.RIGHT and board.head(0) == Vector2i(3, 0), "straight head points right")
	check(board.dirs[1] == Dir.DOWN and board.bends(1) == 1, "L-shape head follows last step")
	check(board.dirs[2] == Dir.DOWN and board.bends(2) == 4, "zigzag bends counted")
	check(board.dirs[3] == Dir.UP and board.bends(3) == 2 and board.length(3) == 7, "U-shape")
	check(ArrowLevel.to_authoring(_level(8, 8, ["0,5:DDRRUU"]))[0] == "0,5:DDRRUU", "authoring roundtrip")

func _test_escape_rules() -> void:
	# Arrow 0 (vertical, head up at top edge) is free. Arrow 1 points right into arrow 2's body.
	var board := ArrowBoard.from_level(_level(6, 6, ["1,3:UUU", "0,4:RR", "4,5:UUUU"]))
	check(board.can_escape(0), "head on the edge leaves")
	check(board.first_obstacle(1) == 2 and board.gap_to_obstacle(1) == 1, "nearest obstacle is the body ahead")
	check(not board.can_escape(1), "blocked by another body")
	check(board.can_escape(2), "vertical arrow free")
	board.remove(2)
	check(board.can_escape(1), "removing the blocker opens the way")
	check(ArrowSolver.peel(ArrowBoard.from_level(_level(6, 6, ["1,3:UUU", "0,4:RR", "4,5:UUUU"])))["solvable"], "peel solves")
	# Head-to-head deadlock is unsolvable.
	var dead := ArrowBoard.from_level(_level(6, 3, ["0,1:RR", "5,1:LL"]))
	check(not dead.can_escape(0) and not dead.can_escape(1), "facing heads block each other")
	check(not ArrowSolver.peel(dead)["solvable"], "facing heads unsolvable")
	# A body far down the ray still blocks.
	var far := ArrowBoard.from_level(_level(8, 3, ["0,1:RR", "6,0:DD"]))
	check(far.first_obstacle(0) == 1 and far.gap_to_obstacle(0) == 3, "far obstacle and gap")

func _test_track() -> void:
	var board := ArrowBoard.from_level(_level(5, 5, ["0,4:UURR"]))
	var track := board.escape_track(0, board.length(0) + 1)
	# Own cells (tail → head) first, then straight on through the ray and past the edge.
	check(track[0] == Vector2i(0, 4) and track[4] == Vector2i(2, 2), "track starts with the body")
	check(track[5] == Vector2i(3, 2) and track[6] == Vector2i(4, 2) and track[7] == Vector2i(5, 2), "track continues ahead of the head")
	check(track.size() == 5 + 2 + 6, "track long enough for the tail to exit")
	for i in range(1, track.size()):
		check(absi(track[i].x - track[i - 1].x) + absi(track[i].y - track[i - 1].y) == 1, "track is connected at %d" % i)

func _test_structure_validation() -> void:
	check(ArrowLevel.check_structure(_level(6, 6, ["0,0:RR", "0,2:DD"])).is_empty(), "valid level")
	var overlap := _level(6, 6, ["0,0:RR", "1,0:DD"])
	check(not ArrowLevel.check_structure(overlap).is_empty(), "overlap rejected")
	# Spiral whose head points back into its own tail is rejected.
	var self_block := _level(6, 6, ["3,1:ULLDR"]) # head (2,1) points right at its own tail (3,1)
	var problems := ArrowLevel.check_structure(self_block)
	check(problems.size() == 1 and problems[0].contains("own body"), "self-blocking head rejected: %s" % str(problems))
	var gap := {"w": 5, "h": 5, "rules": ArrowBoard.RULES, "a": [[0, 0, 2, 0]]}
	check(not ArrowLevel.check_structure(gap).is_empty(), "disconnected path rejected")
	var short := {"w": 5, "h": 5, "rules": ArrowBoard.RULES, "a": [[0, 0]]}
	check(not ArrowLevel.check_structure(short).is_empty(), "single cell arrow rejected")
	var legacy := {"w": 5, "h": 5, "rules": "basic-1", "b": [[0, 0, 1]]}
	check(not ArrowLevel.check_structure(legacy).is_empty(), "legacy tile level rejected by new rules")

func _test_session() -> void:
	var level := _level(6, 6, ["1,3:UUU", "0,4:RR", "4,5:UUUU"])
	var s := ArrowSession.create(level, "campaign", "a1")
	var e := s.tap(1, 1000)
	check(e["type"] == "blocked" and e["life_lost"] and s.lives == 2 and e["blocker"] == 2, "blocked costs one heart")
	e = s.tap(1, 1200)
	check(e["type"] == "blocked" and not e["life_lost"] and s.lives == 2, "same arrow re-tap inside grace is free")
	s.tap(1, 1200 + ArrowSession.SAME_ARROW_GRACE_MS)
	check(s.lives == 1, "same arrow later costs again")
	var fresh := ArrowSession.create(level, "campaign", "a2")
	fresh.tap(1, 0)
	var other := ArrowSession.create(_level(8, 4, ["0,1:RR", "6,0:DDD", "3,3:RR"]), "campaign", "a3")
	other.tap(0, 0)
	other.tap(2, 10)
	check(other.lives == 1, "different blocked arrows tapped quickly are each judged")
	e = s.tap(2, 3000)
	check(e["type"] == "escape" and e["streak"] == 1 and not e["cleared"], "escape")
	check(s.tap(2, 3001)["type"] == "none", "removed arrow ignores repeated taps")
	s.tap(1, 3002)
	e = s.tap(0, 3003)
	check(e["cleared"] and s.status == ArrowSession.Status.CLEARED, "last arrow clears")
	check(s.tap(0, 3004)["type"] == "none", "no events after clear")
	# Failure, single continue.
	var dead := ArrowSession.create(_level(6, 3, ["0,1:RR", "5,1:LL", "0,0:RR"]), "campaign", "a4")
	dead.tap(0, 0)
	dead.tap(1, 1)
	var last := dead.tap(0, 2000)
	check(last["failed"] and dead.lives == 0 and dead.status == ArrowSession.Status.FAILED, "three hearts lost fails")
	check(dead.tap(2, 3000)["type"] == "none", "failed board ignores taps")
	check(dead.continue_with_life() and dead.lives == 1, "continue once")
	dead.tap(0, 9000)
	check(not dead.continue_with_life(), "only one continue")
	# Soft tutorial mistakes.
	var soft_level := _level(6, 3, ["0,1:RR", "5,1:LL"])
	soft_level["soft"] = true
	var soft := ArrowSession.create(soft_level, "campaign", "a5")
	for i in 6:
		soft.tap(i % 2, i * 1000)
	check(soft.lives == ArrowSession.MAX_LIVES and soft.status == ArrowSession.Status.PLAYING, "soft mistakes")
	# Hints point at a free arrow and never play it.
	var hinted := ArrowSession.create(level, "campaign", "a6")
	var h1 := hinted.request_hint()
	check(h1["kind"] == "arrow" and h1["charged"] and hinted.board.can_escape(h1["id"]), "hint is a free arrow")
	check(hinted.board.alive_count == 3, "hint does not play")
	check(hinted.request_hint()["charged"] == false, "repeat hint is free")
	check(h1["id"] == 2, "hint prefers the arrow that frees others")
	# Undo restores exactly (model; offered only where order matters).
	var u := ArrowSession.create(level, "campaign", "a7")
	u.tap(2, 0)
	check(not u.can_undo(), "no undo without a charge")
	u.grant_bonus_undo()
	check(u.undo()["id"] == 2 and u.board.equals(ArrowBoard.from_level(level)), "undo restores the board")

func _test_save_restore() -> void:
	var level := _level(6, 6, ["1,3:UUU", "0,4:RR", "4,5:UUUU"])
	var s := ArrowSession.create(level, "campaign", "r1")
	s.tap(2, 0)
	s.tap(0, 10)
	s.tap(1, 20)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(s.to_save()))
	var back := ArrowSession.from_save(level, saved)
	check(back != null and back.status == ArrowSession.Status.CLEARED, "restored cleared")
	var partial := ArrowSession.create(level, "campaign", "r2")
	partial.tap(1, 0)
	partial.tap(2, 600)
	var restored := ArrowSession.from_save(level, JSON.parse_string(JSON.stringify(partial.to_save())))
	check(restored != null and restored.board.equals(partial.board) and restored.lives == 2, "restored board and hearts")
	var other := level.duplicate(true)
	other["hash"] = "changed"
	check(ArrowSession.from_save(other, saved) == null, "content change discards")
	var legacy_save := {"v": 1, "level_id": "c001", "moves": [0], "hash": level["hash"]}
	check(ArrowSession.from_save(level, legacy_save) == null, "legacy tile save never restored on new rules")

func _test_generator() -> void:
	var params := {"w": 7, "h": 9, "fill": 0.85, "len_min": 3, "len_max": 7, "turn": 0.35}
	var a := ArrowGenerator.build(4242, params)
	var b := ArrowGenerator.build(4242, params)
	check(JSON.stringify(a) == JSON.stringify(b), "generator deterministic")
	a["id"] = "g"
	check(ArrowLevel.check_structure(a).is_empty(), "generated structure valid %s" % str(ArrowLevel.check_structure(a)))
	check(ArrowSolver.replay(ArrowBoard.from_level(a), PackedInt32Array(a["sol"])), "generated solution replays")
	check(ArrowSolver.peel(ArrowBoard.from_level(a))["solvable"], "generated board peels")


func _test_shaped_generator() -> void:
	var mask := Silhouettes.mask("apple", 18, 24)
	var params := {"w": 18, "h": 24, "mask": mask, "lengths": [[8, 14, 0.55], [4, 7, 0.35], [2, 3, 0.1]]}
	var a := ArrowGenerator.build_shaped(77, params)
	var b := ArrowGenerator.build_shaped(77, params)
	check(JSON.stringify(a) == JSON.stringify(b), "shaped generator deterministic")
	a["id"] = "s"
	check(ArrowLevel.check_structure(a).is_empty(), "shaped structure valid %s" % str(ArrowLevel.check_structure(a)))
	var inside := true
	for flat in a["a"]:
		for i in range(0, flat.size(), 2):
			if mask[int(flat[i + 1]) * 18 + int(flat[i])] != 1:
				inside = false
	check(inside, "shaped arrows stay inside the silhouette")
	var before := ArrowBoard.from_level(a).escapable_ids().size()
	var tight := ArrowGenerator.tighten(a, 9, 5, 2, 18, mask)
	tight["id"] = "t"
	var board := ArrowBoard.from_level(tight)
	check(ArrowLevel.check_structure(tight).is_empty(), "tightened structure valid")
	check(board.escapable_ids().size() <= before and board.escapable_ids().size() >= 2, "tighten never adds free arrows (%d -> %d)" % [before, board.escapable_ids().size()])
	check(ArrowSolver.replay(board, PackedInt32Array(tight["sol"])), "tightened solution replays")
	var cells_a := 0
	var cells_t := 0
	for flat in a["a"]:
		cells_a += flat.size()
	for flat in tight["a"]:
		cells_t += flat.size()
	check(cells_a == cells_t, "tighten keeps every picture cell covered")

func _test_fast_solver() -> void:
	# The linear solver must agree with exact peeling on solvable and deadlocked boards.
	var deadlock := ArrowBoard.from_level(_level(4, 4, ["0,1:R", "3,1:L"]))
	check(not ArrowSolver.is_solvable(deadlock) and not ArrowSolver.peel(deadlock)["solvable"], "facing pair is a deadlock for both solvers")
	check(ArrowSolver.stuck_ids(deadlock).size() == 2, "both arrows of the deadlock reported stuck")
	var rng := Prng.new(5)
	var agree := true
	for k in 60:
		var level := ArrowGenerator.build_shaped(1000 + k, {"w": 10, "h": 12, "shape": "pebble"})
		var board := ArrowBoard.from_level(level)
		for flip in 1 + k % 4:
			var id := rng.below(board.size())
			var turned := board.cells_of(id)
			turned.reverse()
			if not ArrowGenerator._self_blocked(turned, board.width, board.height):
				ArrowGenerator._reorient(board, id, turned)
		if ArrowSolver.is_solvable(board) != bool(ArrowSolver.peel(board)["solvable"]):
			agree = false
	check(agree, "fast solver agrees with peeling on 60 perturbed boards")

func _test_escape_events() -> void:
	# The centre column blocks both side arrows; removing it opens two at once.
	var level := _level(5, 5, ["2,4:UUUU", "0,2:R", "4,1:L"])
	level["gold"] = [1]
	var session := ArrowSession.create(level, "campaign", "t", 0)
	check(session.gold_total() == 1 and session.is_golden(1), "golden arrow known to the session")
	var event := session.tap(0, 0)
	check(event["type"] == "escape" and int(event["opened"]) == 2, "removing the centre opens two arrows")
	event = session.tap(1, 10)
	check(bool(event["golden"]) and session.gold_collected() == 1, "golden arrow collected when it leaves")
	var blocked := ArrowSession.create(_level(5, 5, ["2,4:UUUU", "0,2:R"]), "campaign", "u", 0)
	blocked.tap(1, 0)
	check(blocked.blocked_taps == 1 and blocked.mistakes == 1, "blocked taps counted for analytics")

func _test_league_rules() -> void:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var wed := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 7, "hour": 12, "minute": 0, "second": 0}) - bias
	var sun := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 11, "hour": 23, "minute": 30, "second": 0}) - bias
	var mon := Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 12, "hour": 0, "minute": 30, "second": 0}) - bias
	check(LeagueRules.week_key(wed) == "2026-10-05" and LeagueRules.week_key(sun) == "2026-10-05", "week runs Monday to Sunday (local)")
	check(LeagueRules.week_key(mon) == "2026-10-12", "a new week starts on Monday")
	check(LeagueRules.weeks_between("2026-10-05", "2026-10-19") == 2, "weeks between keys")
	check(LeagueRules.seconds_left(sun) == 30 * 60, "countdown to the week's end")
	check(LeagueRules.settle(2, 7) == 1 and LeagueRules.settle(2, 8) == 2 and LeagueRules.settle(0, 0) == 0, "keep line settles the tier")
	var level := {"id": "x", "gold": [1, 2], "hard": true}
	var first := LeagueRules.clear_points(level, true, true, {})
	check(int(first["total"]) == 6, "first perfect HARD clear with two golden arrows pays 6")
	var again := LeagueRules.clear_points(level, false, false, first["claim"])
	check(int(again["total"]) == 0, "the same stage pays once per week")
	var later := LeagueRules.clear_points(level, true, false, again["claim"])
	check(int(later["total"]) == 0, "perfect already paid this week")
	var plain := LeagueRules.clear_points({"id": "y", "gold": [3]}, false, false, {})
	var perfect := LeagueRules.clear_points({"id": "y", "gold": [3]}, true, false, plain["claim"])
	check(int(plain["total"]) == 1 and int(perfect["total"]) == 1, "a later perfect clear adds only the perfect point")
	var step := LeagueRules.promote(0, 0, 30)
	check(int(step["tier"]) == 2 and int(step["base"]) == 26 and step["promotions"] == [1, 2], "promotion lines stack within a week")
	check(int(LeagueRules.promote(4, 0, 999)["tier"]) == 4, "diamond is the top")

func _test_silhouettes() -> void:
	var all_ok := true
	for name in Silhouettes.SHAPES:
		var m := Silhouettes.mask(name, 16, 20)
		if Silhouettes.cell_count(m) < 40:
			all_ok = false
			printerr("small silhouette ", name)
	check(all_ok, "every silhouette keeps at least 40 cells at 16x20")

## Checkpoint (graded boards) and the forgiven first blocked tap ("grace").
func _test_checkpoint_and_warning() -> void:
	# Four rows of four chained arrows pointing right: each row empties from its right end.
	var tokens := []
	for y in 4:
		for x in [0, 2, 4, 6]:
			tokens.append("%d,%d:R" % [x, y])
	var level := _level(8, 4, tokens)
	level["grade"] = 1
	level["grace"] = 1
	level["sol"] = ArrowSolver.peel(ArrowBoard.from_level(level))["order"]
	var session := ArrowSession.create(level, "campaign", "cp-1")
	check(session.uses_checkpoint and session.grace_left == 1, "graded board: checkpoint on, one warning")
	var blocked := -1
	for id in session.board.live_ids():
		if not session.board.can_escape(id):
			blocked = id
			break
	var warned := session.tap(blocked, 1000)
	check(warned["type"] == "blocked" and bool(warned.get("warned", false)) and not warned["life_lost"] and session.lives == 3,
		"first blocked tap warns without costing a heart")
	var charged := session.tap(blocked, 5000)
	check(charged["life_lost"] and session.lives == 2 and session.grace_left == 0, "the next blocked tap costs a heart")
	check(session.wrong.has(blocked) and session.wrong.size() == 1, "a blocked tap marks that arrow as a wrong pick")
	var half := ceili(session.board.size() * ArrowSession.CHECKPOINT_SHARE)
	var reached := false
	while session.history.size() < half:
		var free := session.board.escapable_ids()
		var event := session.tap(free[0], 6000)
		reached = bool(event.get("checkpoint", false))
	check(reached and session.has_checkpoint() and session.checkpoint.size() == half, "checkpoint taken when half the arrows are out")
	var at_checkpoint := session.board.duplicate_board()
	var free_more := session.board.escapable_ids()
	if not free_more.is_empty():
		session.tap(free_more[0], 7000)
	check(session.checkpoint.size() == half, "later moves never move the checkpoint")
	check(not session.restore_checkpoint(), "no checkpoint restore while playing")
	var t := 10000
	while session.status == ArrowSession.Status.PLAYING:
		var stuck := -1
		for id in session.board.live_ids():
			if not session.board.can_escape(id):
				stuck = id
				break
		if stuck == -1:
			break
		t += 1000
		session.tap(stuck, t)
	check(session.status == ArrowSession.Status.FAILED and session.can_restore_checkpoint(), "a fail offers the free checkpoint")
	var mistakes := session.mistakes
	# Save mid-fail and load: the checkpoint survives and still restores exactly.
	var loaded := ArrowSession.from_save(level, session.to_save())
	check(loaded != null and loaded.has_checkpoint() and loaded.can_restore_checkpoint(), "checkpoint survives save and load")
	check(loaded.wrong.keys() == session.wrong.keys(), "wrong picks survive save and load")
	check(loaded.restore_checkpoint() and loaded.board.equals(at_checkpoint) and loaded.lives == 3
		and loaded.status == ArrowSession.Status.PLAYING and loaded.history.size() == half and loaded.mistakes == mistakes,
		"restore rebuilds the exact checkpoint board with full hearts, mistakes kept")
	check(not loaded.can_restore_checkpoint(), "the free checkpoint is used once per attempt")
	# A tampered checkpoint (wrong board) is dropped instead of restoring a different board.
	var data := session.to_save()
	data["checkpoint_alive"] = "1".repeat(session.board.size())
	var tampered := ArrowSession.from_save(level, data)
	check(tampered != null and not tampered.has_checkpoint(), "a checkpoint that does not rebuild its board is dropped")
	# Ungraded boards keep the old rules.
	var plain := level.duplicate(true)
	plain["grade"] = 0
	plain.erase("grace")
	var easy := ArrowSession.create(plain, "campaign", "cp-2")
	check(not easy.uses_checkpoint and easy.grace_left == 0, "ungraded board: no checkpoint, no warning")

## Stage 5 is the fixed, validated first HARD board (2026-10-10 redesign).
func _test_first_hard_board() -> void:
	var pack: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/v2/campaign.json"))
	var level: Dictionary = {}
	for raw in pack["levels"]:
		if str(raw["id"]) == "a005":
			level = raw
	check(not level.is_empty() and int(level["w"]) == 20 and int(level["h"]) == 25 and (level["a"] as Array).size() == 55,
		"stage 5 is the 55-arrow 20x25 board")
	check(str(level.get("hash", "")) == "83d2bbd0a96bb219" and int(level.get("grace", 0)) == 1 and bool(level.get("hard", false)),
		"stage 5 content is pinned (hash) and forgives one blocked tap")
	var m: Dictionary = level.get("m", {})
	check(int(m.get("initial_free", 99)) <= 4 and int(m.get("keys", 0)) >= 10, "stage 5: few ways in, many key moves")
