class_name ArrowSession
extends RefCounted
## One attempt at one "arrow-path-2" level. Pure state; every input returns an event for the view.
## Logic resolves at the moment of the tap. Animations only show the result.
##
## Retry relief on graded (HARD family) boards:
## - Checkpoint: the first time half of the arrows are out, the exact move list is kept (with the
##   resulting board as a bit string, checked again on restore). After a fail the attempt can go
##   back there once for free with full hearts (restore_checkpoint). Rewards are only paid on the
##   clear and golden arrows count from the moves, so nothing can be paid twice.
## - Warning: a level may forgive its first blocked taps (`"grace"` in the level data, the first
##   HARD board uses 1): the obstacle is shown and explained, and no heart is lost.
enum Status { PLAYING, CLEARED, FAILED }

const MAX_LIVES := 3
## Re-tapping the same blocked arrow while its bump plays never costs a second heart. Taps on other
## arrows are judged normally.
const SAME_ARROW_GRACE_MS := 500
const FREE_HINTS := 1
const SAVE_VERSION := 2
## Share of the arrows out of the board at which the checkpoint is taken.
const CHECKPOINT_SHARE := 0.5
const FREE_CHECKPOINT_RESTORES := 1

var level: Dictionary
var mode := "campaign"
var board: ArrowBoard
var lives := MAX_LIVES
var mistakes := 0
var history := PackedInt32Array()
var status := Status.PLAYING
var attempt_id := ""
var retry_count := 0
var active_ms := 0
var streak := 0
var best_streak := 0
var free_hints := FREE_HINTS
var bonus_hints := 0
var hints_used := 0
var bonus_undos := 0
var undos_used := 0
var continues_used := 0
var soft_mistakes := false
var hint_target := -1
var daily_date := ""
var applied_rewards: Array = []
## Every blocked tap, charged or not (analytics aggregate; mistakes counts only charged ones).
var blocked_taps := 0
## Arrows tapped while blocked in this attempt (shown red until the board ends).
var wrong := {} # arrow id -> true
var uses_checkpoint := false
## Moves (in order) up to the checkpoint; empty until it is reached.
var checkpoint := PackedInt32Array()
## The board at the checkpoint, one char per arrow ("1" = still on the board).
var checkpoint_alive := ""
var checkpoints_used := 0
## Blocked taps this attempt still forgives with a warning (no heart lost).
var grace_left := 0
var _last_blocked := {} # arrow id -> ms of its last charged mistake
var _gold := {}

static func create(level_data: Dictionary, play_mode: String, attempt: String, retries: int = 0) -> ArrowSession:
	var session := ArrowSession.new()
	session.level = level_data
	session.mode = play_mode
	session.board = ArrowBoard.from_level(level_data)
	session.attempt_id = attempt
	session.retry_count = retries
	session.soft_mistakes = bool(level_data.get("soft", false))
	session.uses_checkpoint = not session.soft_mistakes and int(level_data.get("grade", 0)) > 0
	session.grace_left = 0 if session.soft_mistakes else maxi(0, int(level_data.get("grace", 0)))
	for id in level_data.get("gold", []):
		session._gold[int(id)] = true
	return session

func is_golden(id: int) -> bool:
	return _gold.has(id)

func gold_total() -> int:
	return _gold.size()

## Golden arrows already out of the board in this attempt.
func gold_collected() -> int:
	var count := 0
	for id in history:
		if _gold.has(id):
			count += 1
	return count

func level_id() -> String:
	return str(level.get("id", ""))

func tap(id: int, now_ms: int) -> Dictionary:
	if status != Status.PLAYING or not board.is_alive(id):
		return {"type": "none"}
	var blocker := board.first_obstacle(id)
	if blocker == ArrowBoard.EMPTY:
		var track := board.escape_track(id, board.length(id) + 1)
		# Arrows this one was the first obstacle for; after it leaves, count those now free.
		var waiting := PackedInt32Array()
		for other in board.live_ids():
			if other != id and board.first_obstacle(other) == id:
				waiting.append(other)
		board.remove(id)
		var opened := 0
		for other in waiting:
			if board.can_escape(other):
				opened += 1
		history.append(id)
		streak += 1
		best_streak = maxi(best_streak, streak)
		if hint_target == id:
			hint_target = -1
		if board.is_cleared():
			status = Status.CLEARED
		var reached_checkpoint := false
		if uses_checkpoint and checkpoint.is_empty() and status == Status.PLAYING \
				and history.size() >= ceili(board.size() * CHECKPOINT_SHARE):
			checkpoint = history.duplicate()
			checkpoint_alive = alive_key()
			reached_checkpoint = true
		return {"type": "escape", "id": id, "track": track, "length": board.length(id), "streak": streak,
			"cleared": status == Status.CLEARED, "remaining": board.alive_count, "opened": opened, "golden": _gold.has(id),
			"checkpoint": reached_checkpoint}
	streak = 0
	blocked_taps += 1
	wrong[id] = true
	var gap := board.gap_to_obstacle(id)
	var charged := false
	if not soft_mistakes and grace_left > 0:
		grace_left -= 1
		_last_blocked[id] = now_ms
		return {"type": "blocked", "id": id, "blocker": blocker, "gap": gap, "life_lost": false, "lives": lives,
			"failed": false, "warned": true}
	if not soft_mistakes and now_ms - int(_last_blocked.get(id, -1000000)) >= SAME_ARROW_GRACE_MS:
		charged = true
		_last_blocked[id] = now_ms
		lives -= 1
		mistakes += 1
		if lives <= 0:
			lives = 0
			status = Status.FAILED
	return {"type": "blocked", "id": id, "blocker": blocker, "gap": gap, "life_lost": charged, "lives": lives,
		"failed": status == Status.FAILED}

## Undo exists in the model (and for future order-dependent modes). The basic ruleset is monotone,
## so the game does not offer it there: removing an escapable arrow never makes a board harder.
func can_undo() -> bool:
	return status == Status.PLAYING and not history.is_empty() and bonus_undos > 0

func undo() -> Dictionary:
	if not can_undo():
		return {"type": "none"}
	var id := history[history.size() - 1]
	history.resize(history.size() - 1)
	board.restore(id)
	bonus_undos -= 1
	undos_used += 1
	streak = 0
	hint_target = -1
	return {"type": "undo", "id": id}

func hints_left() -> int:
	return free_hints + bonus_hints

## Returns {kind: "arrow"|"none", id, charged}. Asking again for a still-valid hint is free.
func request_hint() -> Dictionary:
	if status != Status.PLAYING:
		return {"kind": "none"}
	if hint_target != -1 and board.can_escape(hint_target):
		return {"kind": "arrow", "id": hint_target, "charged": false}
	if hints_left() <= 0:
		return {"kind": "none", "reason": "no_hints"}
	var id := ArrowSolver.best_hint(board)
	if id == -1:
		return {"kind": "none"}
	if free_hints > 0:
		free_hints -= 1
	else:
		bonus_hints -= 1
	hints_used += 1
	hint_target = id
	return {"kind": "arrow", "id": id, "charged": true}

func can_continue() -> bool:
	return status == Status.FAILED and continues_used == 0

func continue_with_life() -> bool:
	if not can_continue():
		return false
	continues_used += 1
	lives = 1
	status = Status.PLAYING
	_last_blocked.clear()
	return true

## The board as one char per arrow ("1" = alive).
func alive_key() -> String:
	var key := ""
	for id in board.size():
		key += "1" if board.is_alive(id) else "0"
	return key

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

## Arrows left on the board at the checkpoint.
func checkpoint_remaining() -> int:
	return checkpoint_alive.count("1")

func can_restore_checkpoint() -> bool:
	return status == Status.FAILED and has_checkpoint() and checkpoints_used < FREE_CHECKPOINT_RESTORES

## Back to the checkpoint board with full hearts. The board is rebuilt from the level by replaying
## the checkpoint moves with the real rule and must match the stored board exactly; otherwise
## nothing changes and false is returned.
func restore_checkpoint() -> bool:
	if not can_restore_checkpoint():
		return false
	var rebuilt := _replay(level, checkpoint)
	if rebuilt == null or _alive_key_of(rebuilt) != checkpoint_alive:
		return false
	board = rebuilt
	history = checkpoint.duplicate()
	checkpoints_used += 1
	lives = MAX_LIVES
	status = Status.PLAYING
	streak = 0
	hint_target = -1
	_last_blocked.clear()
	return true

static func _replay(level_data: Dictionary, moves: PackedInt32Array) -> ArrowBoard:
	var rebuilt := ArrowBoard.from_level(level_data)
	for id in moves:
		if not rebuilt.can_escape(id):
			return null
		rebuilt.remove(id)
	return rebuilt

static func _alive_key_of(b: ArrowBoard) -> String:
	var key := ""
	for id in b.size():
		key += "1" if b.is_alive(id) else "0"
	return key

func grant_bonus_hint() -> void:
	bonus_hints += 1

func grant_bonus_undo() -> void:
	bonus_undos += 1

func is_perfect() -> bool:
	return status == Status.CLEARED and mistakes == 0 and continues_used == 0

func to_save() -> Dictionary:
	return {"v": SAVE_VERSION, "rules": ArrowBoard.RULES, "level_id": level_id(), "hash": str(level.get("hash", "")),
		"mode": mode, "moves": Array(history), "lives": lives, "mistakes": mistakes, "status": int(status),
		"attempt_id": attempt_id, "retry_count": retry_count, "active_ms": active_ms, "streak": streak,
		"best_streak": best_streak, "free_hints": free_hints, "bonus_hints": bonus_hints, "hints_used": hints_used,
		"bonus_undos": bonus_undos, "undos_used": undos_used, "continues_used": continues_used,
		"hint_target": hint_target, "daily_date": daily_date, "applied_rewards": applied_rewards.duplicate(),
		"blocked_taps": blocked_taps, "wrong": wrong.keys(), "checkpoint": Array(checkpoint), "checkpoint_alive": checkpoint_alive,
		"checkpoints_used": checkpoints_used, "grace_left": grace_left}

## Rebuilds an attempt by replaying its moves with the real rule. Returns null for saves from other
## rules or content (including every legacy single-tile save) or any move that is no longer legal.
static func from_save(level_data: Dictionary, data: Dictionary) -> ArrowSession:
	if int(data.get("v", 0)) != SAVE_VERSION or str(data.get("rules", "")) != ArrowBoard.RULES:
		return null
	if str(data.get("hash", "")) != str(level_data.get("hash", "")):
		return null
	var session := create(level_data, str(data.get("mode", "campaign")), str(data.get("attempt_id", "")),
		int(data.get("retry_count", 0)))
	var moves: Variant = data.get("moves", [])
	if not moves is Array:
		return null
	for raw in moves:
		var id := int(raw)
		if not session.board.can_escape(id):
			return null
		session.board.remove(id)
		session.history.append(id)
	session.lives = clampi(int(data.get("lives", MAX_LIVES)), 0, MAX_LIVES)
	session.mistakes = maxi(0, int(data.get("mistakes", 0)))
	session.active_ms = maxi(0, int(data.get("active_ms", 0)))
	session.streak = maxi(0, int(data.get("streak", 0)))
	session.best_streak = maxi(session.streak, int(data.get("best_streak", 0)))
	session.free_hints = clampi(int(data.get("free_hints", FREE_HINTS)), 0, FREE_HINTS)
	session.bonus_hints = maxi(0, int(data.get("bonus_hints", 0)))
	session.hints_used = maxi(0, int(data.get("hints_used", 0)))
	session.bonus_undos = maxi(0, int(data.get("bonus_undos", 0)))
	session.undos_used = maxi(0, int(data.get("undos_used", 0)))
	session.continues_used = maxi(0, int(data.get("continues_used", 0)))
	session.daily_date = str(data.get("daily_date", ""))
	session.blocked_taps = maxi(0, int(data.get("blocked_taps", 0)))
	var saved_wrong: Variant = data.get("wrong", [])
	if saved_wrong is Array:
		for raw in saved_wrong:
			if int(raw) >= 0 and int(raw) < session.board.size():
				session.wrong[int(raw)] = true
	var applied: Variant = data.get("applied_rewards", [])
	session.applied_rewards = applied.duplicate() if applied is Array else []
	var target := int(data.get("hint_target", -1))
	session.hint_target = target if session.board.can_escape(target) else -1
	session.grace_left = clampi(int(data.get("grace_left", session.grace_left)), 0, session.grace_left)
	session.checkpoints_used = maxi(0, int(data.get("checkpoints_used", 0)))
	# A checkpoint is kept only when it is a prefix of the moves and still rebuilds the stored board.
	var saved_checkpoint: Variant = data.get("checkpoint", [])
	if session.uses_checkpoint and saved_checkpoint is Array and not (saved_checkpoint as Array).is_empty():
		var cp := PackedInt32Array()
		for raw in saved_checkpoint:
			cp.append(int(raw))
		var prefix := cp.size() <= session.history.size()
		for i in cp.size():
			if not prefix or cp[i] != session.history[i]:
				prefix = false
				break
		var rebuilt := _replay(level_data, cp) if prefix else null
		if rebuilt != null and _alive_key_of(rebuilt) == str(data.get("checkpoint_alive", "")):
			session.checkpoint = cp
			session.checkpoint_alive = str(data["checkpoint_alive"])
	if session.board.is_cleared():
		session.status = Status.CLEARED
	elif int(data.get("status", 0)) == Status.FAILED or session.lives == 0:
		session.status = Status.FAILED
		session.lives = 0
	return session
