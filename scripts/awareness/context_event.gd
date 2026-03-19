extends RefCounted
class_name ContextEvent

## Structured context event — timestamped, typed, ready for RAG storage.
## All context (screen, audio, vision, conversation) flows through this format.
##
## Event types:
##   "screen_change"       — desktop context changed (window, activity, idle)
##   "audio_transcript"    — system audio transcribed (YouTube, music, etc.)
##   "vision_description"  — vision model described what's on screen
##   "user_message"        — user sent a chat message
##   "kira_message"        — Kira responded
##   "emotion"             — emotion state changed
##   "screenshot"          — screenshot captured (stores metadata, not image)

var timestamp: float  # unix time
var event_type: String  # see types above
var data: Dictionary  # event-specific payload
var session_id: String  # groups events within a session


static func create(type: String, payload: Dictionary) -> ContextEvent:
	var e := ContextEvent.new()
	e.timestamp = Time.get_unix_time_from_system()
	e.event_type = type
	e.data = payload
	return e


func to_dict() -> Dictionary:
	return {
		"ts": timestamp,
		"type": event_type,
		"data": data,
		"session": session_id,
	}
