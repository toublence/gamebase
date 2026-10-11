class_name Nav
extends RefCounted
## Screen routing for Outtap. A play request is stored on Progress and consumed by the game module
## once it mounts, so a pending request can never leak into a later board.

static func play_campaign(index: int) -> bool:
	Progress.request = {"mode": "campaign", "index": clampi(index, 1, Levels.campaign_count())}
	return _go("game")

## Continues the saved attempt when there is one, otherwise the furthest unlocked stage.
static func continue_game() -> bool:
	var active := Progress.active_attempt()
	if not active.is_empty() and str(active.get("rules", "")) == ArrowBoard.RULES and not Levels.by_id(str(active.get("level_id", ""))).is_empty():
		Progress.request = {"mode": "campaign", "resume": true}
		return _go("game")
	return play_campaign(Progress.reached())

static func home() -> bool:
	return _go("menu")

static func levels(tab: String = "campaign") -> bool:
	Progress.levels_tab = tab
	return _go("levels")

static func _go(route: String) -> bool:
	if AdsManager.is_presenting():
		return false
	# Leaving the game, or opening a new board from a game screen: end the current session first so
	# the new game screen always starts its own.
	if route != "game" or GameSession.state != GameSession.State.IDLE:
		GameSession.stop()
	return SceneManager.go_to(route)
