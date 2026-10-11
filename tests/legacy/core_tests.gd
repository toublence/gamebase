extends SceneTree
## Pure rule tests. Run: godot --headless --path . -s res://tests/legacy/core_tests.gd
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _init() -> void:
	_test_directions()
	_test_resolver()
	_test_session_lives()
	_test_switch()
	_test_save_restore()
	_test_prng()
	_test_ascii()
	print("CORE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _level(text: String, rules: String = LevelData.RULES_BASIC) -> Dictionary:
	var level := LevelData.parse_ascii(text)
	level["rules"] = rules
	level["id"] = "t"
	level["hash"] = LevelData.content_hash(level)
	return level

func _test_directions() -> void:
	check(Dir.cw(Dir.LEFT) == Dir.UP and Dir.ccw(Dir.UP) == Dir.LEFT, "clockwise wraps")
	for d in 4:
		check(Dir.ccw(Dir.cw(d)) == d, "cw/ccw inverse %d" % d)

func _test_resolver() -> void:
	# Four directions toward the edge with an empty board.
	for pair in [["^", Dir.UP], [">", Dir.RIGHT], ["v", Dir.DOWN], ["<", Dir.LEFT]]:
		var board := BoardState.from_level(_level(". . .\n. %s .\n. . ." % pair[0]))
		check(board.dirs[0] == pair[1], "parse dir " + pair[0])
		check(MoveResolver.can_escape(board, 0), "open escape " + pair[0])
		check(MoveResolver.exit_distance(board, 0) == 2, "exit distance " + pair[0])
	# Edge blocks escape immediately.
	var edge := BoardState.from_level(_level("< . >"))
	check(MoveResolver.can_escape(edge, 0) and MoveResolver.can_escape(edge, 1), "edge escapes")
	# Nearest obstacle, not the farthest.
	var row := BoardState.from_level(_level("> . ^ . v"))
	check(MoveResolver.first_obstacle(row, 0) == 1, "nearest obstacle chosen")
	check(MoveResolver.gap_to(row, 0, 1) == 1, "gap counts empty cells")
	# Facing pair is a deadlock under basic rules.
	var facing := BoardState.from_level(_level("> <"))
	check(not MoveResolver.can_escape(facing, 0) and not MoveResolver.can_escape(facing, 1), "facing pair blocked")
	check(not LevelValidator.peel(facing)["solvable"], "facing pair unsolvable")
	# Removal frees the path behind.
	var chain := BoardState.from_level(_level("> > >"))
	check(MoveResolver.escapable_ids(chain) == PackedInt32Array([2]), "only the front block is free")
	var peel := LevelValidator.peel(chain)
	check(peel["solvable"] and peel["layers"].size() == 3, "chain peels in three layers")
	check(LevelValidator.replay(BoardState.from_level(_level("> > >")), peel["order"]), "peel order replays")
	# Vertical obstacle in a column.
	var column := BoardState.from_level(_level("v\n.\n^"))
	check(MoveResolver.first_obstacle(column, 0) == 1 and MoveResolver.first_obstacle(column, 1) == 0, "column facing")

func _test_session_lives() -> void:
	var session := PuzzleSession.create(_level("> > .\n. . ."), "campaign", "a1")
	var e := session.tap(0, 1000)
	check(e["type"] == "blocked" and e["life_lost"] and session.lives == 2, "blocked costs one life")
	e = session.tap(0, 1100)
	check(e["type"] == "blocked" and not e["life_lost"] and session.lives == 2, "double tap inside grace is free")
	e = session.tap(0, 1100 + PuzzleSession.MISTAKE_GRACE_MS)
	check(e["life_lost"] and session.lives == 1, "later mistake costs again")
	e = session.tap(1, 2000)
	check(e["type"] == "escape" and not e["cleared"], "front escapes")
	e = session.tap(1, 2001)
	check(e["type"] == "none", "removed block ignores repeated taps")
	e = session.tap(0, 2002)
	check(e["type"] == "escape" and e["cleared"] and session.status == PuzzleSession.Status.CLEARED, "clear exactly once")
	e = session.tap(0, 2003)
	check(e["type"] == "none", "no events after clear")
	# Failure and free restart path.
	var fail := PuzzleSession.create(_level("> <"), "campaign", "a2")
	fail.tap(0, 0)
	fail.tap(1, 1000)
	var last := fail.tap(0, 2000)
	check(last["failed"] and fail.status == PuzzleSession.Status.FAILED and fail.lives == 0, "three mistakes fail")
	check(fail.tap(1, 5000)["type"] == "none", "failed board ignores taps")
	check(fail.continue_with_life() and fail.lives == 1 and fail.status == PuzzleSession.Status.PLAYING, "continue once")
	fail.tap(0, 9000)
	check(not fail.continue_with_life(), "only one continue per attempt")
	# Soft tutorial mistakes.
	var soft_level := _level("> >")
	soft_level["soft"] = true
	var soft := PuzzleSession.create(soft_level, "campaign", "a3")
	for i in 5:
		soft.tap(0, i * 1000)
	check(soft.lives == PuzzleSession.MAX_LIVES and soft.status == PuzzleSession.Status.PLAYING, "tutorial mistakes are soft")
	# Basic mode never offers undo.
	check(not session.has_undo_feature(), "basic mode hides undo")
	# Hints never move blocks; re-asking an unused hint is free.
	var hinted := PuzzleSession.create(_level("> > .\n^ . ."), "campaign", "a4")
	var alive_before := hinted.board.alive_count
	var h1 := hinted.request_hint()
	check(h1["kind"] == "block" and h1["charged"] and hinted.hints_left() == 0, "first hint uses the free charge")
	check(hinted.board.alive_count == alive_before, "hint does not play")
	var h2 := hinted.request_hint()
	check(h2["kind"] == "block" and not h2["charged"] and h2["id"] == h1["id"], "repeat hint is free")
	check(MoveResolver.can_escape(hinted.board, h1["id"]), "hint points at a free block")

func _test_switch() -> void:
	# Switch A turns the down arrow (index 1) into a left arrow once it leaves.
	var level := _level("^A va", LevelData.RULES_SWITCH)
	var board := BoardState.from_level(level)
	check(board.kinds[0] == BoardState.KIND_SWITCH and board.links[0] == PackedInt32Array([1]), "switch parsed")
	var preview := MoveResolver.preview_rotation(board, 0)
	check(preview.get(1) == Dir.LEFT, "preview shows clockwise turn")
	var rotated := MoveResolver.apply_escape(board, 0)
	check(rotated == PackedInt32Array([1]) and board.dirs[1] == Dir.LEFT, "rotation matches preview")
	MoveResolver.revert_escape(board, 0, rotated)
	check(board.dirs[1] == Dir.DOWN and board.is_alive(0), "revert restores direction and block")
	# Removed targets are not rotated.
	var gone := BoardState.from_level(_level("^A ^a", LevelData.RULES_SWITCH))
	MoveResolver.apply_escape(gone, 1)
	check(MoveResolver.apply_escape(gone, 0).is_empty(), "removed target skipped")
	# Order matters: firing the switch first points block 1 into block 2 forever.
	var trap := _level(". . .\n^A >a v\n. . .", LevelData.RULES_SWITCH)
	var analysis := SwitchSolver.analyze(BoardState.from_level(trap))
	check(analysis["status"] == "solvable", "switch puzzle solvable")
	check(LevelValidator.replay(BoardState.from_level(trap), analysis["solution"]), "solver line replays")
	var session := PuzzleSession.create(trap, "switch", "s1")
	check(session.free_undos == PuzzleSession.FREE_UNDOS_SWITCH and session.can_undo() == false, "undo charges start")
	var e := session.tap(0, 0)
	check(e["type"] == "escape" and e["rotated"] == PackedInt32Array([1]), "switch escape rotates")
	check(session.board.dirs[1] == Dir.DOWN, "right arrow turned down")
	var u := session.undo()
	check(u["type"] == "undo" and session.board.dirs[1] == Dir.RIGHT and session.board.is_alive(0), "undo restores rotation")
	check(session.free_undos == PuzzleSession.FREE_UNDOS_SWITCH - 1, "undo used a charge")
	# Unsolvable-but-not-stuck state: hint points to undo without charging.
	var dead := _level("^ . .\n> . <", LevelData.RULES_SWITCH)
	var dead_analysis := SwitchSolver.analyze(BoardState.from_level(dead))
	check(dead_analysis["status"] == "unsolvable", "dead switch board detected")
	var dead_session := PuzzleSession.create(dead, "switch", "s2")
	check(not dead_session.is_stuck() and dead_session.suggest()["kind"] == "undo", "dead but movable state suggests undo")
	var hint := dead_session.request_hint()
	check(hint["kind"] == "undo" and dead_session.hints_left() == 1, "undo suggestion is not charged")
	var budget := SwitchSolver.analyze(BoardState.from_level(trap), 1)
	check(budget["status"] == "unknown", "solver budget reports unknown, never solvable")

func _test_save_restore() -> void:
	var level := _level(". > . v\n> . ^ .\n. ^ < .", LevelData.RULES_BASIC)
	var session := PuzzleSession.create(level, "campaign", "r1")
	var order: PackedInt32Array = LevelValidator.peel(session.board)["order"]
	for i in 3:
		session.tap(order[i], i * 10)
	session.tap(order[order.size() - 1], 999) # might be blocked: costs a life
	var saved := session.to_save()
	var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var restored := PuzzleSession.from_save(level, json)
	check(restored != null, "restore succeeds")
	if restored != null:
		check(restored.board.equals(session.board), "restored board identical")
		check(restored.lives == session.lives and restored.mistakes == session.mistakes, "restored lives")
	var changed := level.duplicate(true)
	changed["hash"] = "different"
	check(PuzzleSession.from_save(changed, json) == null, "content change discards attempt")
	# Switch restore keeps rotations.
	var sw := _level(". . .\n^A >a v\n. . .", LevelData.RULES_SWITCH)
	var ss := PuzzleSession.create(sw, "switch", "r2")
	ss.tap(0, 0)
	var back := PuzzleSession.from_save(sw, JSON.parse_string(JSON.stringify(ss.to_save())))
	check(back != null and back.board.equals(ss.board) and back.board.dirs[1] == Dir.DOWN, "switch restore keeps rotation")
	check(back.can_undo() and back.undo()["type"] == "undo" and back.board.dirs[1] == Dir.RIGHT, "restored undo stack works")

func _test_prng() -> void:
	var a := Prng.new(12345)
	var b := Prng.new(12345)
	var same := true
	for i in 1000:
		if a.next_u32() != b.next_u32():
			same = false
	check(same, "same seed same stream")
	# Must match tools/validate_levels.py (independent Python Mulberry32) value for value.
	var cross := Prng.new(12345)
	var expected := [4207900869, 1317490944, 2079646450, 3513001552]
	var got := []
	for i in 4:
		got.append(cross.next_u32())
	check(got == expected, "PRNG matches Python mirror %s" % str(got))
	var g1 := LevelGenerator.build_basic(77, {"w": 6, "h": 7, "n": 26, "shape": "heart"})
	var g2 := LevelGenerator.build_basic(77, {"w": 6, "h": 7, "n": 26, "shape": "heart"})
	check(JSON.stringify(g1) == JSON.stringify(g2), "generator deterministic")
	var board := BoardState.from_level(g1)
	check(LevelValidator.replay(board, PackedInt32Array(g1["sol"])), "generated solution replays")
	check(LevelValidator.peel(board)["solvable"], "generated board peels")

func _test_ascii() -> void:
	var text := ". > .\nv . <"
	check(LevelData.to_ascii(LevelData.parse_ascii(text)) == text, "ascii roundtrip")
	var level := _level(text)
	check(level["hash"] == LevelData.content_hash(level.duplicate(true)), "hash stable")
	check(LevelValidator.check_structure(level).is_empty(), "structure valid")
	var bad := {"w": 3, "h": 2, "b": [[0, 0, 1], [0, 0, 2], [5, 0, 1], [1, 1, 9]]}
	check(LevelValidator.check_structure(bad).size() == 3, "structure errors found")
