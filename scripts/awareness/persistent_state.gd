extends Node
class_name PersistentState

signal state_loaded
signal state_saved
signal familiarity_changed(new_value: float)
signal new_day

const SAVE_PATH := "user://kira_state.json"
const MAX_KEY_FACTS := 20

@export var save_interval := 60.0

var state := {
	# Mood
	"mood": "content",
	"mood_momentum": 0.0,

	# Interaction tracking
	"last_interaction_time": 0,
	"interactions_today": 0,
	"interactions_this_week": 0,
	"total_interactions": 0,
	"first_seen": 0,
	"last_session_start": 0,
	"total_sessions": 0,

	# Relationship
	"familiarity": 0.0,
	"nickname": "",

	# Context preferences
	"favorite_apps": {},
	"active_hours": {},
	"conversation_topics": [],

	# Last emotion
	"last_emotion": "neutral",
	"last_emotion_intensity": 0.0,

	# Conversation summary
	"conversation_summary": "",
	"key_facts": [],
}

var _save_timer := 0.0
var _last_check_day := -1


func _ready() -> void:
	load_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_state()


func update(delta: float) -> void:
	_save_timer += delta
	if _save_timer >= save_interval:
		_save_timer = 0.0
		save_state()

	_check_daily_reset()


func load_state() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_init_first_run()
		save_state()
		state_loaded.emit()
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("PersistentState: Could not open save file, using defaults.")
		_init_first_run()
		state_loaded.emit()
		return

	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		push_warning("PersistentState: Corrupted save file, using defaults.")
		_init_first_run()
		save_state()
		state_loaded.emit()
		return

	# Merge loaded data onto defaults so new keys are preserved
	var loaded: Dictionary = parsed
	for key in state.keys():
		if loaded.has(key):
			state[key] = loaded[key]

	_begin_session()
	state_loaded.emit()


func save_state() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("PersistentState: Could not write save file.")
		return

	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	state_saved.emit()


func record_interaction() -> void:
	var now := _now()
	state["last_interaction_time"] = now
	state["interactions_today"] = int(state["interactions_today"]) + 1
	state["interactions_this_week"] = int(state["interactions_this_week"]) + 1
	state["total_interactions"] = int(state["total_interactions"]) + 1

	_grow_familiarity()

	# Track active hour
	var hour := Time.get_date_dict_from_system()["hour"] as int if false else Time.get_time_dict_from_system()["hour"] as int
	var hour_key := str(hour)
	var hours: Dictionary = state["active_hours"]
	hours[hour_key] = int(hours.get(hour_key, 0)) + 1
	state["active_hours"] = hours


func record_context(context: Dictionary) -> void:
	if context.has("app_name") and context["app_name"] != "":
		var app_name: String = context["app_name"]
		var apps: Dictionary = state["favorite_apps"]
		apps[app_name] = int(apps.get(app_name, 0)) + 1
		state["favorite_apps"] = apps


func update_mood(mood: String, momentum: float) -> void:
	state["mood"] = mood
	state["mood_momentum"] = clampf(momentum, -1.0, 1.0)


func add_key_fact(fact: String) -> void:
	var facts: Array = state["key_facts"]
	# Avoid duplicates
	if fact in facts:
		return
	facts.append(fact)
	# FIFO: drop oldest if over limit
	while facts.size() > MAX_KEY_FACTS:
		facts.pop_front()
	state["key_facts"] = facts


func set_conversation_summary(summary: String) -> void:
	state["conversation_summary"] = summary


func get_greeting_context() -> Dictionary:
	var now := _now()
	var hour: int = Time.get_time_dict_from_system()["hour"]
	var last_interaction: float = float(state["last_interaction_time"])
	var seconds_since := now - last_interaction if last_interaction > 0 else -1.0

	var time_of_day := "night"
	if hour >= 5 and hour < 12:
		time_of_day = "morning"
	elif hour >= 12 and hour < 17:
		time_of_day = "afternoon"
	elif hour >= 17 and hour < 21:
		time_of_day = "evening"

	var is_new_day := false
	if last_interaction > 0:
		var last_date := Time.get_date_dict_from_unix_time(int(last_interaction))
		var current_date := Time.get_date_dict_from_system()
		is_new_day = (last_date["day"] != current_date["day"]
			or last_date["month"] != current_date["month"]
			or last_date["year"] != current_date["year"])

	return {
		"seconds_since_last_seen": seconds_since,
		"familiarity": float(state["familiarity"]),
		"familiarity_label": get_familiarity_label(),
		"time_of_day": time_of_day,
		"is_new_day": is_new_day,
		"session_count": int(state["total_sessions"]),
		"nickname": state["nickname"],
	}


func get_time_since_last_interaction() -> float:
	var last: float = float(state["last_interaction_time"])
	if last <= 0:
		return -1.0
	return _now() - last


func get_familiarity_label() -> String:
	var f: float = float(state["familiarity"])
	if f < 0.15:
		return "stranger"
	elif f < 0.4:
		return "acquaintance"
	elif f < 0.75:
		return "friend"
	else:
		return "close friend"


# --- Private ---

func _now() -> float:
	return Time.get_unix_time_from_system()


func _init_first_run() -> void:
	var now := _now()
	state["first_seen"] = now
	state["last_session_start"] = now
	state["total_sessions"] = 1
	_last_check_day = Time.get_date_dict_from_system()["day"]


func _begin_session() -> void:
	var now := _now()
	state["last_session_start"] = now
	state["total_sessions"] = int(state["total_sessions"]) + 1

	if int(state["first_seen"]) == 0:
		state["first_seen"] = now

	_last_check_day = Time.get_date_dict_from_system()["day"]
	_check_daily_reset()


func _grow_familiarity() -> void:
	var current: float = float(state["familiarity"])
	var new_value := minf(1.0, current + 0.001 * (1.0 - current))
	if new_value != current:
		state["familiarity"] = new_value
		familiarity_changed.emit(new_value)


func _check_daily_reset() -> void:
	var date := Time.get_date_dict_from_system()
	var today: int = date["day"]

	if _last_check_day == -1:
		_last_check_day = today
		return

	if today != _last_check_day:
		_last_check_day = today
		state["interactions_today"] = 0
		new_day.emit()

		# Weekly reset on Monday (weekday 1 in Godot)
		var weekday: int = date["weekday"]
		if weekday == Time.WEEKDAY_MONDAY:
			state["interactions_this_week"] = 0
