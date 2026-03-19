extends Node
class_name AmbientLLM

## Handles ambient (unprompted) LLM queries — Kira reacting to context
## changes or initiating conversation on her own.
##
## Receives requests from the behavior tree via request_query(), applies
## rate limiting and smart filtering, builds context-aware prompts, then
## sends through the voice pipeline. Responses flow back through the
## normal chat path (hub_client.chat_response or direct mode).

signal query_sent(prompt: String, query_type: String)
signal query_blocked(reason: String)

# ── Configuration ─────────────────────────────────────────────────────────────

## Minimum seconds between ambient queries.
var min_interval := 120.0

## Debounce window — ignore rapid context changes within this window.
var debounce_seconds := 5.0

# ── Query types ───────────────────────────────────────────────────────────────

enum QueryType { REACTION, OBSERVATION, INITIATION, GREETING, COMMENT }

const QUERY_TYPE_NAMES := {
	QueryType.REACTION: "reaction",
	QueryType.OBSERVATION: "observation",
	QueryType.INITIATION: "initiation",
	QueryType.GREETING: "greeting",
	QueryType.COMMENT: "comment",
}

# ── Internal state ────────────────────────────────────────────────────────────

var _voice_pipeline: Node  # VoicePipeline
var _hub_client: Node      # HubClient — for direct ambient sends
var _last_query_time := 0.0
var _last_context_change_time := 0.0
var _mood := "content"
var _behavior_state := "observing"
var _last_activity := ""
var _last_window_title := ""
var _setup_done := false


# ── Setup ─────────────────────────────────────────────────────────────────────

func setup(voice_pipeline: Node, hub_client: Node = null) -> void:
	_voice_pipeline = voice_pipeline
	_hub_client = hub_client
	_setup_done = true
	print("[ambient] Setup complete")


# ── Public API ────────────────────────────────────────────────────────────────

func request_query(prompt: String, query_type: String, context: Dictionary) -> bool:
	"""Attempt an ambient query. Returns true if sent, false if blocked."""
	if not _setup_done or _voice_pipeline == null:
		query_blocked.emit("not_setup")
		return false

	# Map string type to enum for internal use
	var qt := _parse_query_type(query_type)

	# ── Filtering ─────────────────────────────────────────────────────────
	# Don't query while user is actively chatting
	if _behavior_state == "attentive":
		query_blocked.emit("user_attentive")
		print("[ambient] Blocked: user is attentive")
		return false

	# Rate limit
	if not can_query():
		var remaining := get_cooldown_remaining()
		query_blocked.emit("rate_limit (%.0fs remaining)" % remaining)
		print("[ambient] Blocked: rate limit (%.0fs remaining)" % remaining)
		return false

	# Debounce rapid context changes (except greetings/initiations)
	if qt == QueryType.REACTION or qt == QueryType.OBSERVATION:
		var now := Time.get_unix_time_from_system()
		var since_change := now - _last_context_change_time
		if since_change < debounce_seconds and _last_context_change_time > 0.0:
			query_blocked.emit("debounce (%.1fs)" % since_change)
			print("[ambient] Blocked: debounce (%.1fs since last change)" % since_change)
			return false

	# Filter trivial tab switches — same activity, just different tab
	if qt == QueryType.REACTION:
		var new_activity: String = context.get("activity", "unknown")
		var new_title: String = context.get("window_title", "")
		if _is_trivial_switch(new_activity, new_title):
			query_blocked.emit("trivial_switch")
			print("[ambient] Blocked: trivial switch")
			return false

	# Check pipeline is idle — don't interrupt active speech/processing
	if _voice_pipeline.current_state != _voice_pipeline.PipelineState.IDLE:
		query_blocked.emit("pipeline_busy")
		print("[ambient] Blocked: pipeline busy")
		return false

	# ── Build and send ────────────────────────────────────────────────────
	var full_prompt := _build_prompt(prompt, qt, context)

	_last_query_time = Time.get_unix_time_from_system()
	_update_tracking(context)

	# Send directly to hub as a chat request with the context as system framing.
	# The full_prompt goes as the user message — but we DON'T display it in chat.
	# The companion extension's system prompt + our context = Kira's natural response.
	if _hub_client and _hub_client._is_connected:
		_hub_client.send_chat(full_prompt, [])
	else:
		_voice_pipeline.send_text(full_prompt)

	query_sent.emit(_type_name(qt), _type_name(qt))
	print("[ambient] Sent %s query" % _type_name(qt))
	return true


func set_mood(mood: String) -> void:
	_mood = mood


func set_behavior_state(state: String) -> void:
	_behavior_state = state


func can_query() -> bool:
	"""Check if rate limit allows a query right now."""
	if _last_query_time <= 0.0:
		return true
	return get_cooldown_remaining() <= 0.0


func get_cooldown_remaining() -> float:
	"""Seconds until next query is allowed. 0 if ready."""
	if _last_query_time <= 0.0:
		return 0.0
	var elapsed := Time.get_unix_time_from_system() - _last_query_time
	return maxf(0.0, min_interval - elapsed)


func on_context_changed(context: Dictionary) -> void:
	"""Call when screen context changes — updates debounce tracking."""
	_last_context_change_time = Time.get_unix_time_from_system()


# ── Prompt Building ───────────────────────────────────────────────────────────

func _build_prompt(raw_prompt: String, qt: QueryType, context: Dictionary) -> String:
	var activity: String = context.get("activity", "something")
	var title: String = context.get("window_title", "")
	var time_of_day: String = context.get("time_of_day", "afternoon")
	var idle_min: float = context.get("idle_minutes", 0.0)

	# System context block
	var parts: PackedStringArray = []
	parts.append("You are Kira, observing your user's desktop.")
	parts.append("Current context: User is %s" % activity)
	if title != "":
		parts.append(' — window: "%s"' % _sanitize_title(title))
	else:
		parts.append(".")
	# Background media (YouTube, Spotify, etc. playing in another window)
	var bg_media: String = context.get("background_media", "")
	if bg_media != "":
		parts.append(". Also %s in the background" % bg_media)

	parts.append("\nTime: %s. Your mood: %s." % [
		_format_time_of_day(time_of_day), _mood,
	])
	if idle_min > 1.0:
		parts.append(" User has been idle for %d minutes." % int(idle_min))

	# Query-type specific instruction
	parts.append("\n")
	match qt:
		QueryType.REACTION:
			parts.append(
				"Something just changed on their screen. "
				+ "React briefly and naturally — like you noticed."
			)
		QueryType.OBSERVATION:
			parts.append(
				"Share a brief observation about what they're doing. "
				+ "Be casual, like thinking out loud."
			)
		QueryType.INITIATION:
			parts.append(
				"Start a casual, unprompted thought or question. "
				+ "Something a companion would say to break comfortable silence."
			)
		QueryType.GREETING:
			parts.append(
				"Greet them naturally for the %s. " % _format_time_of_day(time_of_day)
				+ "Be warm but not over the top."
			)
		QueryType.COMMENT:
			parts.append(
				"Make a brief, natural comment. Keep it light."
			)

	parts.append("\nKeep your response to 1-2 sentences max. Be natural and casual.")
	parts.append("\nNever mention that you're an AI or that you're watching their screen.")
	parts.append("\nReact as a companion who lives on the desktop would.")

	# Append the raw prompt from behavior tree as additional direction
	if raw_prompt != "":
		parts.append("\n\nAdditional context: " + raw_prompt)

	return "".join(parts)


func _sanitize_title(title: String) -> String:
	"""Truncate and clean window title for prompt inclusion."""
	# Strip potentially sensitive URL paths, keep the meaningful part
	var clean := title.strip_edges()
	if clean.length() > 120:
		clean = clean.substr(0, 120) + "..."
	return clean


func _format_time_of_day(tod: String) -> String:
	match tod:
		"late_night": return "late night"
		"morning": return "morning"
		"afternoon": return "afternoon"
		"evening": return "evening"
		"night": return "night"
	return tod


# ── Smart Filtering ───────────────────────────────────────────────────────────

func _is_trivial_switch(new_activity: String, new_title: String) -> bool:
	"""Detect trivial tab switches that don't warrant a reaction."""
	# Same activity type (e.g. browsing → browsing) = tab switch
	if new_activity == _last_activity and new_activity == "browsing":
		return true

	# Same activity, minor title change (same app, different file/tab)
	if new_activity == _last_activity and new_activity != "unknown":
		# If both titles share a common app identifier, it's trivial
		var old_base := _extract_app_name(_last_window_title)
		var new_base := _extract_app_name(new_title)
		if old_base != "" and old_base == new_base:
			return true

	return false


func _extract_app_name(title: String) -> String:
	"""Extract the application name from a window title.
	Many apps use 'Document - AppName' or 'AppName - Document' format."""
	if title.is_empty():
		return ""
	# Common patterns: "file.py - Visual Studio Code", "Tab Title - Firefox"
	var parts := title.split(" - ")
	if parts.size() >= 2:
		# Usually the app name is the last segment
		return parts[-1].strip_edges().to_lower()
	# Or "AppName: something"
	parts = title.split(": ")
	if parts.size() >= 2:
		return parts[0].strip_edges().to_lower()
	return title.strip_edges().to_lower()


# ── Tracking ──────────────────────────────────────────────────────────────────

func _update_tracking(context: Dictionary) -> void:
	_last_activity = context.get("activity", "unknown")
	_last_window_title = context.get("window_title", "")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _parse_query_type(type_str: String) -> QueryType:
	match type_str.to_lower():
		"reaction": return QueryType.REACTION
		"observation": return QueryType.OBSERVATION
		"initiation": return QueryType.INITIATION
		"greeting": return QueryType.GREETING
		"comment": return QueryType.COMMENT
	return QueryType.COMMENT


func _type_name(qt: QueryType) -> String:
	return QUERY_TYPE_NAMES.get(qt, "unknown")
