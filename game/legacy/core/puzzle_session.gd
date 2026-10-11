class_name PuzzleSession
extends RefCounted
## One attempt at one level. Pure state: every input returns an event dictionary for the view.
## Logic resolves immediately on tap; animations only express the result.
enum Status { PLAYING, CLEARED, FAILED }

const MAX_LIVES := 3
## A second blocked tap inside this window (double tap, palm, fast retry) shows the bump again but
## never costs another life.
const MISTAKE_GRACE_MS := 450
const FREE_HINTS := 1
const FREE_UNDOS_SWITCH := 3
const SAVE_VERSION := 1

var level: Dictionary
var mode := "campaign"
var board: BoardState
var lives := MAX_LIVES
var mistakes := 0
var history: Array = [] # [{id, rotated}]
var status := Status.PLAYING
var attempt_id := ""
var retry_count := 0
var active_ms := 0
var combo := 0
var best_combo := 0
var free_hints := FREE_HINTS
var bonus_hints := 0
var hints_used := 0
var free_undos := 0
var bonus_undos := 0
var undos_used := 0
var continues_used := 0
var soft_mistakes := false
var hint_target := -1
var daily_date := ""
var applied_rewards: Array = []
var _last_life_loss_ms := -1000000

static func create(level_data: Dictionary, play_mode: String, attempt: String, retries: int = 0) -> PuzzleSession:
	var session := PuzzleSession.new()
	session.level = level_data
	session.mode = play_mode
	session.board = BoardState.from_level(level_data)
	session.attempt_id = attempt
	session.retry_count = retries
	session.free_undos = FREE_UNDOS_SWITCH if session.is_switch() else 0
	session.soft_mistakes = bool(level_data.get("soft", false))
	return session

func is_switch() -> bool:
	return str(level.get("rules", LevelData.RULES_BASIC)) == LevelData.RULES_SWITCH

func level_id() -> String:
	return str(level.get("id", ""))

func tap(id: int, now_ms: int) -> Dictionary:
	if status != Status.PLAYING or not board.is_alive(id):
		return {"type": "none"}
	var blocker := MoveResolver.first_obstacle(board, id)
	if blocker == BoardState.EMPTY:
		var distance := MoveResolver.exit_distance(board, id)
		var rotated := MoveResolver.apply_escape(board, id)
		history.append({"id": id, "rotated": rotated})
		combo += 1
		best_combo = maxi(best_combo, combo)
		if hint_target == id or not board.is_alive(hint_target):
			hint_target = -1
		var cleared := board.is_cleared()
		if cleared:
			status = Status.CLEARED
		return {"type": "escape", "id": id, "rotated": rotated, "cleared": cleared, "combo": combo, "distance": distance}
	combo = 0
	var life_lost := false
	if not soft_mistakes and now_ms - _last_life_loss_ms >= MISTAKE_GRACE_MS:
		lives -= 1
		mistakes += 1
		life_lost = true
		_last_life_loss_ms = now_ms
		if lives <= 0:
			lives = 0
			status = Status.FAILED
	return {"type": "blocked", "id": id, "blocker": blocker, "gap": MoveResolver.gap_to(board, id, blocker),
		"life_lost": life_lost, "lives": lives, "failed": status == Status.FAILED}

func is_stuck() -> bool:
	return status == Status.PLAYING and not board.is_cleared() and MoveResolver.escapable_ids(board).is_empty()

## Undo exists only for the switch ruleset; basic escapes never make a board harder.
func has_undo_feature() -> bool:
	return is_switch()

func can_undo() -> bool:
	return has_undo_feature() and status == Status.PLAYING and not history.is_empty()

## Undo is free while charges remain, and always free when the board is stuck.
func undo_is_free() -> bool:
	return free_undos > 0 or bonus_undos > 0 or is_stuck()

func undo() -> Dictionary:
	if not can_undo() or not undo_is_free():
		return {"type": "none"}
	var stuck := is_stuck()
	var last: Dictionary = history.pop_back()
	MoveResolver.revert_escape(board, last["id"], last["rotated"])
	if not stuck:
		if free_undos > 0:
			free_undos -= 1
		else:
			bonus_undos -= 1
	undos_used += 1
	combo = 0
	hint_target = -1
	return {"type": "undo", "id": last["id"], "rotated": last["rotated"], "was_stuck": stuck}

func hints_left() -> int:
	return free_hints + bonus_hints

## Returns {kind: "block"|"undo"|"none", id, charged}. Re-asking for an unused hint is free.
func request_hint() -> Dictionary:
	if status != Status.PLAYING:
		return {"kind": "none"}
	if hint_target != -1 and MoveResolver.can_escape(board, hint_target):
		return {"kind": "block", "id": hint_target, "charged": false}
	var suggestion := suggest()
	if suggestion["kind"] != "block":
		return suggestion # pointing at undo or a cleared board costs nothing
	if hints_left() <= 0:
		return {"kind": "none", "reason": "no_hints"}
	if free_hints > 0:
		free_hints -= 1
	else:
		bonus_hints -= 1
	hints_used += 1
	hint_target = suggestion["id"]
	return {"kind": "block", "id": hint_target, "charged": true}

## Read-only suggestion: the block that frees the most others, or the next move on a winning switch
## line. Never performs the move.
func suggest() -> Dictionary:
	if is_switch():
		if is_stuck():
			return {"kind": "undo", "charged": false}
		var move := SwitchSolver.next_move(board)
		if move >= 0:
			return {"kind": "block", "id": move}
		if move == -1:
			return {"kind": "undo", "charged": false}
	var free := MoveResolver.escapable_ids(board)
	if free.is_empty():
		return {"kind": "none"}
	var best := free[0]
	var best_score := -1
	for id in free:
		var score := 0
		for other in board.live_ids():
			if other != id and MoveResolver.first_obstacle(board, other) == id:
				score += 1
		if score > best_score:
			best_score = score
			best = id
	return {"kind": "block", "id": best}

func can_continue() -> bool:
	return status == Status.FAILED and continues_used == 0

func continue_with_life() -> bool:
	if not can_continue():
		return false
	continues_used += 1
	lives = 1
	status = Status.PLAYING
	_last_life_loss_ms = -1000000
	return true

func grant_bonus_hint() -> void:
	bonus_hints += 1

func grant_bonus_undo() -> void:
	bonus_undos += 1

func is_perfect() -> bool:
	return status == Status.CLEARED and mistakes == 0 and continues_used == 0

func moves_ids() -> Array:
	var ids: Array = []
	for entry in history:
		ids.append(entry["id"])
	return ids

func to_save() -> Dictionary:
	return {"v": SAVE_VERSION, "level_id": level_id(), "hash": str(level.get("hash", "")),
		"rules": str(level.get("rules", LevelData.RULES_BASIC)), "mode": mode, "moves": moves_ids(),
		"lives": lives, "mistakes": mistakes, "status": int(status), "attempt_id": attempt_id,
		"retry_count": retry_count, "active_ms": active_ms, "combo": combo, "best_combo": best_combo,
		"free_hints": free_hints, "bonus_hints": bonus_hints, "hints_used": hints_used,
		"free_undos": free_undos, "bonus_undos": bonus_undos, "undos_used": undos_used,
		"continues_used": continues_used, "hint_target": hint_target, "daily_date": daily_date,
		"applied_rewards": applied_rewards.duplicate()}

## Rebuilds an attempt by replaying its moves with the real rules. Returns null when the saved
## attempt belongs to different content or any move is no longer legal.
static func from_save(level_data: Dictionary, data: Dictionary) -> PuzzleSession:
	if int(data.get("v", 0)) != SAVE_VERSION or str(data.get("hash", "")) != str(level_data.get("hash", "")):
		return null
	if str(data.get("rules", "")) != str(level_data.get("rules", LevelData.RULES_BASIC)):
		return null
	var session := create(level_data, str(data.get("mode", "campaign")), str(data.get("attempt_id", "")),
		int(data.get("retry_count", 0)))
	var moves: Variant = data.get("moves", [])
	if not moves is Array:
		return null
	for raw in moves:
		var id := int(raw)
		if not MoveResolver.can_escape(session.board, id):
			return null
		session.history.append({"id": id, "rotated": MoveResolver.apply_escape(session.board, id)})
	session.lives = clampi(int(data.get("lives", MAX_LIVES)), 0, MAX_LIVES)
	session.mistakes = maxi(0, int(data.get("mistakes", 0)))
	session.active_ms = maxi(0, int(data.get("active_ms", 0)))
	session.combo = maxi(0, int(data.get("combo", 0)))
	session.best_combo = maxi(session.combo, int(data.get("best_combo", 0)))
	session.free_hints = clampi(int(data.get("free_hints", FREE_HINTS)), 0, FREE_HINTS)
	session.bonus_hints = maxi(0, int(data.get("bonus_hints", 0)))
	session.hints_used = maxi(0, int(data.get("hints_used", 0)))
	session.free_undos = clampi(int(data.get("free_undos", session.free_undos)), 0, FREE_UNDOS_SWITCH)
	session.bonus_undos = maxi(0, int(data.get("bonus_undos", 0)))
	session.undos_used = maxi(0, int(data.get("undos_used", 0)))
	session.continues_used = maxi(0, int(data.get("continues_used", 0)))
	session.daily_date = str(data.get("daily_date", ""))
	var applied: Variant = data.get("applied_rewards", [])
	session.applied_rewards = applied.duplicate() if applied is Array else []
	var target := int(data.get("hint_target", -1))
	session.hint_target = target if MoveResolver.can_escape(session.board, target) else -1
	var saved_status := int(data.get("status", 0))
	if session.board.is_cleared():
		session.status = Status.CLEARED
	elif saved_status == Status.FAILED or session.lives == 0:
		session.status = Status.FAILED
		session.lives = 0
	return session
