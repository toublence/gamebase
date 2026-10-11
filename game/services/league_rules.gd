class_name LeagueRules
extends RefCounted
## Personal weekly league — honest by design. There are no other players and no server: every point
## comes from the player's own clears on this device, the goal lines per tier are fixed, and the only
## "rival" shown is the player's own previous week and best week.
##
## Points (each part counted once per stage per week, so replays matter but cannot be farmed):
##   golden arrows on the board  +1 each
##   HARD stage cleared          +2
##   perfect clear (no mistakes) +1
##   first clear ever of a stage +1 (once, not weekly)
## Promotion is immediate: when this week's points pass the tier's line, the tier goes up and the
## next line starts from there. At the week's end a tier is kept when the week reached its keep line,
## otherwise it drops one step (every missed week counts as a week with 0 points).
const TIERS := ["bronze", "silver", "gold", "platinum", "diamond"]
const NAMES := ["LEAGUE_BRONZE", "LEAGUE_SILVER", "LEAGUE_GOLD", "LEAGUE_PLATINUM", "LEAGUE_DIAMOND"]
const COLORS := ["C9834B", "9FB0C3", "E2B23F", "57C1C4", "8EA9FF"]
const PROMOTE := [10, 16, 22, 28, 0]
const KEEP := [0, 4, 8, 12, 16]
const TOP := 4
const POINTS := {"gold": 1, "hard": 2, "perfect": 1, "first_clear": 1}
const DAY := 86400

static func tier_color(tier: int) -> Color:
	return Color(COLORS[clampi(tier, 0, TOP)])

static func tier_name(tier: int) -> String:
	return NAMES[clampi(tier, 0, TOP)]

## Local Monday 00:00 of the week containing `unix`, as unix seconds.
static func week_start(unix: int) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := unix + bias
	var day_start := local - posmod(local, DAY)
	var weekday := int(Time.get_datetime_dict_from_unix_time(day_start)["weekday"]) # 0 = Sunday
	var since_monday := (weekday + 6) % 7
	return day_start - since_monday * DAY - bias

## "YYYY-MM-DD" of the local Monday that starts the week.
static func week_key(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(week_start(unix) + bias)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func seconds_left(unix: int) -> int:
	return maxi(0, week_start(unix) + 7 * DAY - unix)

## Whole weeks between two week keys (0 when equal or out of order).
static func weeks_between(from_key: String, to_key: String) -> int:
	var a := _key_unix(from_key)
	var b := _key_unix(to_key)
	if a < 0 or b < 0 or b <= a:
		return 0
	return int(round(float(b - a) / (7 * DAY)))

static func _key_unix(key: String) -> int:
	var parts := key.split("-")
	if parts.size() != 3:
		return -1
	return Time.get_unix_time_from_datetime_dict({"year": int(parts[0]), "month": int(parts[1]), "day": int(parts[2]),
		"hour": 12, "minute": 0, "second": 0})

## Tier after a finished week with `points`.
static func settle(tier: int, points: int) -> int:
	return tier if points >= KEEP[clampi(tier, 0, TOP)] else maxi(0, tier - 1)

## Points one clear earns this week. `claim` is what this stage already paid out this week
## ({gold: int, hard: bool, perfect: bool}); the result carries the updated claim.
static func clear_points(level: Dictionary, perfect: bool, first_clear: bool, claim: Dictionary) -> Dictionary:
	var parts := {"gold": 0, "hard": 0, "perfect": 0, "first_clear": 0}
	var gold_count: int = (level.get("gold", []) as Array).size()
	var paid_gold := int(claim.get("gold", 0))
	if gold_count > paid_gold:
		parts["gold"] = (gold_count - paid_gold) * int(POINTS["gold"])
	if bool(level.get("hard", false)) and not bool(claim.get("hard", false)):
		parts["hard"] = int(POINTS["hard"])
	if perfect and not bool(claim.get("perfect", false)):
		parts["perfect"] = int(POINTS["perfect"])
	if first_clear:
		parts["first_clear"] = int(POINTS["first_clear"])
	var total := 0
	for key in parts:
		total += int(parts[key])
	var updated := {"gold": maxi(paid_gold, gold_count), "hard": bool(claim.get("hard", false)) or bool(level.get("hard", false)),
		"perfect": bool(claim.get("perfect", false)) or perfect}
	return {"parts": parts, "total": total, "claim": updated}

## Applies `gained` points: returns {tier, base, promotions: [tiers reached]}.
static func promote(tier: int, base: int, points: int) -> Dictionary:
	var promotions: Array = []
	var t := tier
	var b := base
	while t < TOP and points - b >= PROMOTE[t]:
		b += PROMOTE[t]
		t += 1
		promotions.append(t)
	return {"tier": t, "base": b, "promotions": promotions}
